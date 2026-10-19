"""Check local pilot prerequisites without contacting Telegram or printing secrets."""
import base64
import os
from pathlib import Path
import shutil
from urllib.parse import urlsplit
import zipfile


def check():
    errors = []
    for key in ['APPSTORE_BOT_TOKEN', 'APPSTORE_MASTER_KEY', 'APPSTORE_DELIVERY_ALLOWED_IDS', 'APPSTORE_UNSIGNED_IPA', 'APPSTORE_ORIGIN']:
        if not os.environ.get(key): errors.append('Не задано: ' + key)
    key = os.environ.get('APPSTORE_MASTER_KEY')
    if key:
        try:
            if len(base64.b64decode(key, validate=True)) != 32: raise ValueError()
        except ValueError: errors.append('APPSTORE_MASTER_KEY должен содержать 32 байта в base64')
    ids = os.environ.get('APPSTORE_DELIVERY_ALLOWED_IDS', '')
    if ids and any(not item.strip().isdigit() or int(item.strip()) <= 0 for item in ids.split(',')):
        errors.append('Разрешённые Telegram ID должны быть положительными числами через запятую')
    origin = os.environ.get('APPSTORE_ORIGIN')
    if origin:
        parsed = urlsplit(origin)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
            errors.append('Нужен HTTPS origin без пароля в URL')
    signer = os.environ.get('APPSTORE_ZSIGN', 'zsign')
    if not shutil.which(signer): errors.append('Не найден исполняемый zsign')
    if not shutil.which('openssl'): errors.append('Не найден OpenSSL')
    source = os.environ.get('APPSTORE_UNSIGNED_IPA')
    if source:
        try:
            with zipfile.ZipFile(Path(source)) as z:
                if any('_CodeSignature' in name.split('/') for name in z.namelist()):
                    errors.append('Сначала подготовьте основу через prepare_base.py')
        except (OSError, zipfile.BadZipFile): errors.append('Не удалось прочитать базовую IPA')
    return errors


if __name__ == '__main__':
    errors = check()
    for error in errors: print(error)
    if errors:
        print('Живая выдача пока не готова. Значения секретов не выводились.')
        raise SystemExit(1)
    print('Локальные предпосылки готовы. Доступность HTTPS, Telegram и подпись проверяются отдельным живым тестом.')
