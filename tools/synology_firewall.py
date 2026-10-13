#!/usr/bin/env python3
"""Inspect the exact Primordia IPv6 destination and vendor firewall schema."""
import ipaddress,json,os,re,subprocess
from pathlib import Path
from synology_ipv6 import Router
from synology_ui_inspect import fetch

def inspect():
    router=Router('192.168.1.1',os.environ['PRIMORDIA_ROUTER_CERT_SHA256'])
    try:
        router.discover();router.login(os.environ['PRIMORDIA_ROUTER_USERNAME'],os.environ['PRIMORDIA_ROUTER_PASSWORD'])
        data=router.read('SYNO.Core.Security.Firewall.Rules')
        root=Path.home()/'.local/share/primordia-deploy/router-firewall'
        root.mkdir(parents=True,exist_ok=True,mode=0o700)
        snapshot=root/('before-'+os.environ.get('GITHUB_RUN_ID','local')+'.json')
        fd=os.open(snapshot,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as out:json.dump(data,out,sort_keys=True);out.flush();os.fsync(out.fileno())
        entries=json.loads(subprocess.check_output(['ip','-j','-6','addr','show','dev','enp4s0'],text=True))
        candidates=[a for e in entries for a in e.get('addr_info',[]) if ipaddress.ip_address(a['local']).is_global and not any(a.get(k) for k in ['temporary','deprecated','tentative'])]
        listeners=subprocess.check_output(['ss','-ltn','sport = :80 or sport = :8766 or sport = :8767'],text=True)
        print(json.dumps({'firewall_inspection':True,'read_only':True,'default_policy':data.get('default_policy'),'rule_count':len(data.get('rules') or []),'rule_schema':sorted({key for r in (data.get('rules') or []) for key in r}),'all_global_ipv6':[a for e in entries for a in e.get('addr_info',[]) if ipaddress.ip_address(a['local']).is_global],'ipv6_candidates':candidates,'listeners':listeners,'ipv6_default_route':json.loads(subprocess.check_output(['ip','-6','-j','route','show','default'],text=True)),'snapshot':str(snapshot)}))
        source=fetch('/webman/modules/nsm-Home/NSMHome.js',router.sid)
        for private in [router.sid,router.synotoken,os.environ['PRIMORDIA_ROUTER_USERNAME'],os.environ['PRIMORDIA_ROUTER_PASSWORD']]:
            if private:source=source.replace(private,'[redacted]')
        source=source[source.index('Ext.define("SYNO.SDS.NSMHome.Security.Firewall'):]
        for term in ['created_by:"user"','inputValue:"wan"','inputValue:"custom"','in_interface_type:"wan"','inInterfaceWan','dst_port_type:"custom"','profile:']:
            excerpts=[]
            for match in list(re.finditer(re.escape(term),source))[:2]:
                excerpts.append(source[max(0,match.start()-1300):match.end()+400])
            if excerpts:print(json.dumps({'vendor_term':term,'definitions':excerpts}))
    finally:router.logout()

if __name__=='__main__':inspect()
