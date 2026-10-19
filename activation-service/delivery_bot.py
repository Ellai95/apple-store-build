"""Private pilot bot: owner uploads a certificate pair or requests it by UDID.
Run with a separate test bot. Only explicitly allowed numeric Telegram IDs are served.
"""
import base64
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import subprocess
import plistlib
import threading
import time
import urllib.parse
import urllib.request

from bot import reply as status_reply
from delivery import configured_delivery
from one_provider import check_udid, certificate_payload, fetch_certificate
from service import configured_store

MAX_FILE = 1024 * 1024
HELP = ('AppStore+ · тестовая выдача\n\nПришлите .p12 и .mobileprovision вместе или отдельно. Пароль по умолчанию: 1. '
        'Если пароль другой, сначала укажите /password ВАШ_ПАРОЛЬ, затем отправьте файлы.\n'
        'Если в профиле одно устройство, UDID определится автоматически. Иначе укажите: /udid ВАШ_UDID. '
        'Если файлов нет, по UDID попробуем получить уже выпущенный сертификат у провайдера.\n'
        'Когда все данные получены, подпись начнётся автоматически. /sign — повторить; /cancel — очистить введённые данные; '
        '/install — последняя ссылка и срок доступа. Не пересылайте файлы сертификата другим людям.')


class Telegram:
    def __init__(self, token):
        self.token = token

    def call(self, method, payload):
        request = urllib.request.Request('https://api.telegram.org/bot'+self.token+'/'+method,
                                         data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=40) as response:
            data = json.load(response)
        if not data.get('ok'):
            raise ValueError('Telegram request failed')
        return data['result']

    def file(self, document):
        if not 0 < document.get('file_size',0) <= MAX_FILE:
            raise ValueError('Certificate file exceeds 1 MiB or has no size')
        info = self.call('getFile',{'file_id':document['file_id']})
        path = info['file_path']
        if not re.fullmatch(r'[A-Za-z0-9_./-]+',path) or '..' in path.split('/') or path.startswith('/'):
            raise ValueError('Invalid Telegram file path')
        with urllib.request.urlopen('https://api.telegram.org/file/bot'+self.token+'/'+path,timeout=40) as response:
            data = response.read(MAX_FILE+1)
        if not data or len(data)>MAX_FILE or len(data)!=document['file_size']:
            raise ValueError('Incomplete certificate file')
        return data

    def send(self, recipient, text, link=None):
        payload = {'chat_id':recipient,'text':text}
        if link:
            payload['reply_markup']={'inline_keyboard':[[{'text':'Установить AppStore+','url':link}]]}
        self.call('sendMessage',payload)


class DeliveryBot:
    def __init__(self, store, delivery, telegram, allowed_ids, access_days=30, provider_key=None):
        if not allowed_ids or access_days<1 or access_days>366:
            raise ValueError('Configure allowed numeric Telegram IDs and duration')
        self.store,self.delivery,self.telegram = store,delivery,telegram
        self.allowed_ids,self.access_days,self.provider_key = set(allowed_ids),access_days,provider_key
        self.executor=ThreadPoolExecutor(max_workers=1)
        self.lock=threading.RLock();self.busy=set()
        with store.db() as db:
            db.execute('CREATE TABLE IF NOT EXISTS bot_drafts (telegram_id INTEGER PRIMARY KEY, material BLOB NOT NULL, expires REAL NOT NULL)')

    def draft(self, sender):
        with self.store.db() as db:
            db.execute('DELETE FROM bot_drafts WHERE expires<=?',(time.time(),))
            row=db.execute('SELECT material FROM bot_drafts WHERE telegram_id=?',(sender,)).fetchone()
        if row is None:return {}
        return json.loads(self.store.cipher.decrypt(bytes(row['material'])[:12],bytes(row['material'])[12:],str(sender).encode()))

    def save(self, sender, draft):
        with self.store.db() as db:
            if draft:
                db.execute('INSERT OR REPLACE INTO bot_drafts VALUES(?,?,?)',
                           (sender,self.store.seal(str(sender),draft),time.time()+3600))
            else:db.execute('DELETE FROM bot_drafts WHERE telegram_id=?',(sender,))

    def handle(self, message):
        sender=message.get('from',{});chat=message.get('chat',{});user=sender.get('id')
        if chat.get('type')!='private' or chat.get('id')!=user or sender.get('is_bot') or user not in self.allowed_ids:
            return False
        with self.lock:
            if user in self.busy:
                self.telegram.send(user,'Подготовка AppStore+ уже идёт. Дождитесь результата.')
                return True
            draft=self.draft(user)
            text=message.get('text','');command,_,value=text.partition(' ')
            command=command.split('@',1)[0]
            try:
                if command in ('/start','/help'):
                    self.telegram.send(user,HELP);return True
                if command=='/cancel':
                    self.save(user,{});self.telegram.send(user,'Введённые файлы и пароль очищены.');return True
                if command in ('/install','/status'):
                    result=status_reply(self.store,message,os.environ.get('APPSTORE_SUPPORT_URL','https://t.me/appleipa095'))
                    if result:self.telegram.call('sendMessage',result)
                    return True
                document=message.get('document')
                if document:
                    ext=Path(document.get('file_name','')).suffix.lower()
                    if ext not in ('.p12','.mobileprovision'):
                        self.telegram.send(user,'Нужны только два файла: .p12 и .mobileprovision.');return True
                    material=self.telegram.file(document)
                    draft['p12' if ext=='.p12' else 'profile']=base64.b64encode(material).decode()
                    draft.setdefault('password','1')
                    if ext=='.mobileprovision' and 'udid' not in draft:
                        decoded=subprocess.run(['openssl','cms','-verify','-inform','DER','-noverify'],
                                               input=material,capture_output=True,check=True,timeout=15).stdout
                        devices=plistlib.loads(decoded).get('ProvisionedDevices',[])
                        if len(devices)==1:
                            check_udid(devices[0]);draft['udid']=devices[0]
                elif command=='/password':
                    # /password followed by one space denotes an intentionally empty password.
                    if ' ' not in text:raise ValueError('Password argument required')
                    draft['password']=value
                elif command=='/udid':
                    check_udid(value.strip());draft['udid']=value.strip()
                    self.save(user,draft)
                    if not draft.get('p12') and not draft.get('profile') and self.provider_key:
                        self.busy.add(user)
                        self.telegram.send(user,'Проверяем готовый сертификат по UDID. Новая регистрация и списание не выполняются.')
                        self.executor.submit(self.provider_job,user,draft)
                        return True
                elif command!='/sign':
                    self.telegram.send(user,HELP);return True
                self.save(user,draft)
                self.maybe_prepare(user,draft)
            except Exception:
                self.telegram.send(user,'Не удалось принять данные. Проверьте тип файлов, UDID и команду пароля. Для нового комплекта: /cancel.')
            return True

    def maybe_prepare(self, user, draft):
        fields={'p12':'файл .p12','profile':'файл .mobileprovision','password':'пароль (/password …)','udid':'UDID (/udid …)'}
        missing=[label for key,label in fields.items() if key not in draft]
        if missing:
            self.telegram.send(user,'Принято. Ещё нужно: '+', '.join(missing)+'.');return
        self.busy.add(user)
        self.telegram.send(user,'Готовим персональный AppStore+. После подписи появится кнопка установки.')
        self.executor.submit(self.sign_job,user,dict(draft))

    def provider_job(self,user,draft):
        try:
            response=fetch_certificate(draft['udid'],self.provider_key)
            entries=response if isinstance(response,list) else [response]
            matching=[row for row in entries if isinstance(row,dict) and row.get('udid')==draft['udid']]
            override=None if len(matching)==1 and isinstance(matching[0].get('p12_password'),str) else '1'
            payload,_=certificate_payload(response,draft['udid'],override)
            draft.update(p12=payload['p12'],profile=payload['profile'],password=payload['password'])
            with self.lock:self.save(user,draft)
            self.sign_job(user,draft)
        except Exception:
            with self.lock:self.busy.discard(user)
            try:self.telegram.send(user,'Готовый сертификат не получен. Нужен доступ API провайдера и выпущенный профиль. Можно прислать свои .p12 и .mobileprovision.')
            except Exception:pass

    def sign_job(self,user,draft):
        try:
            self.delivery.cleanup()
            result=self.delivery.prepare(user,draft['udid'],base64.b64decode(draft['p12'],validate=True),
                                         base64.b64decode(draft['profile'],validate=True),draft['password'],self.access_days)
            with self.lock:self.save(user,{})
            text = ('AppStore+ подготовлен. Откройте ссылку в Safari. Сертификат подключится автоматически; для доступа к магазину введите индивидуальный ключ владельца.' if result.get('requiresLicense') else 'AppStore+ подготовлен. Доступ до '+result['expiresAt'][:10]+'. Откройте ссылку в Safari.')
            self.telegram.send(user,text,result['installURL'])
        except Exception:
            # Draft is retained encrypted for an explicit retry. No exception bodies contain logs.
            try:self.telegram.send(user,'Подготовка не завершена. Проверьте пароль, UDID, срок сертификата и настройки подписи. Повтор: /sign. Последняя готовая ссылка: /install.')
            except Exception:pass
        finally:
            with self.lock:self.busy.discard(user)


def main():
    os.umask(0o077)
    store=configured_store();delivery=configured_delivery(store)
    allowed={int(value) for value in os.environ['APPSTORE_DELIVERY_ALLOWED_IDS'].split(',') if value.strip()}
    telegram=Telegram(os.environ['APPSTORE_BOT_TOKEN'])
    bot=DeliveryBot(store,delivery,telegram,allowed,int(os.environ.get('APPSTORE_ACCESS_DAYS','30')),
                    os.environ.get('ONE_IBOT_API_KEY'))
    with store.db() as db:
        row=db.execute('SELECT offset FROM bot_state WHERE id=1').fetchone();offset=row[0] if row else 0
    try:
        while True:
            try:
                for update in telegram.call('getUpdates',{'offset':offset,'timeout':25,'allowed_updates':['message']}):
                    if update.get('message'):bot.handle(update['message'])
                    offset=update['update_id']+1
                    with store.db() as db:db.execute('INSERT OR REPLACE INTO bot_state VALUES(1,?)',(offset,))
                delivery.cleanup()
                with store.db() as db:db.execute('DELETE FROM bot_drafts WHERE expires<=?',(time.time(),))
            except (KeyboardInterrupt,SystemExit):break
            except Exception:
                print('Telegram unavailable; retrying without logging private data.',flush=True);time.sleep(5)
    finally:bot.executor.shutdown(wait=True)


if __name__=='__main__':main()
