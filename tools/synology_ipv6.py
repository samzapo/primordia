#!/usr/bin/env python3
"""Read-only, certificate-pinned Synology IPv6 discovery; never change router settings."""
import hashlib
from http.client import HTTPSConnection
import json
import os
from pathlib import Path
import re
import secrets
import ssl
from urllib.parse import urlencode

ALLOWED = {"SYNO.Core.System", "SYNO.Core.Network.IPv6", "SYNO.Core.Network.IPv6.Router",
           "SYNO.Core.Network.IPv6.Router.Prefix", "SYNO.Core.Security.Firewall.Forward.Conf",
           "SYNO.Core.Security.Firewall.Conf", "SYNO.Core.Security.Firewall.AllowSrmFromWan",
           "SYNO.Core.Network.Ethernet", "SYNO.Core.Network.LocalBridge", "SYNO.Core.Network.LocalNetwork", "SYNO.Core.Security.Firewall.Rules", "SYNO.Core.Security.Firewall.Forward.Rules"}

class RouterError(Exception):
    pass

class Router:
    def __init__(self, host, fingerprint, port=8001):
        if host != "192.168.1.1" or port != 8001:
            raise RouterError("Only the owner-authorized Synology LAN endpoint is allowed")
        if not re.fullmatch(r"[0-9a-fA-F]{64}",fingerprint):
            raise RouterError("Provide the router certificate SHA-256 pin")
        self.host=host; self.port=port; self.fingerprint=fingerprint.lower()
        self.sid="";self.synotoken="";self.apis={}

    def call(self, path, fields):
        if not re.fullmatch(r"[a-zA-Z0-9_/.]+\.cgi",path) or ".." in path:
            raise RouterError("Invalid API path")
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname=False;context.verify_mode=ssl.CERT_NONE
        connection=HTTPSConnection(self.host,self.port,timeout=10,context=context)
        try:
            connection.connect()
            actual=hashlib.sha256(connection.sock.getpeercert(binary_form=True)).hexdigest()
            # Exact pin verification occurs before request encoding/sending any credentials.
            if not secrets.compare_digest(actual,self.fingerprint):
                raise RouterError("Router certificate pin mismatch; no credentials sent")
            data=dict(fields)
            if self.sid:data['_sid']=self.sid
            headers={'Content-Type':'application/x-www-form-urlencoded'}
            if self.sid:headers['Cookie']='id='+self.sid
            if self.synotoken:
                headers['X-SYNO-TOKEN']=self.synotoken
                data['SynoToken']=self.synotoken
            connection.request('POST','/webapi/'+path,body=urlencode(data).encode(),headers=headers)
            response=connection.getresponse();body=response.read(131073)
            if response.status!=200 or len(body)>131072:
                raise RouterError("Router returned an invalid or oversized response")
            try:value=json.loads(body)
            except (ValueError,UnicodeError):raise RouterError("Router returned a non-JSON response")
            if not value.get('success'):
                code=value.get('error',{}).get('code','unknown')
                if not isinstance(code,int):code='unknown'
                raise RouterError("Synology API rejected request (code "+str(code)+")")
            return value.get('data',{})
        finally:connection.close()

    def discover(self):
        self.apis=self.call('query.cgi',{'api':'SYNO.API.Info','version':1,'method':'query','query':','.join(sorted(ALLOWED|{'SYNO.API.Auth'}))})

    def login(self, username, password):
        if not username or not password:raise RouterError("Router account secrets are missing")
        auth=self.apis.get('SYNO.API.Auth')
        if not auth:raise RouterError("Router did not advertise its authentication API")
        data=self.call(auth['path'],{'api':'SYNO.API.Auth','version':min(3,auth['maxVersion']),
                                    'method':'login','account':username,'passwd':password,
                                    'session':'webui','format':'sid','enable_syno_token':'yes','dsm_version':3})
        self.sid=data.get('sid','');self.synotoken=data.get('synotoken','')
        if not self.sid:raise RouterError("Router login returned no session")

    def read(self, api, *, interface=None):
        if api not in ALLOWED:raise RouterError("Router operation is outside the read-only allowlist")
        entry=self.apis.get(api)
        if not entry:raise RouterError("Required router API unavailable")
        fields={'api':api,'version':entry['minVersion'],'method':'info' if api=='SYNO.Core.System' else 'list' if api in {'SYNO.Core.Network.IPv6.Router.Prefix','SYNO.Core.Network.Ethernet','SYNO.Core.Network.LocalNetwork'} else 'get'}
        if api=='SYNO.Core.Network.LocalNetwork':fields['version']=entry['maxVersion']
        if api=='SYNO.Core.Network.LocalBridge':fields['ifname']='lbr0'
        if interface is not None:
            if api not in {'SYNO.Core.Network.IPv6','SYNO.Core.Network.IPv6.Router'} or interface not in {'wan','lan','lan1','br0','lbr0','lbr1','eth0'}:
                raise RouterError("Interface is outside the read-only allowlist")
            fields['wan' if api=='SYNO.Core.Network.IPv6.Router' else 'ifname']=interface
        return self.call(entry['path'],fields)

    def logout(self):
        if self.sid:
            try:self.call(self.apis['SYNO.API.Auth']['path'],{'api':'SYNO.API.Auth','version':1,'method':'logout','session':'webui'})
            except (OSError,RouterError):pass
            self.sid='';self.synotoken=''

# Never print raw configuration, account details, session IDs, Wi-Fi or WAN secrets.
DISPLAY_KEYS={'model','version','major','minor','build','buildnumber','productversion',
              'enable','enabled','mode','type','prefix','prefix_len','prefix_length',
              'ipv6','ipv6addr','ipv6_addr','ipv6_prefix','ipv6_enable','gateway','default_gateway',
              'wan_ipv6','wan_ipv6_forward','default_action','default_policy','policy',
              'allow_srm_from_wan','allow_external_access','ifname','interface',
              'firmware_ver','ip','router','is_default_gateway','is_persisted_link_local','is_enabled','enable_ipv6','link','status','name','interface_type','is_primary','netmask','ipv6_router','mode_type','id','action','direction','proto','protocol','dst_port','dst_ports','src_port','dst_ip','src_ip','started','is_auto_mode','net_id','network_id','netid','chain','jump','sync_lan','wan','is_lan','ipv6_enabled','ipv6_type','router_enable','autoconf','dhcpv6_enable','prefix_id','prefixlen','valid_lifetime','preferred_lifetime','port_list','default_policy','config_type','dhcp_mode','auto_dns','prefix_delegation','pd_enable','addr','address','ip6_addr','ip6_prefix','ip6_mode','ipv6_type','enable_port_check','pf_auto_fw_rules','upnp_auto_fw_rules','dmz_auto_fw_rules'}
def summarize(value):
    if isinstance(value,dict):
        result={}
        for key,item in value.items():
            if key in DISPLAY_KEYS and isinstance(item,(str,int,float,bool,type(None))):result[key]=item
            elif isinstance(item,(dict,list)):
                selected=summarize(item)
                if selected:result[key]=selected
        return result
    if isinstance(value,list):return [item for item in (summarize(x) for x in value[:32]) if item]
    return None

def main():
    router=Router('192.168.1.1',os.environ.get('PRIMORDIA_ROUTER_CERT_SHA256',''))
    report={'router':'Synology RT6600ax','address':'192.168.1.1:8001','read_only':True,'apis':{}}
    try:
        router.discover()
        router.login(os.environ.get('PRIMORDIA_ROUTER_USERNAME',''),os.environ.get('PRIMORDIA_ROUTER_PASSWORD',''))
        for api in sorted(ALLOWED):
            try:
                data=router.read(api,interface='wan' if api=='SYNO.Core.Network.IPv6' else 'eth0' if api=='SYNO.Core.Network.IPv6.Router' else None);report['apis'][api]={'status':'read','summary':summarize(data),'field_names':sorted(data) if isinstance(data,dict) else []}
                if api=='SYNO.Core.Security.Firewall.Rules':report['apis'][api].update(default_policy=data.get('default_policy'),rule_count=len(data.get('rules',[])),rule_schema=sorted({key for row in data.get('rules',[]) for key in row}))
            except RouterError as error:report['apis'][api]={'status':'unavailable','reason':str(error)}
        for api,interfaces in [('SYNO.Core.Network.IPv6',['eth0']),('SYNO.Core.Network.IPv6.Router',[])]:
            for interface in interfaces:
                key=api+':'+interface
                try:
                    data=router.read(api,interface=interface)
                    report['apis'][key]={'status':'read','summary':summarize(data),'field_names':sorted(data) if isinstance(data,dict) else []}
                except RouterError as error:report['apis'][key]={'status':'unavailable','reason':str(error)}
    except (OSError,RouterError) as error:
        report['status']='failed';report['reason']=str(error) if isinstance(error,RouterError) else type(error).__name__
    finally:router.logout()
    print(json.dumps(report,indent=2))
    return 1 if report.get('status')=='failed' else 0

if __name__=='__main__':raise SystemExit(main())
