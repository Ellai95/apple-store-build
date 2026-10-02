#!/usr/bin/env python3
"""Validate/publish catalog metadata; no IPA download and no credentials required."""
import argparse,json,re,time,datetime
from pathlib import Path
from urllib.parse import urlparse

def validate(doc):
    assert doc['schemaVersion']==1 and isinstance(doc['revision'],int) and doc['revision']>0
    apps=doc['apps'];assert 0<len(apps)<=5000 and len({a['id'] for a in apps})==len(apps)
    def https(value):
        u=urlparse(value);return u.scheme=='https' and bool(u.hostname) and not u.username and not u.password
    for a in apps:
        assert re.fullmatch(r'[A-Za-z0-9_-]{1,100}',a['id']),a['id']
        for key in ['name','category','subtitle','description','version','size','ipaUrl','kind','searchTerms','addedAt','updatedAt']:assert isinstance(a[key],str),(a['id'],key)
        assert a['name'].strip()
        assert isinstance(a['featured'],bool) and isinstance(a['isMod'],bool)
        assert isinstance(a['modFeatures'],list)
        assert not a['ipaUrl'] or https(a['ipaUrl'])
        assert not a.get('iconURL') or https(a['iconURL'])
        assert len(a.get('screenshots',[]))<=50 and all(https(u) for u in a.get('screenshots',[]))
        if a.get('rating'):assert 0<=a['rating']['value']<=5 and a['rating']['count']>=0
        if a['kind']=='subscription':assert not a['ipaUrl'] and a['subscriptionPlans']
    for name,host in [('telegram','t.me'),('whatsapp','wa.me'),('news','t.me')]:
        value=doc['contacts'].get(name,'');assert not value or (https(value) and urlparse(value).hostname==host)
    return len(apps)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('catalog',type=Path);p.add_argument('--publish',action='store_true',help='Increase revision and update publishedAt');p.add_argument('--whatsapp',help='International number, digits only');args=p.parse_args()
    d=json.loads(args.catalog.read_text(encoding='utf-8-sig'))
    if args.whatsapp:
        number=re.sub(r'\D','',args.whatsapp);assert 7<=len(number)<=15;d['contacts']['whatsapp']='https://wa.me/'+number
    count=validate(d)
    if args.publish or args.whatsapp:
        d['revision']=max(int(time.time()),d['revision']+1);d['publishedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        args.catalog.with_suffix('.json.backup').write_bytes(args.catalog.read_bytes())
        tmp=args.catalog.with_suffix('.json.tmp');tmp.write_text(json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8');tmp.replace(args.catalog)
    print(f'OK: {count} apps, revision {d["revision"]}')
if __name__=='__main__':main()
