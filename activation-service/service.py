"""AppStore+ private activation service. Bind to loopback behind an HTTPS proxy.
No Apple account registration/signing provider is implicitly configured.
"""
import argparse
import base64
import hashlib
import hmac
import json
import math
import os
import re
import secrets
import sqlite3
import subprocess
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.hazmat.primitives import serialization as ser
import plistlib


def compact(value):
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode()


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def date(value):
    return datetime.fromtimestamp(value, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def https(value):
    u = urlsplit(value)
    if u.scheme != 'https' or not u.hostname or u.username or u.password or u.fragment:
        raise ValueError('Expected a public HTTPS URL without credentials or fragments')
    return value


class APIError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


class Store:
    def __init__(self, path, master_key):
        if len(master_key) != 32:
            raise ValueError('APPSTORE_MASTER_KEY must be base64 encoded 32 random bytes')
        self.path, self.cipher = str(path), AESGCM(master_key)
        Path(path).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS accounts (
              id TEXT PRIMARY KEY, telegram_id INTEGER NOT NULL, device_id TEXT NOT NULL,
              starts REAL NOT NULL, ends REAL NOT NULL, cert_ends REAL NOT NULL,
              revoked INTEGER NOT NULL DEFAULT 0, credentials BLOB NOT NULL,
              code_hash TEXT UNIQUE NOT NULL, code_ends REAL NOT NULL,
              public_key BLOB, install_url TEXT, created REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS sessions (
              token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL, expires REAL NOT NULL,
              FOREIGN KEY(account_id) REFERENCES accounts(id));
            CREATE TABLE IF NOT EXISTS nonces (
              account_id TEXT NOT NULL, nonce TEXT NOT NULL, expires REAL NOT NULL,
              PRIMARY KEY(account_id,nonce));
            CREATE TABLE IF NOT EXISTS failures (bucket TEXT PRIMARY KEY, count INTEGER, until REAL);
            CREATE TABLE IF NOT EXISTS bot_state (id INTEGER PRIMARY KEY CHECK(id=1), offset INTEGER);
            ''')
        os.chmod(self.path, 0o600)

    @contextmanager
    def db(self):
        con = sqlite3.connect(self.path, timeout=15, isolation_level=None)
        con.row_factory = sqlite3.Row
        con.execute('PRAGMA foreign_keys=ON')
        con.execute('PRAGMA secure_delete=ON')
        try:
            con.execute('BEGIN IMMEDIATE')
            yield con
            if con.in_transaction: con.execute('COMMIT')
        except BaseException:
            if con.in_transaction: con.execute('ROLLBACK')
            raise
        finally:
            con.close()

    def seal(self, account_id, payload):
        nonce = os.urandom(12)
        return nonce + self.cipher.encrypt(nonce, compact(payload), account_id.encode())

    def open(self, row):
        data = row['credentials']
        return json.loads(self.cipher.decrypt(data[:12], data[12:], row['id'].encode()))

    def provision(self, telegram_id, device_id, payload, starts, ends, cert_ends):
        now = time.time()
        if telegram_id <= 0 or not device_id or not starts < ends <= cert_ends or cert_ends <= now:
            raise ValueError('Invalid recipient or dates; access must end by certificate/profile expiry')
        account_id, code = secrets.token_urlsafe(18), secrets.token_urlsafe(32)
        with self.db() as db:
            db.execute('INSERT INTO accounts VALUES(?,?,?,?,?,?,0,?,?,?,NULL,NULL,?)',
                       (account_id, telegram_id, device_id, starts, ends, cert_ends,
                        self.seal(account_id, payload), digest(code), min(ends, now + 7*86400), now))
        return account_id, code

    @staticmethod
    def status(row):
        now = time.time()
        state = ('revoked' if row['revoked'] else 'pending' if now < row['starts'] else
                 'expired' if now >= min(row['ends'], row['cert_ends']) else 'active')
        return dict(accountID=row['id'], status=state, connectedAt=date(row['starts']),
                    expiresAt=date(row['ends']), certificateExpiresAt=date(row['cert_ends']),
                    remainingDays=max(0, math.ceil((min(row['ends'], row['cert_ends'])-now)/86400)),
                    deviceID=row['device_id'])

    def activate(self, data):
        try:
            code, raw = data['code'], base64.b64decode(data['publicKey'], validate=True)
            if not isinstance(code, str) or not 32 <= len(code) <= 100 or len(raw) != 65:
                raise ValueError()
            key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)
            signature = base64.b64decode(data['signature'], validate=True)
            key.verify(signature, ('AppStore+ activate\n'+code).encode(), ec.ECDSA(hashes.SHA256()))
        except (KeyError, ValueError, TypeError, InvalidSignature):
            raise APIError(401, 'invalid_activation')
        with self.db() as db:
            row = db.execute('SELECT * FROM accounts WHERE code_hash=?', (digest(code),)).fetchone()
            if row is None or row['code_ends'] <= time.time():
                raise APIError(401, 'invalid_activation')
            if row['public_key'] is not None and not hmac.compare_digest(bytes(row['public_key']), raw):
                raise APIError(409, 'activation_already_bound')
            if not self.enrollment_allowed(row):
                raise APIError(403, 'access_inactive')
            # Idempotent retry on the same key if a network response was lost.
            db.execute('UPDATE accounts SET public_key=? WHERE id=?', (raw, row['id']))
            token = secrets.token_urlsafe(32)
            db.execute('DELETE FROM sessions WHERE account_id=?', (row['id'],))
            db.execute('INSERT INTO sessions VALUES(?,?,?)', (digest(token),row['id'],row['ends']))
        return dict(token=token, subscription=self.status(row))

    def enrollment_allowed(self, row):
        return self.status(row)['status'] == 'active'

    def delivery_allowed(self, row):
        return self.enrollment_allowed(row)

    def credentials_allowed(self, row):
        return self.enrollment_allowed(row)

    def authenticated(self, path, headers, body=b'', method='GET'):
        try:
            auth = headers.get('Authorization', '')
            if not auth.startswith('Bearer '):
                raise ValueError()
            token = auth[7:]
            stamp, nonce = headers['X-Store-Time'], headers['X-Store-Nonce']
            if abs(time.time()-int(stamp)) > 120 or not re.fullmatch(r'[A-Za-z0-9-]{16,80}', nonce):
                raise ValueError()
            signature = base64.b64decode(headers['X-Store-Signature'], validate=True)
        except (KeyError, ValueError, TypeError):
            raise APIError(401, 'invalid_session')
        with self.db() as db:
            row = db.execute('SELECT a.*,s.expires AS session_ends FROM accounts a JOIN sessions s '
                             'ON a.id=s.account_id WHERE s.token_hash=?', (digest(token),)).fetchone()
            if row is None or row['session_ends'] <= time.time():
                raise APIError(401, 'invalid_session')
            key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), row['public_key'])
            canonical = '\n'.join([method,path,hashlib.sha256(body).hexdigest(),stamp,nonce]).encode()
            try:
                key.verify(signature, canonical, ec.ECDSA(hashes.SHA256()))
            except InvalidSignature:
                raise APIError(401, 'invalid_session')
            db.execute('DELETE FROM nonces WHERE expires<?', (time.time(),))
            try:
                db.execute('INSERT INTO nonces VALUES(?,?,?)', (row['id'],nonce,time.time()+240))
            except sqlite3.IntegrityError:
                raise APIError(409, 'request_replayed')
            return dict(row)

    def rate_limit(self, identity):
        # Persist abuse protection across server restarts. IP must be forwarded only by a trusted proxy.
        bucket, now = digest(identity), time.time()
        with self.db() as db:
            db.execute('DELETE FROM failures WHERE until<?', (now,))
            row = db.execute('SELECT * FROM failures WHERE bucket=?', (bucket,)).fetchone()
            if row and row['count'] >= 15:
                raise APIError(429, 'try_later')
            db.execute('INSERT INTO failures VALUES(?,1,?) ON CONFLICT(bucket) DO UPDATE SET count=count+1',
                       (bucket, now+300))

    def account(self, account_id):
        with self.db() as db:
            return db.execute('SELECT * FROM accounts WHERE id=?', (account_id,)).fetchone()


def handler(store, delivery=None):
    class Handler(BaseHTTPRequestHandler):
        server_version = 'AppStorePlus'
        def log_message(self, *_):
            pass  # Never record personal install links, codes, tokens, or certificate bodies.

        def reply(self, status, data):
            body = compact(data)
            self.send_response(status)
            self.send_header('Content-Type','application/json; charset=utf-8')
            self.send_header('Content-Length',str(len(body)))
            self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff')
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            try:
                if self.path not in ('/v1/activate','/v1/license/redeem'):
                    raise APIError(404,'not_found')
                if self.path == '/v1/activate': store.rate_limit(self.client_address[0])
                size = int(self.headers.get('Content-Length',0))
                if not 1 <= size <= 4096 or self.headers.get_content_type() != 'application/json':
                    raise APIError(400,'invalid_request')
                raw = self.rfile.read(size)
                body = json.loads(raw)
                if not isinstance(body,dict): raise APIError(400,'invalid_request')
                if self.path == '/v1/activate':
                    result = store.activate(body)
                else:
                    if not hasattr(store,'redeem_key'): raise APIError(404,'not_found')
                    row = store.authenticated(self.path,self.headers,raw,method='POST')
                    store.rate_limit('license:'+row['id'])
                    result = store.redeem_key(row,body.get('key'))
                self.reply(200,result)
            except APIError as error:
                self.reply(error.status,dict(error=error.code))
            except (ValueError, TypeError, KeyError):
                self.reply(400,dict(error='invalid_request'))
            except Exception:
                self.reply(500,dict(error='service_unavailable'))

        def do_GET(self):
            try:
                if delivery is not None and self.path.startswith('/delivery/'):
                    from delivery import serve_file
                    serve_file(self, *delivery.resolve(self.path))
                    return
                if self.path not in ('/v1/subscription','/v1/credentials'):
                    raise APIError(404,'not_found')
                row = store.authenticated(self.path,self.headers)
                status = store.status(row)
                if self.path == '/v1/subscription':
                    self.reply(200,status)
                elif not store.credentials_allowed(row):
                    raise APIError(403,'access_inactive')
                else:
                    self.reply(200,dict(subscription=status,**store.open(row)))
            except APIError as error:
                self.reply(error.status,dict(error=error.code))
            except Exception:
                self.reply(500,dict(error='service_unavailable'))
        def do_HEAD(self):
            try:
                if delivery is None:
                    raise APIError(404,'not_found')
                from delivery import serve_file
                serve_file(self, *delivery.resolve(self.path), head=True)
            except APIError as error:
                self.send_response(error.status)
                self.send_header('Content-Length','0')
                self.end_headers()
    return Handler


def validate_credentials(p12_path, profile_path, password, device_id):
    p12, profile = Path(p12_path).read_bytes(), Path(profile_path).read_bytes()
    return validate_credential_bytes(p12, profile, password, device_id)


def validate_credential_bytes(p12, profile, password, device_id):
    if len(p12)+len(profile) > 1024*1024:
        raise ValueError('Certificate package too large')
    key, cert, _ = pkcs12.load_key_and_certificates(p12,password.encode() or None)
    if key is None or cert is None:
        raise ValueError('P12 must include its private key and certificate')
    decoded = subprocess.run(['openssl','cms','-verify','-inform','DER','-noverify'],
                             input=profile,capture_output=True,check=True,timeout=15).stdout
    info = plistlib.loads(decoded)
    if device_id not in info.get('ProvisionedDevices',[]):
        raise ValueError('Device UDID absent from mobileprovision')
    if cert.public_bytes(ser.Encoding.DER) not in info.get('DeveloperCertificates',[]):
        raise ValueError('P12 and mobileprovision do not match')
    expiry = min(cert.not_valid_after_utc.timestamp(),info['ExpirationDate'].replace(tzinfo=timezone.utc).timestamp())
    if expiry <= time.time():
        raise ValueError('Certificate/profile already expired')
    return dict(p12=base64.b64encode(p12).decode(),profile=base64.b64encode(profile).decode(),password=password,
                fingerprint=hashlib.sha256(p12+profile).hexdigest()), expiry


def configured_store():
    store_type = Store
    if os.environ.get('APPSTORE_PAID_ACCESS','1') == '1':
        from licenses import LicenseStore
        store_type = LicenseStore
    return store_type(os.environ.get('APPSTORE_DB','activation-state/store.sqlite3'),
                 base64.b64decode(os.environ['APPSTORE_MASTER_KEY'],validate=True))


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command',required=True)
    sub.add_parser('serve')
    for command in ('provision', 'provision-one'):
        p = sub.add_parser(command)
        for name in ('telegram-id','device-id','ends','endpoint','out'):
            p.add_argument('--'+name,required=True)
        if command == 'provision':
            for name in ('p12','profile','password-file'):
                p.add_argument('--'+name,required=True)
        else:
            p.add_argument('--response',required=True,help='Private One_iBot certificate response JSON')
            p.add_argument('--password-file',help='Explicit password override if provider omitted it')
    link = sub.add_parser('set-install-url')
    link.add_argument('account_id'); link.add_argument('url')
    revoke = sub.add_parser('revoke'); revoke.add_argument('account_id')
    args = parser.parse_args()
    store = configured_store()
    if args.command == 'serve':
        from delivery import configured_delivery
        delivery = configured_delivery(store, optional=True)
        server = ThreadingHTTPServer(('127.0.0.1',8787),handler(store, delivery))
        server.socket.settimeout(15)
        server.serve_forever()
    elif args.command in ('provision', 'provision-one'):
        if args.command == 'provision-one':
            from one_provider import certificate_payload
            override = Path(args.password_file).read_text().rstrip('\r\n') if args.password_file else None
            if Path(args.response).stat().st_size > 2 * 1024 * 1024:
                raise ValueError('Provider response too large')
            payload, expiry = certificate_payload(json.loads(Path(args.response).read_text(encoding='utf-8-sig')),args.device_id,override)
        else:
            payload, expiry = validate_credentials(args.p12,args.profile,Path(args.password_file).read_text().rstrip('\r\n'),args.device_id)
        ends = datetime.fromisoformat(args.ends.replace('Z','+00:00'))
        if ends.tzinfo is None: raise ValueError('Use an explicit timezone')
        path = Path(args.out)
        if path.exists(): raise ValueError('Output exists; choose a new private file')
        endpoint = https(args.endpoint).rstrip('/')
        if urlsplit(endpoint).path or urlsplit(endpoint).query: raise ValueError('Use the root HTTPS origin for the activation service')
        account_id, code = store.provision(int(args.telegram_id),args.device_id,payload,time.time(),ends.timestamp(),expiry)
        path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        with path.open('x') as file:
            json.dump(dict(endpoint=endpoint,code=code,deviceID=args.device_id),file)
        os.chmod(path,0o600)
        print('Account ID:',account_id)  # No activation code or certificate secret on stdout.
        print('Private bootstrap written; inject into the IPA BEFORE signing.')
    elif args.command == 'set-install-url':
        https(args.url)
        with store.db() as db:
            if not db.execute('UPDATE accounts SET install_url=? WHERE id=?',(args.url,args.account_id)).rowcount:
                raise ValueError('Unknown account')
    elif args.command == 'revoke':
        with store.db() as db:
            db.execute('UPDATE accounts SET revoked=1 WHERE id=?',(args.account_id,))
            db.execute('DELETE FROM sessions WHERE account_id=?',(args.account_id,))

if __name__ == '__main__':
    main()
