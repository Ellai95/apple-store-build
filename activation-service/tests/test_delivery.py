import base64
from datetime import datetime,timedelta,timezone
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import urllib.request
import urllib.error
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import pkcs12
from service import Store,APIError,handler
from delivery import Delivery
from delivery_bot import DeliveryBot


class TelegramFixture:
    def __init__(self,files):self.files=files;self.sent=[]
    def file(self,document):return self.files[document['file_id']]
    def send(self,user,text,link=None):self.sent.append((user,text,link))
    def call(self,method,payload):self.sent.append((payload['chat_id'],payload['text'],None));return True


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.store=Store(self.root/'store.db',os.urandom(32))
        key=ec.generate_private_key(ec.SECP256R1());now=datetime.now(timezone.utc)
        name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Local fixture, NOT an Apple identity')])
        cert=x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(123).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=4)).sign(key,hashes.SHA256())
        self.p12=pkcs12.serialize_key_and_certificates(b'test',key,cert,None,serialization.BestAvailableEncryption(b'test-password'))
        (self.root/'cert.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        (self.root/'key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
        profile=dict(ProvisionedDevices=['device-one'],DeveloperCertificates=[cert.public_bytes(serialization.Encoding.DER)],ExpirationDate=(now+timedelta(days=2)).replace(tzinfo=None))
        (self.root/'profile.plist').write_bytes(plistlib.dumps(profile))
        subprocess.run(['openssl','cms','-sign','-binary','-in',str(self.root/'profile.plist'),'-signer',str(self.root/'cert.pem'),'-inkey',str(self.root/'key.pem'),'-outform','DER','-nodetach','-out',str(self.root/'profile.mobileprovision')],check=True,capture_output=True)
        self.profile=(self.root/'profile.mobileprovision').read_bytes()
        source=self.root/'base.ipa'
        with zipfile.ZipFile(source,'w') as archive:
            archive.writestr('Payload/Store.app/Info.plist',plistlib.dumps(dict(CFBundleIdentifier='ru.ipa95.applestore',CFBundleVersion='492')))
        self.delivery=Delivery(self.store,source,'https://example.com',self.root/'delivery','fake-zsign')

    def fake_sign(self,args,**kwargs):
        # Structure-only fixture. This is NOT a cryptographic code signature or installable IPA.
        output=Path(args[args.index('-o')+1]);source=Path(args[-1]);profile=Path(args[args.index('-m')+1])
        with zipfile.ZipFile(source) as src,zipfile.ZipFile(output,'w') as dst:
            for info in src.infolist():dst.writestr(info,src.read(info))
            dst.writestr('Payload/Store.app/_CodeSignature/CodeResources',b'fixture-only')
            dst.writestr('Payload/Store.app/embedded.mobileprovision',profile.read_bytes())
        return subprocess.CompletedProcess(args,0,b'',b'')

    def prepared(self):
        with patch('delivery.subprocess.run',side_effect=self.fake_sign):
            # Credential CMS parsing must use real openssl, patched only after validation.
            with patch('delivery.validate_credential_bytes',return_value=(dict(p12=base64.b64encode(self.p12).decode(),profile=base64.b64encode(self.profile).decode(),password='test-password',fingerprint='fixture'),time.time()+86400)):
                return self.delivery.prepare(123,'device-one',self.p12,self.profile,'test-password',30)

    def test_private_publication_and_embedded_activation(self):
        result=self.prepared();token=result['installURL'].split('/')[-2]
        path,mime=self.delivery.resolve('/delivery/'+token+'/AppStore-Plus.ipa')
        with zipfile.ZipFile(path) as archive:
            config=json.loads(archive.read('Payload/Store.app/StoreActivation.json'))
            self.assertEqual(config['deviceID'],'device-one')
            self.assertFalse(any(name.endswith('.p12') for name in archive.namelist()))
        self.assertEqual(self.store.account(result['accountID'])['install_url'],result['installURL'])
        self.assertLessEqual(self.store.account(result['accountID'])['ends'],time.time()+86401)
        self.assertFalse(list(self.delivery.root.glob('.job-*')))

    def test_signer_failure_never_leaves_ready_link(self):
        with patch('delivery.validate_credential_bytes',return_value=({},time.time()+86400)),patch('delivery.subprocess.run',return_value=subprocess.CompletedProcess([],1,b'',b'private error')):
            with self.assertRaisesRegex(ValueError,'Signing failed'):
                self.delivery.prepare(123,'device-one',self.p12,self.profile,'test-password',30)
        with self.store.db() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM deliveries').fetchone()[0],0)
            self.assertEqual(db.execute('SELECT revoked FROM accounts').fetchone()[0],1)
        self.assertFalse(list(self.delivery.root.iterdir()))

    def test_real_credentials_reject_other_device_before_signer(self):
        with self.assertRaisesRegex(ValueError,'UDID absent'):
            self.delivery.prepare(123,'other-device',self.p12,self.profile,'test-password',30)
        with self.store.db() as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM accounts').fetchone()[0],0)

    def test_expiry_revocation_and_traversal(self):
        result=self.prepared();path='/delivery/'+result['installURL'].split('/')[-2]+'/manifest.plist'
        for invalid in ('/delivery/../manifest.plist',path+'/../certificate.p12',path+'?secret=x'):
            with self.assertRaises(APIError):self.delivery.resolve(invalid)
        with self.store.db() as db:db.execute('UPDATE accounts SET revoked=1')
        with self.assertRaises(APIError):self.delivery.resolve(path)
        with self.store.db() as db:db.execute('UPDATE deliveries SET expires=0')
        self.delivery.cleanup();self.assertFalse(list(self.delivery.root.iterdir()))

    def test_http_manifest_range_and_head(self):
        from http.server import ThreadingHTTPServer
        result=self.prepared();base='/delivery/'+result['installURL'].split('/')[-2]
        server=ThreadingHTTPServer(('127.0.0.1',0),handler(self.store,self.delivery))
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            host=f'http://127.0.0.1:{server.server_port}'
            with urllib.request.urlopen(host+base+'/manifest.plist') as response:
                manifest=plistlib.loads(response.read());self.assertIn('AppStore-Plus.ipa',manifest['items'][0]['assets'][0]['url'])
            req=urllib.request.Request(host+base+'/AppStore-Plus.ipa',headers={'Range':'bytes=0-3'})
            with urllib.request.urlopen(req) as response:self.assertEqual((response.status,response.read()),(206,b'PK\x03\x04'))
            with urllib.request.urlopen(urllib.request.Request(host+base+'/AppStore-Plus.ipa',method='HEAD')) as response:self.assertEqual(response.read(),b'')
        finally:server.shutdown();server.server_close();thread.join()

    def message(self,text=None,doc=None,user=123):
        row={'chat':{'id':user,'type':'private'},'from':{'id':user}}
        if text is not None:row['text']=text
        if doc:row['document']={'file_id':doc,'file_name':doc,'file_size':1}
        return row

    def test_bot_uploads_auto_prepare_and_recipient_isolation(self):
        telegram=TelegramFixture({'a.p12':self.p12,'b.mobileprovision':self.profile})
        bot=DeliveryBot(self.store,self.delivery,telegram,{123})
        self.assertFalse(bot.handle(self.message(doc='a.p12',user=999)))
        outcome={'installURL':'https://example.com/private','expiresAt':'2026-11-01T00:00:00Z'}
        with patch.object(self.delivery,'prepare',return_value=outcome) as prepare:
            for message in (self.message(doc='a.p12'),self.message(doc='b.mobileprovision')):bot.handle(message)
            bot.executor.shutdown(wait=True)
            prepare.assert_called_once()
            self.assertEqual(prepare.call_args.args[0],123)
            self.assertEqual(prepare.call_args.args[1],'device-one')
            self.assertEqual(prepare.call_args.args[4],'1')
        self.assertNotIn(b'test-password',Path(self.store.path).read_bytes())
        self.assertTrue(any(row[2]=='https://example.com/private' for row in telegram.sent))
        self.assertEqual(bot.draft(123),{})
        self.assertNotIn('test-password',json.dumps(telegram.sent))

    def test_bot_udid_fetches_existing_certificate_without_register(self):
        telegram=TelegramFixture({});bot=DeliveryBot(self.store,self.delivery,telegram,{123},provider_key='local-test-key')
        response={'udid':'device-one','p12':base64.b64encode(self.p12).decode(),'mobileprovision':base64.b64encode(self.profile).decode(),'p12_password':'test-password'}
        with patch('delivery_bot.fetch_certificate',return_value=response) as fetch,patch.object(self.delivery,'prepare',return_value={'installURL':'https://example.com/private','expiresAt':'2026-11-01T00:00:00Z'}) as prepare:
            bot.handle(self.message('/udid device-one'));bot.executor.shutdown(wait=True)
            fetch.assert_called_once_with('device-one','local-test-key');prepare.assert_called_once()
        self.assertNotIn('local-test-key',json.dumps(telegram.sent))

    def test_cancel_deletes_encrypted_draft(self):
        telegram=TelegramFixture({});bot=DeliveryBot(self.store,self.delivery,telegram,{123})
        bot.handle(self.message('/password sensitive-value'));bot.handle(self.message('/cancel'))
        self.assertEqual(bot.draft(123),{});bot.executor.shutdown(wait=True)

    def test_files_in_reverse_order_preserve_explicit_password(self):
        telegram=TelegramFixture({'a.p12':self.p12,'b.mobileprovision':self.profile})
        bot=DeliveryBot(self.store,self.delivery,telegram,{123})
        outcome={'installURL':'https://example.com/private','expiresAt':'2026-11-01T00:00:00Z'}
        with patch.object(self.delivery,'prepare',return_value=outcome) as prepare:
            bot.handle(self.message('/password custom-password'))
            bot.handle(self.message(doc='b.mobileprovision'))
            prepare.assert_not_called()
            bot.handle(self.message(doc='a.p12'))
            bot.executor.shutdown(wait=True)
            prepare.assert_called_once()
            self.assertEqual(prepare.call_args.args[4],'custom-password')

    def test_two_document_updates_from_same_send_prepare_once(self):
        telegram=TelegramFixture({'a.p12':self.p12,'b.mobileprovision':self.profile})
        bot=DeliveryBot(self.store,self.delivery,telegram,{123})
        outcome={'installURL':'https://example.com/private','expiresAt':'2026-11-01T00:00:00Z'}
        with patch.object(self.delivery,'prepare',return_value=outcome) as prepare:
            for name in ('a.p12','b.mobileprovision'):
                message=self.message(doc=name)
                message['media_group_id']='same-group'
                bot.handle(message)
            bot.executor.shutdown(wait=True)
            prepare.assert_called_once()
            self.assertEqual(prepare.call_args.args[4],'1')
