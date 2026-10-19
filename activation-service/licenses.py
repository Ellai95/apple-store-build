"""Paid access: owner-issued, device-bound, one-time keys; no public issuance API."""
import argparse
import calendar
import math
from datetime import datetime, timezone
import secrets
import time
from service import Store, APIError, date, digest

PLANS = {
    'external_6m': dict(group='external', months=6, rub=1000, title='6 месяцев'),
    'external_12m': dict(group='external', months=12, rub=2000, title='1 год'),
    'external_lifetime': dict(group='external', months=None, rub=3500, title='Навсегда'),
    'customer_1m': dict(group='customer', months=1, rub=300, title='1 месяц'),
    'customer_3m': dict(group='customer', months=3, rub=500, title='3 месяца'),
    'customer_6m': dict(group='customer', months=6, rub=800, title='6 месяцев'),
    'customer_12m': dict(group='customer', months=12, rub=1000, title='1 год'),
}


def add_months(stamp, months):
    value = datetime.fromtimestamp(stamp, timezone.utc)
    index = value.year * 12 + value.month - 1 + months
    year, month = divmod(index, 12)
    return value.replace(year=year, month=month+1, day=min(value.day, calendar.monthrange(year, month+1)[1])).timestamp()


class LicenseStore(Store):
    paid_access = True

    def __init__(self, path, master_key):
        super().__init__(path, master_key)
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS licenses (
              device_id TEXT PRIMARY KEY, telegram_id INTEGER NOT NULL,
              starts REAL NOT NULL, ends REAL, lifetime INTEGER NOT NULL,
              revoked INTEGER NOT NULL DEFAULT 0, plan TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS license_keys (
              hash TEXT PRIMARY KEY, device_id TEXT NOT NULL, telegram_id INTEGER NOT NULL,
              plan TEXT NOT NULL, issued REAL NOT NULL, revoked INTEGER NOT NULL DEFAULT 0,
              redeemed REAL, redeemed_account TEXT);
            ''')

    def provision(self, telegram_id, device_id, payload, starts, ends, cert_ends):
        # Enrollment refreshes certificate delivery; it never grants/extends paid time.
        if telegram_id <= 0 or not device_id or cert_ends <= time.time():
            raise ValueError('Invalid enrollment')
        with self.db() as db:
            existing = db.execute('SELECT * FROM accounts WHERE device_id=? ORDER BY created LIMIT 1', (device_id,)).fetchone()
            if existing:
                if existing['telegram_id'] != telegram_id or existing['revoked']:
                    raise ValueError('Device belongs to another account or has been revoked')
                account_id, code = existing['id'], secrets.token_urlsafe(32)
                db.execute('UPDATE accounts SET credentials=?,cert_ends=?,ends=?,code_hash=?,code_ends=? WHERE id=?',
                           (self.seal(account_id,payload),cert_ends,cert_ends,digest(code),min(cert_ends,time.time()+7*86400),account_id))
                return account_id, code
            account_id, code = secrets.token_urlsafe(18), secrets.token_urlsafe(32)
            now = time.time()
            db.execute('INSERT INTO accounts VALUES(?,?,?,?,?,?,0,?,?,?,NULL,NULL,?)',
                       (account_id,telegram_id,device_id,now,cert_ends,cert_ends,
                        self.seal(account_id,payload),digest(code),min(cert_ends,now+7*86400),now))
            return account_id, code

    def enrollment_allowed(self, row):
        return not row['revoked'] and row['cert_ends'] > time.time()

    def delivery_allowed(self, row):
        return self.enrollment_allowed(row)

    def credentials_allowed(self, row):
        return self.enrollment_allowed(row)

    def status(self, row):
        now = time.time()
        with self.db() as db:
            license = db.execute('SELECT * FROM licenses WHERE device_id=? AND telegram_id=?',
                                 (row['device_id'],row['telegram_id'])).fetchone()
        license_state = ('unlicensed' if license is None else 'revoked' if license['revoked'] else
                         'active' if license['lifetime'] or license['ends'] > now else 'expired')
        state = ('revoked' if row['revoked'] else license_state if license_state != 'active' else
                 'certificate_expired' if row['cert_ends'] <= now else 'active')
        lifetime = bool(license and license['lifetime'])
        expiry = license['ends'] if license and not lifetime else None
        return dict(accountID=row['id'],deviceID=row['device_id'],status=state,licenseStatus=license_state,
                    connectedAt=date(license['starts'] if license else row['starts']),
                    expiresAt=date(expiry if expiry is not None else row['cert_ends']),
                    licenseConnectedAt=date(license['starts']) if license else None,
                    licenseExpiresAt=date(expiry) if expiry is not None else None,
                    certificateExpiresAt=date(row['cert_ends']), lifetime=lifetime,
                    remainingDays=max(0,math.ceil((expiry-now)/86400)) if expiry is not None else 0,
                    planID=license['plan'] if license else None, serverTime=date(now), requiresLicense=True)

    def issue_key(self, account_id, plan_id):
        if plan_id not in PLANS: raise ValueError('Unknown plan')
        key = 'ASP-' + secrets.token_urlsafe(24)
        with self.db() as db:
            row = db.execute('SELECT * FROM accounts WHERE id=?', (account_id,)).fetchone()
            if row is None or row['revoked']: raise ValueError('Unknown or revoked account')
            db.execute('INSERT INTO license_keys(hash,device_id,telegram_id,plan,issued) VALUES(?,?,?,?,?)',
                       (digest(key),row['device_id'],row['telegram_id'],plan_id,time.time()))
        return key

    def redeem_key(self, account, value):
        if not isinstance(value,str) or not 20 <= len(value.strip()) <= 120:
            raise APIError(400,'invalid_license_key')
        now = time.time()
        with self.db() as db:
            row = db.execute('SELECT * FROM license_keys WHERE hash=?', (digest(value.strip()),)).fetchone()
            if row is None or row['revoked']:
                raise APIError(400,'invalid_license_key')
            if row['device_id'] != account['device_id'] or row['telegram_id'] != account['telegram_id']:
                raise APIError(403,'license_wrong_device')
            current_account = db.execute('SELECT * FROM accounts WHERE id=?', (account['id'],)).fetchone()
            if current_account is None or current_account['revoked']:
                raise APIError(403,'access_inactive')
            if row['redeemed'] is None:
                existing = db.execute('SELECT * FROM licenses WHERE device_id=?', (account['device_id'],)).fetchone()
                if existing and (existing['telegram_id'] != account['telegram_id'] or existing['revoked']):
                    raise APIError(403,'access_inactive')
                if existing and existing['lifetime']:
                    raise APIError(409,'already_lifetime')
                plan = PLANS[row['plan']]
                lifetime = plan['months'] is None
                starts = existing['starts'] if existing else now
                origin = max(now,existing['ends']) if existing and existing['ends'] else now
                ends = None if lifetime else add_months(origin,plan['months'])
                db.execute('INSERT INTO licenses VALUES(?,?,?,?,?,0,?) ON CONFLICT(device_id) DO UPDATE SET '
                           'ends=excluded.ends,lifetime=excluded.lifetime,plan=excluded.plan',
                           (account['device_id'],account['telegram_id'],starts,ends,int(lifetime),row['plan']))
                db.execute('UPDATE license_keys SET redeemed=?,redeemed_account=? WHERE hash=?',
                           (now,account['id'],row['hash']))
        return self.status(current_account)


def main():
    from service import configured_store
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command',required=True)
    sub.add_parser('accounts'); sub.add_parser('plans')
    issue = sub.add_parser('issue'); issue.add_argument('--account',required=True); issue.add_argument('--plan',choices=PLANS,required=True)
    revoke = sub.add_parser('revoke-key'); revoke.add_argument('--key-file',required=True)
    for action in ('revoke-license','restore-license'):
        block = sub.add_parser(action); block.add_argument('--account',required=True)
    args = parser.parse_args(); store = configured_store()
    if not isinstance(store,LicenseStore): raise ValueError('Enable APPSTORE_PAID_ACCESS=1')
    if args.command == 'issue':
        # The owner selects the plan and verifies purchase history; clients cannot set a discount.
        print(store.issue_key(args.account,args.plan))
    elif args.command == 'plans':
        for id,plan in PLANS.items(): print(id,plan['title'],str(plan['rub'])+' RUB')
    elif args.command == 'accounts':
        with store.db() as db:
            for row in db.execute('SELECT id,telegram_id,device_id FROM accounts'): print(row['id'],row['telegram_id'],row['device_id'])
    elif args.command == 'revoke-key':
        from pathlib import Path
        with store.db() as db: db.execute('UPDATE license_keys SET revoked=1 WHERE hash=?',(digest(Path(args.key_file).read_text().strip()),))
    elif args.command in ('revoke-license','restore-license'):
        account = store.account(args.account)
        if account is None: raise ValueError('Unknown account')
        with store.db() as db: db.execute('UPDATE licenses SET revoked=? WHERE device_id=?',(int(args.command == 'revoke-license'),account['device_id']))


if __name__ == '__main__': main()
