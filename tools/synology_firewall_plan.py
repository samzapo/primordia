#!/usr/bin/env python3
"""Pure, bounded additions to SRM's version-2 firewall rule representation."""
from copy import deepcopy
import hashlib
import ipaddress
import json

RULE_NAMES={8766:'Primordia IPv6 HTTPS',80:'Primordia IPv6 ACME'}

def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def address(value):
    parsed=ipaddress.ip_address(value)
    if parsed.version!=6 or not parsed.is_global:raise ValueError('A single global IPv6 address is required')
    return str(parsed)

def new_rule(destination,port,ui_id):
    if port not in RULE_NAMES:raise ValueError('Only Primordia HTTPS and ACME ports are authorized')
    return {'ui_id':ui_id,'profile':'custom','enabled':True,'name':RULE_NAMES[port],
            'chain':'forward','protocol':'tcp','in_interface_type':'specific','in_interface_value':['wan'],
            'out_interface_type':'specific','out_interface_value':['lbr0'],'src_ip_type':'all','src_ip_value':'',
            'dst_ip_type':'single','dst_ip_value':address(destination),'src_port_type':'all','src_port_value':'',
            'dst_port_type':'custom','dst_port_value':str(port),'ip_version':'v6','action':'allow',
            'logged':False,'created_by':'user'}

def equivalent(row,expected):
    for key,value in expected.items():
        if key=='ui_id':continue # SRM assigns UI indices.
        actual=row.get(key)
        if key=='dst_ip_value':
            try:actual=address(actual)
            except (ValueError,TypeError):return False
        if actual!=value:return False
    return True

def build(before,destination):
    destination=address(destination)
    policy=before.get('default_policy')
    if not isinstance(policy,dict) or any(policy.get(k)!='deny' for k in ['ipv6_wan_to_lan','ipv6_wan_to_srm']):
        raise ValueError('Expected existing IPv6 deny policies; no broad policy change is authorized')
    original=before.get('rules') or []
    if not isinstance(original,list) or any(not isinstance(row,dict) for row in original):raise ValueError('Invalid rule collection')
    rows=deepcopy(original);added=[]
    used={row.get('ui_id') for row in rows};next_id=0
    for port in [8766,80]:
        while next_id in used or next_id in {9527,9528,9529,9530}:next_id+=1
        wanted=new_rule(destination,port,next_id)
        matches=[row for row in rows if row.get('name')==wanted['name']]
        if matches:
            if len(matches)!=1 or not equivalent(matches[0],wanted):raise ValueError('Existing Primordia rule has a different scope; refusing to replace it')
            continue
        used.add(next_id);next_id+=1;rows.append(wanted);added.append(wanted)
    return {'rules':rows,'default_policy':deepcopy(policy)},added

def verify(before,after,destination):
    expected,_=build(before,destination)
    if after.get('default_policy')!=before.get('default_policy'):raise ValueError('Firewall default policies changed')
    rows=after.get('rules') or []
    if not isinstance(rows,list) or len(rows)!=len(expected['rules']):raise ValueError('Unexpected firewall rule count')
    original=before.get('rules') or []
    if rows[:len(original)]!=original:raise ValueError('Existing firewall rules changed')
    for port in [8766,80]:
        wanted=new_rule(destination,port,0)
        matches=[row for row in rows if row.get('name')==wanted['name']]
        if len(matches)!=1 or not equivalent(matches[0],wanted):raise ValueError('Primordia rule scope did not match the authorized IPv6 destination/port')
