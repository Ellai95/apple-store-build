import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer
import threading
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from service import APIError, handler
from licenses import LicenseStore, PLANS, add_months

class LicenseTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.store=LicenseStore(Path(self.tmp.name)/'db',os.urandom(32))
        now=time.time();self.account,self.code=self.store.provision(123,'device-one',dict(p12='fixture'),now,now+300,now+86400)
        self.key=ec.generate_private_key(ec.SECP256R1())
        raw=self.key.public_key().public_bytes(serialization.Encoding.X962,serialization.PublicFormat.UncompressedPoint)
        sig=self.key.sign(('AppStore+ activate\n'+self.code).encode(),ec.ECDSA(hashes.SHA256()))
        self.enrollment=dict(code=self.code,publicKey=base64.b64encode(raw).decode(),signature=base64.b64encode(sig).decode())
    def tearDown(self): self.tmp.cleanup()
    def row(self): return self.store.account(self.account)
    def issue(self,plan='customer_1m'): return self.store.issue_key(self.account,plan)
    def license(self):
        with self.store.db() as db: return dict(db.execute('SELECT * FROM licenses').fetchone())
    def test_enrollment_does_not_grant_access(self):
        self.assertEqual(self.store.activate(self.enrollment)['subscription']['status'],'unlicensed')
        self.assertTrue(self.store.credentials_allowed(self.row()));self.assertTrue(self.store.delivery_allowed(self.row()))
        self.issue();self.assertEqual(self.store.status(self.row())['status'],'unlicensed')
    def test_start_time_hash_only_storage_and_retry(self):
        key=self.issue();before=time.time();self.store.redeem_key(self.row(),key);first=self.license()
        self.assertGreaterEqual(first['starts'],before);self.assertEqual(first['ends'],add_months(first['starts'],1))
        self.store.redeem_key(self.row(),key);self.assertEqual(self.license(),first)
        self.assertNotIn(key.encode(),Path(self.store.path).read_bytes())
    def test_renew_from_expiry_or_now(self):
        self.store.redeem_key(self.row(),self.issue());old=self.license()
        self.store.redeem_key(self.row(),self.issue('customer_3m'))
        self.assertEqual(self.license()['ends'],add_months(old['ends'],3))
        with self.store.db() as db: db.execute('UPDATE licenses SET ends=?',(time.time()-100,))
        self.assertEqual(self.store.status(self.row())['status'],'expired')
        before=time.time();self.store.redeem_key(self.row(),self.issue())
        self.assertGreaterEqual(self.license()['ends'],add_months(before,1))
    def test_wrong_device_invalid_and_revoked_key(self):
        key=self.issue();other,_=self.store.provision(124,'other-device',{},time.time(),time.time()+10,time.time()+86400)
        with self.assertRaises(APIError) as error: self.store.redeem_key(self.store.account(other),key)
        self.assertEqual(error.exception.code,'license_wrong_device')
        with self.assertRaises(APIError): self.store.redeem_key(self.row(),'ASP-'+'x'*32)
        with self.store.db() as db: db.execute('UPDATE license_keys SET revoked=1')
        with self.assertRaises(APIError): self.store.redeem_key(self.row(),key)
    def test_lifetime_and_certificate_replacement(self):
        self.store.redeem_key(self.row(),self.issue('external_lifetime'));self.assertIsNone(self.license()['ends'])
        with self.store.db() as db: db.execute('UPDATE accounts SET cert_ends=?',(time.time()-1,))
        self.assertEqual(self.store.status(self.row())['status'],'certificate_expired')
        self.assertEqual(self.store.status(self.row())['licenseStatus'],'active')
        id,_=self.store.provision(123,'device-one',dict(p12='replacement'),time.time(),time.time()+10,time.time()+86400)
        self.assertEqual(id,self.account);self.assertTrue(self.store.status(self.row())['lifetime'])
        self.assertEqual(self.store.status(self.row())['status'],'active')
        with self.assertRaises(ValueError): self.store.provision(999,'device-one',{},time.time(),time.time()+10,time.time()+86400)
    def test_concurrent_redemption_extends_once(self):
        key=self.issue('customer_3m')
        with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(lambda _:self.store.redeem_key(self.row(),key),range(2)))
        self.assertEqual(results[0]['licenseExpiresAt'],results[1]['licenseExpiresAt'])
        value=self.license();self.assertEqual(value['ends'],add_months(value['starts'],3))
    def test_revoked_license_not_reactivated_by_new_key(self):
        self.store.redeem_key(self.row(),self.issue())
        with self.store.db() as db: db.execute('UPDATE licenses SET revoked=1')
        with self.assertRaises(APIError): self.store.redeem_key(self.row(),self.issue())
        self.assertEqual(self.store.status(self.row())['status'],'revoked')
    def test_calendar_and_prices(self):
        def stamp(x): return datetime.fromisoformat(x).replace(tzinfo=timezone.utc).timestamp()
        self.assertEqual(add_months(stamp('2028-01-31'),1),stamp('2028-02-29'))
        self.assertEqual(add_months(stamp('2028-02-29'),12),stamp('2029-02-28'))
        self.assertEqual([x['rub'] for x in PLANS.values()],[1000,2000,3500,300,500,800,1000])
    def test_http_signed_post_tampering_and_replay(self):
        token=self.store.activate(self.enrollment)['token'];server=ThreadingHTTPServer(('127.0.0.1',0),handler(self.store))
        server.daemon_threads=True;thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            path='/v1/license/redeem';body=json.dumps({'key':self.issue()}).encode();stamp=str(int(time.time()));nonce='abcdef01'*4
            sig=self.key.sign('\n'.join(['POST',path,hashlib.sha256(body).hexdigest(),stamp,nonce]).encode(),ec.ECDSA(hashes.SHA256()))
            headers={'Content-Type':'application/json','Authorization':'Bearer '+token,'X-Store-Time':stamp,'X-Store-Nonce':nonce,'X-Store-Signature':base64.b64encode(sig).decode()}
            def request(data): return urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:'+str(server.server_port)+path,data=data,headers=headers),timeout=4)
            with self.assertRaises(urllib.error.HTTPError) as error: request(b'{"key":"tampered"}')
            self.assertEqual(error.exception.code,401)
            with request(body) as response: self.assertEqual(json.load(response)['status'],'active')
            with self.assertRaises(urllib.error.HTTPError) as error: request(body)
            self.assertEqual(error.exception.code,409)
        finally: server.shutdown();server.server_close();thread.join(timeout=3)
