import base64
import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from one_provider import certificate_payload, ProviderError, fetch_certificate, NoRedirect


class ProviderTests(unittest.TestCase):
    def row(self, **changes):
        row = dict(udid='device-one', p12=base64.b64encode(b'p12').decode(),
                   mobileprovision=base64.b64encode(b'profile').decode(),p12_password='example-password')
        return {**row, **changes}

    def test_normalization_uses_real_credential_validator(self):
        with patch('one_provider.validate_credential_bytes', return_value=({'fingerprint': 'test'}, 123)) as validate:
            result = certificate_payload([self.row(), self.row(udid='other')], 'device-one')
            validate.assert_called_once_with(b'p12',b'profile','example-password','device-one')
            self.assertEqual(result[1],123)

    def test_incomplete_certificate_does_not_provision(self):
        for missing in ('', None, 'null'):
            with self.assertRaisesRegex(ProviderError,'not ready'):
                certificate_payload(self.row(mobileprovision=missing),'device-one')

    def test_wrong_or_ambiguous_recipient_rejected(self):
        for data in ([self.row(udid='other')], [self.row(),self.row()], {}):
            with self.assertRaisesRegex(ProviderError,'exactly one'):
                certificate_payload(data,'device-one')

    def test_password_never_assumed_to_be_one(self):
        with self.assertRaisesRegex(ProviderError,'password missing'):
            certificate_payload(self.row(p12_password=None),'device-one')
        with patch('one_provider.validate_credential_bytes') as validate:
            certificate_payload(self.row(p12_password=None),'device-one','override')
            self.assertEqual(validate.call_args.args[2],'override')

    def test_corrupted_or_inactive_material_rejected(self):
        for changes in (dict(p12='not base64!'),dict(revoked=True),dict(enabled=False),dict(status='expired')):
            with self.assertRaises(ProviderError):certificate_payload(self.row(**changes),'device-one')

    def test_validation_failure_hides_sensitive_exception(self):
        with patch('one_provider.validate_credential_bytes',side_effect=ValueError('secret-payload')):
            with self.assertRaises(ProviderError) as error:certificate_payload(self.row(),'device-one')
        self.assertNotIn('secret-payload',str(error.exception))

    def test_invalid_udid_does_not_contact_provider(self):
        with patch('urllib.request.build_opener') as opener:
            with self.assertRaises(ProviderError):fetch_certificate('one&udid=other','secret')
            opener.assert_not_called()

    def test_no_key_does_not_contact_provider(self):
        with patch('urllib.request.build_opener') as opener:
            with self.assertRaises(ProviderError):fetch_certificate('device-one',None)
            opener.assert_not_called()

    def test_redirect_does_not_forward_authorization(self):
        with self.assertRaisesRegex(ProviderError,'redirect refused'):
            NoRedirect().redirect_request(None,None,302,'',{},'https://other.example')
