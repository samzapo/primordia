#!/usr/bin/env python3
"""Check narrow rule scope, concurrent edits, rollback and preservation of existing settings."""
from copy import deepcopy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from synology_firewall_plan import build,verify,new_rule
from synology_firewall import apply_rules

TARGET='2601:19b:401:f7b5:b5b3:46f8:f424:fb33'
POLICY={key:'deny' for key in ['ipv4_wan_to_lan','ipv4_wan_to_srm','ipv6_wan_to_lan','ipv6_wan_to_srm']}

class Fixture:
    def __init__(self,value,*,concurrent=False,broaden=False):
        self.value=deepcopy(value);self.calls=[];self.reads=0;self.concurrent=concurrent;self.broaden=broaden
        self.apis={'SYNO.Core.Security.Firewall.Rules':{'path':'entry.cgi','minVersion':2,'maxVersion':2}}
    def read(self,api):
        if api=='SYNO.Core.Security.Firewall.Rules':
            self.reads+=1
            if self.concurrent and self.reads==2:self.value['default_policy']['ipv4_wan_to_lan']='allow'
            return deepcopy(self.value)
        if api=='SYNO.Core.Security.Firewall.Forward.Rules':return {'rules':[{'keep':'existing forwarding'}]}
        if api=='SYNO.Core.Security.Firewall.AllowSrmFromWan':return {'enable':False}
        raise AssertionError('Unexpected API read')
    def call(self,path,fields):
        self.calls.append(deepcopy(fields));self.value={'rules':json.loads(fields['rules']),'default_policy':json.loads(fields['default_policy'])}
        if self.broaden and len(self.calls)==1:self.value['rules'][-1]['dst_ip_type']='all'
        return {}

class Firewall(unittest.TestCase):
    def test_scope_preservation_and_idempotence(self):
        original={'ui_id':7,'name':'Existing unrelated rule','opaque':{'retain':[1,2]}}
        before={'default_policy':POLICY,'rules':[original]}
        planned,added=build(before,TARGET)
        self.assertEqual(planned['rules'][0],original);self.assertEqual(before['rules'],[original])
        self.assertEqual(planned['default_policy'],POLICY);self.assertEqual(len(added),2)
        for row in added:
            self.assertEqual((row['chain'],row['in_interface_type'],row['ip_version'],row['protocol']),('forward','specific','v6','tcp'))
            self.assertEqual((row['dst_ip_type'],row['dst_ip_value']),('single',TARGET))
            self.assertEqual(row['in_interface_value'],['wan']);self.assertEqual(row['out_interface_value'],['lbr0'])
            self.assertIn(row['dst_port_value'],{'80','8766'})
        verify(before,planned,TARGET)
        again,new=build(planned,TARGET);self.assertEqual(again,planned);self.assertEqual(new,[])
        for invalid in ['::1','fe80::1','192.168.1.25',TARGET+'/64','['+TARGET+']']:
            with self.assertRaises(ValueError):build(before,invalid)
        with self.assertRaises(ValueError):new_rule(TARGET,8767,0)
        broad=deepcopy(planned);broad['rules'][-1]['ip_version']='both_v4_v6'
        with self.assertRaises(ValueError):verify(before,broad,TARGET)
        changed=deepcopy(planned);changed['default_policy']['ipv6_wan_to_lan']='allow'
        with self.assertRaises(ValueError):verify(before,changed,TARGET)
        conflict=deepcopy(planned);conflict['rules'][-1]['dst_ip_value']='2601:19b:401:f7b5::1234'
        with self.assertRaises(ValueError):build(conflict,TARGET)
    def test_guarded_write_and_rollback(self):
        for concurrent,broaden in [(False,False),(True,False),(False,True)]:
            with tempfile.TemporaryDirectory(prefix='primordia-firewall-') as directory:
                before={'default_policy':deepcopy(POLICY),'rules':None};router=Fixture(before,concurrent=concurrent,broaden=broaden)
                if concurrent or broaden:
                    with self.assertRaises(ValueError):apply_rules(router,TARGET,Path(directory))
                else:
                    report=apply_rules(router,TARGET,Path(directory));self.assertTrue(report['firewall_updated']);verify(before,router.value,TARGET)
                if concurrent:self.assertEqual(router.calls,[])
                if broaden:self.assertEqual(router.value,{'default_policy':POLICY,'rules':[]});self.assertEqual(len(router.calls),2)
                for call in router.calls:self.assertEqual((call['api'],call['method'],call['version']),('SYNO.Core.Security.Firewall.Rules','set',2))
                for path in Path(directory).iterdir():self.assertEqual(path.stat().st_mode & 0o777,0o600)

if __name__=='__main__':unittest.main()
