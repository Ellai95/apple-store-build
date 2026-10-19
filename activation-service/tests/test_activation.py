import base64
import hashlib
import importlib.util
import json
import os
import sqlite3
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from service import Store, APIError, handler
from bot import reply
from personalize import personalize

class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.store=Store(Path(self.temp.name)/'store.db',os.urandom(32))
        self.key=ec.generate_private_key(ec.SECP256R1())
        self.public=self.key.public_key().public_bytes(__import__('cryptography').hazmat.primitives.serialization.Encoding.X962,
                                                      __import__('cryptography').hazmat.primitives.serialization.PublicFormat.UncompressedPoint)
        self.account,self.code=self.store.provision(123,'device-one',dict(p12='secret-p12',profile='secret-profile',password='secret-password'),
                                                   time.time()-1,time.time()+3600,time.time()+7200)
    def tearDown(self): self.temp.cleanup()
    def activate(self,key=None,code=None):
        key=key or self.key; code=code or self.code
        from cryptography.hazmat.primitives.serialization import Encoding,PublicFormat
        public=key.public_key().public_bytes(Encoding.X962,PublicFormat.UncompressedPoint)
        signature=key.sign(('AppStore+ activate\n'+code).encode(),ec.ECDSA(hashes.SHA256()))
        return self.store.activate(dict(code=code,publicKey=base64.b64encode(public).decode(),signature=base64.b64encode(signature).decode()))
    def headers(self,token,path='/v1/subscription',nonce='a'*32,stamp=None,key=None):
        stamp=str(stamp or int(time.time())); key=key or self.key
        canonical='\n'.join(['GET',path,hashlib.sha256(b'').hexdigest(),stamp,nonce]).encode()
        sig=key.sign(canonical,ec.ECDSA(hashes.SHA256()))
        return {'Authorization':'Bearer '+token,'X-Store-Time':stamp,'X-Store-Nonce':nonce,'X-Store-Signature':base64.b64encode(sig).decode()}
    def test_enrollment_and_signed_request(self):
        session=self.activate()
        self.assertEqual(session['subscription']['deviceID'],'device-one')
        row=self.store.authenticated('/v1/subscription',self.headers(session['token']))
        self.assertEqual(row['id'],self.account)
    def test_same_key_retry_different_key_rejected(self):
        self.activate(); self.activate()
        with self.assertRaises(APIError) as error: self.activate(ec.generate_private_key(ec.SECP256R1()))
        self.assertEqual(error.exception.code,'activation_already_bound')
    def test_stolen_token_requires_private_key(self):
        token=self.activate()['token']
        with self.assertRaises(APIError): self.store.authenticated('/v1/subscription',self.headers(token,key=ec.generate_private_key(ec.SECP256R1())))
    def test_replay_and_path_tampering_rejected(self):
        token=self.activate()['token']; headers=self.headers(token)
        self.store.authenticated('/v1/subscription',headers)
        with self.assertRaises(APIError): self.store.authenticated('/v1/subscription',headers)
        with self.assertRaises(APIError): self.store.authenticated('/v1/credentials',self.headers(token,nonce='b'*32))
    def test_expired_timestamp_and_code_rejected(self):
        token=self.activate()['token']
        with self.assertRaises(APIError): self.store.authenticated('/v1/subscription',self.headers(token,stamp=int(time.time())-300))
        with self.store.db() as db: db.execute('UPDATE accounts SET code_ends=0')
        with self.assertRaises(APIError): self.activate()
    def test_revoked_account_does_not_activate(self):
        with self.store.db() as db: db.execute('UPDATE accounts SET revoked=1')
        with self.assertRaises(APIError): self.activate()
    def test_at_rest_and_wrong_master_key(self):
        raw=Path(self.store.path).read_bytes()
        self.assertNotIn(b'secret-password',raw); self.assertNotIn(self.code.encode(),raw)
        row=self.store.account(self.account)
        self.assertEqual(self.store.open(row)['password'],'secret-password')
        wrong=Store(self.store.path,os.urandom(32))
        with self.assertRaises(Exception): wrong.open(row)
    def test_signature_required_for_code(self):
        with self.assertRaises(APIError): self.store.activate(dict(code=self.code,publicKey=base64.b64encode(self.public).decode(),signature='AAAA'))
    def test_budget_dates_and_rate_limit(self):
        with self.assertRaises(ValueError): self.store.provision(123,'udid',{},time.time(),time.time()+7200,time.time()+3600)
        for _ in range(15): self.store.rate_limit('test')
        with self.assertRaises(APIError): self.store.rate_limit('test')
    def test_bot_recipient_isolation_and_no_secrets(self):
        with self.store.db() as db: db.execute('UPDATE accounts SET install_url=?',('https://example.com/private',))
        message=dict(chat=dict(type='private',id=123),**{'from':dict(id=123),'text':'/install'})
        result=reply(self.store,message,'https://t.me/support')
        self.assertIn('reply_markup',result)
        serialized=json.dumps(result)
        self.assertNotIn('secret',serialized); self.assertNotIn(self.code,serialized)
        message['from']['id']=456; message['chat']['id']=456
        self.assertNotIn('reply_markup',reply(self.store,message,'https://t.me/support'))
        message['chat']['type']='group'
        self.assertIsNone(reply(self.store,message,'https://t.me/support'))
    def test_personalization_preserves_ipa_and_refuses_signed_source(self):
        root=Path(self.temp.name); source=root/'base.ipa'; config=root/'bootstrap.json'; output=root/'personal.ipa'
        config.write_text(json.dumps(dict(endpoint='https://example.com',code=self.code,deviceID='device-one')))
        with zipfile.ZipFile(source,'w') as z: z.writestr('Payload/Store.app/Info.plist',b'original')
        personalize(source,config,output)
        with zipfile.ZipFile(output) as z:
            self.assertEqual(z.read('Payload/Store.app/Info.plist'),b'original')
            self.assertEqual(json.loads(z.read('Payload/Store.app/StoreActivation.json'))['deviceID'],'device-one')
        with zipfile.ZipFile(source,'a') as z: z.writestr('Payload/Store.app/_CodeSignature/CodeResources',b'signed')
        with self.assertRaises(ValueError): personalize(source,config,root/'invalid.ipa')
    def test_real_http_activation_credentials_and_replay(self):
        import threading,urllib.request,urllib.error
        from http.server import ThreadingHTTPServer
        server=ThreadingHTTPServer(('127.0.0.1',0),handler(self.store))
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        try:
            token=self.activate()['token']; path='/v1/credentials'
            request=urllib.request.Request(f'http://127.0.0.1:{server.server_port}'+path,headers=self.headers(token,path=path))
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.headers['Cache-Control'],'no-store')
                self.assertEqual(json.load(response)['password'],'secret-password')
            with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(request)
            self.assertEqual(error.exception.code,409)
            with self.store.db() as db: db.execute('UPDATE accounts SET revoked=1')
            request=urllib.request.Request(f'http://127.0.0.1:{server.server_port}'+path,headers=self.headers(token,path=path,nonce='c'*32))
            with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(request)
            self.assertEqual(error.exception.code,403)
        finally:
            server.shutdown(); server.server_close(); thread.join()

if __name__=='__main__': unittest.main()

class RealCertificateTests(unittest.TestCase):
    def test_real_p12_and_cms_profile_validation(self):
        import subprocess,plistlib
        from datetime import datetime,timedelta,timezone
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.serialization import pkcs12
        from service import validate_credentials
        key=ec.generate_private_key(ec.SECP256R1())
        name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Local test only')])
        now=datetime.now(timezone.utc)
        cert=x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(123).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=3)).sign(key,hashes.SHA256())
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); p12=root/'cert.p12'; pem=root/'cert.pem'; private=root/'key.pem'; profile=root/'profile.mobileprovision'; plist=root/'profile.plist'
            p12.write_bytes(pkcs12.serialize_key_and_certificates(b'test',key,cert,None,serialization.BestAvailableEncryption(b'correct-password')))
            pem.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
            private.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
            plist.write_bytes(plistlib.dumps(dict(ProvisionedDevices=['device-one'],DeveloperCertificates=[cert.public_bytes(serialization.Encoding.DER)],ExpirationDate=(now+timedelta(days=2)).replace(tzinfo=None))))
            subprocess.run(['openssl','cms','-sign','-binary','-in',str(plist),'-signer',str(pem),'-inkey',str(private),'-outform','DER','-nodetach','-out',str(profile)],check=True,capture_output=True)
            payload,expiry=validate_credentials(p12,profile,'correct-password','device-one')
            self.assertEqual(payload['password'],'correct-password'); self.assertGreater(expiry,time.time())
            from one_provider import certificate_payload, ProviderError
            provider_response = dict(udid='device-one',p12=base64.b64encode(p12.read_bytes()).decode(),
                                     mobileprovision=base64.b64encode(profile.read_bytes()).decode(),
                                     p12_password='correct-password')
            imported,provider_expiry=certificate_payload(provider_response,'device-one')
            self.assertEqual(imported,payload)
            self.assertEqual(provider_expiry,expiry)
            with self.assertRaises(ProviderError):
                certificate_payload({**provider_response,'p12_password':'wrong'},'device-one')
            with self.assertRaises(ValueError): validate_credentials(p12,profile,'wrong-password','device-one')
            with self.assertRaises(ValueError): validate_credentials(p12,profile,'correct-password','other-device')
