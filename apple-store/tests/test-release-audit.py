#!/usr/bin/env python3
"""Regression fixtures: guard against packaging plaintext, credentials or source."""
from pathlib import Path
import importlib.util
import plistlib
import tempfile
import zipfile

spec = importlib.util.spec_from_file_location('audit', Path(__file__).parents[1]/'audit-ipa.py')
audit = importlib.util.module_from_spec(spec); spec.loader.exec_module(audit)
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    base = {
        'Payload/AppleStore.app/Info.plist': plistlib.dumps({'CFBundleExecutable':'AppleStore','CFBundleShortVersionString':'3.7'}),
        'Payload/AppleStore.app/AppleStore': b'fixture executable',
        'Payload/AppleStore.app/StoreData.bin': b'\x91'*1200,
        'Payload/AppleStore.app/server.pem': b'expected local installation transport fixture'
    }
    def run(extra):
        ipa=root/'fixture.ipa'
        with zipfile.ZipFile(ipa,'w') as z:
            for key,value in (base|extra).items(): z.writestr(key,value)
        audit.check(ipa,root/'report')
    run({})
    for filename,content in [
        ('AppleStoreCatalog.json',b'{}'),('private.p12',b'test'),
        ('Implementation.swift',b'import Foundation'),
        ('notes.txt',b'https://github.com/Ellai95/apple-store-build'),
        ('binary-marker',b'prefix\0pub-d11175355ab34b9299fb0a916702bce7.r2.dev\0suffix'),
        ('token.txt',b'1234567890:'+b'A'*35),
        ('Debug.dSYM/Contents/Resources/DWARF/AppleStore',b'test')
    ]:
        try: run({'Payload/AppleStore.app/'+filename:content})
        except SystemExit: pass
        else: raise AssertionError('Accepted forbidden fixture: '+filename)
    print('PASS: rejects source, debug data, credentials, customer certificates and plaintext catalog/addresses.')
