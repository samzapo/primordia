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
        for term in ['FwCustomPortDialog','FwDstCustomPortDialog','dst_port_value",']:
            excerpts=[]
            for match in list(re.finditer(re.escape(term),source))[:5]:
                excerpts.append(source[max(0,match.start()-1300):match.end()+400])
            if excerpts:print(json.dumps({'vendor_term':term,'definitions':excerpts}))
    finally:router.logout()


def selected_address(requested):
    from synology_firewall_plan import address
    target=address(requested)
    entries=json.loads(subprocess.check_output(['ip','-j','-6','addr','show','dev','enp4s0'],text=True))
    records=[a for e in entries for a in e.get('addr_info',[]) if a['local']==target]
    if len(records)!=1 or any(records[0].get(k) for k in ['temporary','tentative','deprecated']) or records[0].get('preferred_life_time',0)==0:
        raise ValueError('Selected IPv6 address is not currently assigned and preferred on the game desktop')
    listeners=subprocess.check_output(['ss','-H','-ltn','sport = :8766'],text=True)
    assigned={a['local'] for e in entries for a in e.get('addr_info',[]) if ipaddress.ip_address(a['local']).is_global}
    bound=set(re.findall(r'\[([0-9a-fA-F:]+)\]:8766',listeners))
    if not (assigned & bound):
        raise ValueError('No configured IPv6 game listener on this desktop; no rule write authorized')
    return target,records[0]

def save_snapshot(root,name,value):
    root.mkdir(parents=True,exist_ok=True,mode=0o700)
    path=root/name
    descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'w') as stream:json.dump(value,stream,sort_keys=True,indent=2);stream.flush();os.fsync(stream.fileno())
    return str(path)

def write_rules(router,value):
    # The only configuration mutation in this tool is this one firewall endpoint.
    api='SYNO.Core.Security.Firewall.Rules';entry=router.apis[api]
    if not (entry['minVersion']<=2<=entry['maxVersion']):raise ValueError('SRM version-2 firewall API required')
    return router.call(entry['path'],{'api':api,'version':2,'method':'set',
                                     'rules':json.dumps(value['rules'],separators=(',',':')),
                                     'default_policy':json.dumps(value['default_policy'],separators=(',',':'))})

def apply_rules(router,target,root):
    from synology_firewall_plan import build,digest,verify
    before=router.read('SYNO.Core.Security.Firewall.Rules')
    forward=router.read('SYNO.Core.Security.Firewall.Forward.Rules')
    admin=router.read('SYNO.Core.Security.Firewall.AllowSrmFromWan')
    request,added=build(before,target)
    prefix=os.environ.get('GITHUB_RUN_ID','local')+'-'+os.environ.get('GITHUB_RUN_ATTEMPT','1')
    backup=save_snapshot(root,'before-'+prefix+'.json',{'firewall':before,'forward_rules':forward,'remote_admin':admin,'destination':target})
    save_snapshot(root,'planned-'+prefix+'.json',request)
    if digest(router.read('SYNO.Core.Security.Firewall.Rules'))!=digest(before):
        raise ValueError('Firewall changed while preparing; no write attempted')
    if added:
        try:
            write_rules(router,request)
            after=router.read('SYNO.Core.Security.Firewall.Rules')
            verify(before,after,target)
        except Exception:
            # Recover only our new entries. Keep any concurrent unrelated state.
            current=router.read('SYNO.Core.Security.Firewall.Rules')
            try:verify(before,current,target)
            except ValueError:
                names={row['name'] for row in added}
                survivors=[row for row in (current.get('rules') or []) if row.get('name') not in names]
                if survivors==(before.get('rules') or []):
                    write_rules(router,{'rules':survivors,'default_policy':current['default_policy']})
                    save_snapshot(root,'rollback-'+prefix+'.json',router.read('SYNO.Core.Security.Firewall.Rules'))
                raise
            after=current # Write response lost, but readback proves the requested state.
    else:after=router.read('SYNO.Core.Security.Firewall.Rules');verify(before,after,target)
    save_snapshot(root,'after-'+prefix+'.json',after)
    if router.read('SYNO.Core.Security.Firewall.Forward.Rules')!=forward:raise ValueError('Forwarding configuration changed concurrently; inspection required')
    if router.read('SYNO.Core.Security.Firewall.AllowSrmFromWan')!=admin:raise ValueError('Remote administration setting changed concurrently; inspection required')
    return {'firewall_updated':True,'destination':target,'destination_prefix_length':128,
            'ports':[80,8766],'protocol':'tcp','source_interface':'wan','chain':'forward',
            'default_policy':after['default_policy'],'added_rule_names':[row['name'] for row in added],
            'preserved_existing_rules':len(before.get('rules') or []),'backup':backup}

def apply():
    import socket
    if os.environ.get('GITHUB_REPOSITORY')!='samzapo/primordia' or os.environ.get('RUNNER_NAME')!='samzapo-desktop' or socket.gethostname()!='samzapo-desktop':
        raise ValueError('Only the owner-authorized Primordia target may apply these firewall rules')
    target,record=selected_address(os.environ.get('PRIMORDIA_FIREWALL_ADDRESS',''))
    router=Router('192.168.1.1',os.environ['PRIMORDIA_ROUTER_CERT_SHA256'])
    try:
        router.discover();router.login(os.environ['PRIMORDIA_ROUTER_USERNAME'],os.environ['PRIMORDIA_ROUTER_PASSWORD'])
        report=apply_rules(router,target,Path.home()/'.local/share/primordia-deploy/router-firewall')
        report['destination_temporary']=bool(record.get('temporary'))
        report['https_url']='https://['+target+']:8766/'
        print(json.dumps(report))
        result=subprocess.run(['curl','--noproxy','*','-6','--connect-timeout','5','--max-time','10','--fail','--silent','--show-error','https://['+target+']:8766/health'],capture_output=True,text=True)
        health={'https_check':True,'scope':'from_the_game_desktop','exit_code':result.returncode}
        if result.returncode==0:
            value=json.loads(result.stdout);health['game']={key:value.get(key) for key in ['world_id','epoch','tick','backend','gpu','backend_error','checkpoint_error']}
        else:health['reason']='Public HTTPS certificate/connection not yet verified'
        print(json.dumps(health))
    finally:router.logout()

if __name__=='__main__':
    if os.environ.get('PRIMORDIA_FIREWALL_APPLY')=='true':apply()
    else:inspect()
