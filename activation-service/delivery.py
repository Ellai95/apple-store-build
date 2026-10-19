"""Prepare a personal AppStore+ IPA and privately serve its OTA installation files."""
import base64
import html
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile
import time
from urllib.parse import quote
import zipfile

from personalize import personalize
from service import APIError, date, https, validate_credential_bytes


class Delivery:
    def __init__(self, store, unsigned_ipa, origin, root, signer='zsign'):
        self.store, self.source = store, Path(unsigned_ipa).resolve()
        self.origin = https(origin).rstrip('/')
        from urllib.parse import urlsplit
        if urlsplit(self.origin).path or urlsplit(self.origin).query:
            raise ValueError('Use root HTTPS origin')
        self.root, self.signer = Path(root).resolve(), signer
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        with store.db() as db:
            db.execute('CREATE TABLE IF NOT EXISTS deliveries (token TEXT PRIMARY KEY, account_id TEXT NOT NULL, expires REAL NOT NULL)')
        with zipfile.ZipFile(self.source) as archive:
            roots = [name for name in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
            if len(roots) != 1:
                raise ValueError('Expected one base app')
            self.info = plistlib.loads(archive.read(roots[0]))
            if self.info.get('CFBundleIdentifier') != 'ru.ipa95.applestore':
                raise ValueError('Base IPA is not our AppStore+')
            if getattr(store,'paid_access',False) and self.info.get('AppStoreRequiresLicense') is not True:
                raise ValueError('Paid delivery requires the new fail-closed AppStore+ base')

    def prepare(self, telegram_id, udid, p12, profile, password, access_days):
        if not 0 < access_days <= 366:
            raise ValueError('Invalid access duration')
        payload, expiry = validate_credential_bytes(p12, profile, password, udid)
        now = time.time()
        ends = min(now + access_days * 86400, expiry)
        account = None
        existing_account = None
        if getattr(self.store,'paid_access',False):
            with self.store.db() as db:
                found = db.execute('SELECT id FROM accounts WHERE device_id=? AND telegram_id=? ORDER BY created LIMIT 1',(udid,telegram_id)).fetchone()
                existing_account = found['id'] if found else None
        token = secrets.token_urlsafe(32)
        published = self.root / token
        try:
            with tempfile.TemporaryDirectory(prefix='.job-', dir=self.root) as folder:
                work = Path(folder)
                os.chmod(work, 0o700)
                account, code = self.store.provision(telegram_id, udid, payload, now, ends, expiry)
                config = work / 'StoreActivation.json'
                config.write_text(json.dumps(dict(endpoint=self.origin, code=code, deviceID=udid)))
                os.chmod(config, 0o600)
                personal, signed = work/'personal.ipa', work/'AppStore-Plus.ipa'
                personalize(self.source, config, personal)
                for name, data in (('certificate.p12', p12), ('profile.mobileprovision', profile)):
                    file = work/name
                    file.write_bytes(data)
                    os.chmod(file, 0o600)
                # No shell and no subprocess output in logs. zsign requires its password argument.
                result = subprocess.run([self.signer, '-k', str(work/'certificate.p12'), '-p', password,
                                         '-m', str(work/'profile.mobileprovision'), '-o', str(signed), str(personal)],
                                        capture_output=True, timeout=600)
                if result.returncode or not signed.is_file() or signed.stat().st_size == 0:
                    raise ValueError('Signing failed; check local signer and certificate')
                with zipfile.ZipFile(signed) as archive:
                    names = archive.namelist()
                    matches = [n for n in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
                    if len(matches) != 1:
                        raise ValueError('Invalid signed IPA')
                    prefix = matches[0].rsplit('/',1)[0] + '/'
                    info = plistlib.loads(archive.read(matches[0]))
                    if info.get('CFBundleIdentifier') != self.info['CFBundleIdentifier']:
                        raise ValueError('Signer changed application identity')
                    if prefix+'_CodeSignature/CodeResources' not in names or prefix+'embedded.mobileprovision' not in names:
                        raise ValueError('Signer did not produce required signing resources')
                    if json.loads(archive.read(prefix+'StoreActivation.json'))['code'] != code:
                        raise ValueError('Signer lost activation resource')
                ready = work/'ready'
                ready.mkdir(mode=0o700)
                shutil.move(signed, ready/'AppStore-Plus.ipa')
                os.chmod(ready/'AppStore-Plus.ipa', 0o600)
                base = self.origin + '/delivery/' + token
                manifest = {'items': [{'assets': [{'kind': 'software-package', 'url': base+'/AppStore-Plus.ipa'}],
                                      'metadata': {'bundle-identifier': info['CFBundleIdentifier'],
                                                   'bundle-version': str(info.get('CFBundleVersion', '1')),
                                                   'kind': 'software', 'title': 'AppStore+'}}]}
                (ready/'manifest.plist').write_bytes(plistlib.dumps(manifest))
                install = 'itms-services://?action=download-manifest&url=' + quote(base+'/manifest.plist', safe='')
                page = '<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>AppStore+</title><h1>AppStore+</h1><p>Откройте эту страницу в Safari на своём iPhone.</p><p><a href="'+html.escape(install, quote=True)+'">Установить AppStore+</a></p></html>'
                (ready/'install').write_text(page, encoding='utf-8')
                ready.rename(published)
                link = base + '/install'
                with self.store.db() as db:
                    db.execute('INSERT INTO deliveries VALUES(?,?,?)', (token, account, min(ends, now+7*86400)))
                    db.execute('UPDATE accounts SET install_url=? WHERE id=?', (link, account))
                return {'installURL': link, 'accountID': account, 'expiresAt': date(ends), 'requiresLicense': bool(getattr(self.store,'paid_access',False))}
        except BaseException:
            shutil.rmtree(published, ignore_errors=True)
            if account:
                with self.store.db() as db:
                    if account != existing_account: db.execute('UPDATE accounts SET revoked=1 WHERE id=?', (account,))
                    db.execute('DELETE FROM deliveries WHERE token=?', (token,))
            raise

    def resolve(self, request_path):
        match = re.fullmatch(r'/delivery/([A-Za-z0-9_-]{43})/(install|manifest\.plist|AppStore-Plus\.ipa)', request_path)
        if not match:
            raise APIError(404, 'not_found')
        token, name = match.groups()
        with self.store.db() as db:
            row = db.execute('SELECT a.*,d.expires AS delivery_expires FROM deliveries d JOIN accounts a ON a.id=d.account_id WHERE d.token=?', (token,)).fetchone()
        if row is None or row['delivery_expires'] <= time.time() or not self.store.delivery_allowed(row):
            raise APIError(404, 'not_found')
        path = self.root/token/name
        if not path.is_file():
            raise APIError(404, 'not_found')
        mime = {'install': 'text/html; charset=utf-8', 'manifest.plist': 'text/xml', 'AppStore-Plus.ipa': 'application/octet-stream'}[name]
        return path, mime

    def cleanup(self):
        with self.store.db() as db:
            expired = db.execute('SELECT token FROM deliveries WHERE expires<=?', (time.time(),)).fetchall()
            for row in expired:
                shutil.rmtree(self.root/row['token'], ignore_errors=True)
                db.execute('DELETE FROM deliveries WHERE token=?', (row['token'],))


def configured_delivery(store, optional=False):
    source, origin = os.environ.get('APPSTORE_UNSIGNED_IPA'), os.environ.get('APPSTORE_ORIGIN')
    if optional and not source and not origin:
        return None
    if not source or not origin:
        raise ValueError('Set APPSTORE_UNSIGNED_IPA and APPSTORE_ORIGIN')
    return Delivery(store, source, origin, os.environ.get('APPSTORE_DELIVERY_ROOT','activation-state/delivery'),
                    os.environ.get('APPSTORE_ZSIGN','zsign'))


def serve_file(handler, path, mime, head=False):
    size = path.stat().st_size
    start, end, partial = 0, size-1, False
    value = handler.headers.get('Range')
    if value:
        match = re.fullmatch(r'bytes=(\d*)-(\d*)', value)
        if not match or not any(match.groups()):
            raise APIError(416,'invalid_range')
        a, b = match.groups()
        if a:
            start, end = int(a), min(int(b),size-1) if b else size-1
        else:
            start = max(0,size-int(b))
        if not 0 <= start <= end < size:
            raise APIError(416,'invalid_range')
        partial = True
    handler.send_response(206 if partial else 200)
    handler.send_header('Content-Type',mime)
    handler.send_header('Content-Length',str(end-start+1))
    handler.send_header('Accept-Ranges','bytes')
    handler.send_header('Cache-Control','no-store')
    handler.send_header('Referrer-Policy','no-referrer')
    handler.send_header('X-Content-Type-Options','nosniff')
    if partial:
        handler.send_header('Content-Range',f'bytes {start}-{end}/{size}')
    handler.end_headers()
    if not head:
        with path.open('rb') as stream:
            stream.seek(start)
            remaining = end-start+1
            while remaining:
                chunk = stream.read(min(remaining,1024*1024))
                if not chunk:
                    break
                handler.wfile.write(chunk)
                remaining -= len(chunk)
