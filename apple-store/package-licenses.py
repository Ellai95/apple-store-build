#!/usr/bin/env python3
from pathlib import Path
import json
import sys
import zipfile

source = Path(sys.argv[1])
resources = json.loads((source/'SOURCE_RESOURCES.json').read_text())
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as archive:
    archive.writestr('GNU-GPL-3.0.txt', resources['texts']['AppleStoreLicense'])
    archive.writestr('Components-and-Authors.txt', resources['texts']['AppleStoreNotices'])
    archive.writestr('READ_ME.txt',
        'Apple Store 3.8\nИзменения Apple Store: Maga Magomadov.\n'
        'Программа основана на Feather. Лицензия: GNU GPL-3.0.\n'
        'Программа предоставляется без гарантий в пределах лицензии.\n'
        'Полные исходники соответствующей сборки распространяются рядом с IPA:\n'
        'Apple-Store-3.8-Source.zip.\n'
        'Авторские права на компоненты принадлежат указанным в уведомлениях авторам.\n')
print('PASS: standalone licenses and author notices prepared for publication beside IPA.')
