import plistlib
from pathlib import Path
import tempfile
import unittest
import zipfile
from prepare_base import prepare_base


class PrepareBaseTests(unittest.TestCase):
    def archive(self, root, extra=None, bundle='ru.ipa95.applestore'):
        source = root/'input.ipa'
        with zipfile.ZipFile(source, 'w') as archive:
            archive.writestr('Payload/Store.app/Info.plist', plistlib.dumps({'CFBundleIdentifier': bundle}))
            info = zipfile.ZipInfo('Payload/Store.app/AppleStore'); info.external_attr = 0o100755 << 16
            archive.writestr(info, b'example executable')
            archive.writestr('Payload/Store.app/StoreData.bin', b'encrypted resources')
            archive.writestr('Payload/Store.app/_CodeSignature/CodeResources', b'old envelope')
            archive.writestr('Payload/Store.app/embedded.mobileprovision', b'old profile')
            if extra: archive.writestr(extra, b'private')
        return source

    def test_preserves_resources_and_mode_removes_old_envelope(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); out = prepare_base(self.archive(root), root/'base.ipa')
            with zipfile.ZipFile(out) as archive:
                self.assertEqual(archive.read('Payload/Store.app/StoreData.bin'), b'encrypted resources')
                self.assertEqual(archive.getinfo('Payload/Store.app/AppleStore').external_attr >> 16, 0o100755)
                self.assertFalse(any('_CodeSignature' in n or n.endswith('.mobileprovision') for n in archive.namelist()))
            with self.assertRaises(ValueError): prepare_base(root/'input.ipa', out)

    def test_rejects_private_personalized_and_unsafe_input(self):
        for extra in ['Payload/Store.app/StoreActivation.json', 'Payload/Store.app/client.p12', '../escape']:
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                with self.assertRaises(ValueError): prepare_base(self.archive(root, extra), root/'base.ipa')
                self.assertFalse((root/'base.ipa').exists())

    def test_rejects_other_application(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError): prepare_base(self.archive(root, bundle='other.app'), root/'base.ipa')
