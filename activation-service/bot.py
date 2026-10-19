"""Private-chat replies only. No billing or Apple credentials are accepted via Telegram."""
import json
import os
import time
import urllib.request
from service import configured_store


def reply(store, message, support):
    sender, chat = message.get('from',{}), message.get('chat',{})
    if chat.get('type') != 'private' or sender.get('is_bot') or chat.get('id') != sender.get('id'):
        return None
    command = message.get('text','').split(' ',1)[0].split('@',1)[0]
    if command not in ('/start','/install','/status','/support'):
        return dict(chat_id=chat['id'],text='Команды AppStore+: /install — установка, /status — срок доступа, /support — помощь.')
    if command == '/support':
        return dict(chat_id=chat['id'],text='Поддержка AppStore+: '+support)
    with store.db() as db:
        rows = db.execute('SELECT * FROM accounts WHERE telegram_id=? ORDER BY created DESC', (sender['id'],)).fetchall()
    if not rows:
        return dict(chat_id=chat['id'],text='AppStore+\nДля вашего Telegram пока нет подключённого устройства. Для оформления доступа: '+support)
    text, buttons = ['AppStore+'], []
    for index,row in enumerate(rows,1):
        status = store.status(row)
        label = dict(active='Активен',expired='Истёк',pending='Ожидает подключения',revoked='Приостановлен',unlicensed='Нужен ключ доступа',certificate_expired='Нужна замена сертификата')[status['status']]
        expiry = 'Навсегда' if status.get('lifetime') else status['expiresAt'][:10]
        text.append(f"Устройство {index}: {label}")
        if status['status'] != 'unlicensed': text.append(f"Доступ до: {expiry}")
        if store.delivery_allowed(row):
            if row['install_url']:
                buttons.append([dict(text=f'Установить AppStore+ · устройство {index}',url=row['install_url'])])
            else:
                text.append('Персональная ссылка готовится. Сообщим о готовности при следующей проверке /install.')
    text.append('Откройте ссылку в Safari. В AppStore+ введите индивидуальный ключ доступа.' if getattr(store,'paid_access',False) else 'Откройте ссылку в Safari. При первом запуске доступ подключится автоматически.')
    result = dict(chat_id=chat['id'],text='\n\n'.join(text))
    if buttons: result['reply_markup'] = dict(inline_keyboard=buttons)
    return result


def main():
    token = os.environ['APPSTORE_BOT_TOKEN']
    support = os.environ['APPSTORE_SUPPORT_URL']
    if not support.startswith('https://t.me/'): raise ValueError('Use your support Telegram link')
    store = configured_store()
    def call(method,payload):
        request = urllib.request.Request('https://api.telegram.org/bot'+token+'/'+method,
                                         data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=40) as response:
            data = json.load(response)
        if not data.get('ok'): raise RuntimeError('Telegram request failed')
        return data['result']
    with store.db() as db:
        row = db.execute('SELECT offset FROM bot_state WHERE id=1').fetchone()
        offset = row[0] if row else 0
    while True:
        try:
            for update in call('getUpdates',dict(offset=offset,timeout=25,allowed_updates=['message'])):
                message = update.get('message')
                result = reply(store,message,support) if message else None
                if result: call('sendMessage',result)
                offset = update['update_id']+1
                with store.db() as db:
                    db.execute('INSERT OR REPLACE INTO bot_state VALUES(1,?)',(offset,))
        except (KeyboardInterrupt,SystemExit):
            return
        except Exception:
            # Avoid token-bearing URLs from urllib exceptions in logs.
            print('Telegram unavailable; retrying.',flush=True)
            time.sleep(5)

if __name__ == '__main__': main()
