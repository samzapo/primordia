extends "res://tests/lineage_start_network.gd"
func run() -> void:
 OS.unset_environment("PRIMORDIA_ACCESS_KEYS_FILE")
 OS.set_environment("PRIMORDIA_INVITE","private-feedback-pass-network-fixture")
 host=Host.new();host.cpu=not ("--gpu" in OS.get_cmdline_user_args());host.port=19000+OS.get_process_id()%20000
 if not host.cpu:root.size=Vector2i(64,64)
 host.store.directory=ProjectSettings.globalize_path("res://build/feedback-pass-network-"+str(OS.get_process_id()))
 host.world=Sim.new(59,0,false);host.world.cells=[host.world.player];host.world.automatic_reproduction=false
 host.world.autonomous_build_retry_at=INF
 host.world.player.add_organ("feeding",0,"graze",false)
 host.world.habitat_geometry=Sim.Habitat.new(59,host.world.cells)
 root.add_child(host)
 check(await until(func():return host.running),"Isolated investment authority starts")
 socket.inbound_buffer_size=Protocol.MAX_FRAME;socket.outbound_buffer_size=65536
 socket.connect_to_url("ws://127.0.0.1:"+str(host.port))
 check(await until(func():return socket.get_ready_state()==WebSocketPeer.STATE_OPEN),"Real investment socket connects")
 socket.send_text(JSON.stringify({"op":"hello","invite":OS.get_environment("PRIMORDIA_INVITE"),"snapshot_ack":true,"death_events":true}))
 check(await until(func():return messages.any(func(m):return m.get("kind","")=="welcome")),"Fixture account signs in")
 var welcome: Dictionary=messages.filter(func(m):return m.get("kind","")=="welcome")[0]
 var account: Dictionary=host.accounts[welcome.token.sha256_text()]
 var selected=host._selected(account)
 var points: int=selected.ap
 var command: Dictionary={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":1,"action":"investment","args":{"scope":"lineage","kind":"producer"}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(1).is_empty()),"Investment command returns a durable receipt")
 check(result(1).ok and selected.ap==points and host.world.investment.lineages[account.root]=="producer","Changing strategy is free and scoped to the authenticated family")
 var saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.world.investment.lineages[account.root]=="producer","Successful policy edit is already in the checkpoint")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==1).size()==2),"Retried policy command returns its original receipt")
 check(host.world.investment.lineages.size()==1 and selected.ap==points,"Duplicate policy changes do not create an extra policy")
 command.sequence=2;command.edit=account.edit;command.args={"scope":"cell","kind":"grazer"}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(2).is_empty()),"Body override has a sequenced receipt")
 check(result(2).ok and host.world.investment.cells[selected.id]=="grazer","Body override targets the signed-in selected body")
 command.sequence=3;command.edit=account.edit;command.cell=selected.id+1000;command.args={"scope":"lineage","kind":"hunter"}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(3).is_empty()),"Forged target gets an explicit rejection")
 check(not result(3).ok and host.world.investment.lineages[account.root]=="producer","A client cannot change another body's investment")
 host.world.managed_lineages=host.accounts.values().map(func(a):return a.root);host.world.managed_cells=[selected.id]
 check(host.world.Investment.candidate(host.world,selected).is_empty(),"Connected selected body stays manual under family/body strategy")
 host.world.managed_cells=[]
 check(host.world.Investment.candidate(host.world,selected).kind=="cilia","The same body uses its strategy when no longer controlled")
 var peer: Dictionary=host.peers.values().filter(func(p):return p.account==welcome.token.sha256_text())[0]
 peer.view=Vector4(selected.position.x,selected.position.y,500,500);peer.perception="exteroception"
 var frame: Dictionary=host._frame(peer)
 var visible=Codec.new().restore(frame.graph)
 check(visible.investment.lineages.size()==1 and visible.investment.npc.is_empty(),"Policy snapshot does not reveal another family's settings")
 check(visible.player.ap==selected.ap and visible.evolution.points==selected.ap and account.evolution.points==0,"Legacy point fields remain zero")

 # Portraits include the owner's off-camera family, without widening live camera models.
 var relative=Sim.Cell.clone_state(selected);relative.id=host.world.next_id;host.world.next_id+=1
 relative.lineage=account.root;relative.position=Sim.Medium.wrap_position(selected.position+Vector2(1700,900))
 relative.previous_position=relative.position;relative.add_organ("photosynthesis",1,"graze",false)
 host.world.cells.append(relative);account.lineage.register(relative,selected.id,selected.generation+1,"living",host.world.time)
 var foreign=Sim.Cell.new(host.world.next_id);host.world.next_id+=1;host.world.cells.append(foreign)
 var random: int=host.world.rng.state;var tissue: float=relative.organic_mass()
 frame=host._frame(peer);visible=Codec.new().restore(frame.graph)
 check(frame.family_portraits.has(relative.id) and not visible.cells.any(func(body):return body.id==relative.id),"Owned off-camera anatomy arrives as portrait data without promoting a live world/camera model")
 check(not frame.family_portraits.has(foreign.id),"Family portraits cannot reveal an unrelated lineage's off-camera anatomy")
 check(frame.family_portraits[relative.id].organs.any(func(organ):return organ.kind=="photosynthesis"),"A family picture carries its actual installed organs")
 frame.protocol=Protocol.VERSION
 var decoded: Dictionary=Protocol.unpack(Protocol.pack(frame))
 check(decoded.family_portraits[relative.id].outline==relative.membrane.outline(),"Real compressed network framing retains portrait geometry and integer identity")
 check(host.world.rng.state==random and is_equal_approx(relative.organic_mass(),tissue),"Capturing remote portraits is read-only with respect to biology and ecology RNG")
 var earlier: Dictionary=frame.family_portraits[relative.id]
 relative.organs[-1].hp*=.5;relative.render_revision+=1
 var latest: Dictionary=host._frame(peer).family_portraits[relative.id]
 check(earlier.organs[-1].hp==1 and latest.organs[-1].hp==.5,"Snapshots refresh damage while earlier queued portrait data stays immutable")
 relative.dead=true;relative.health=0;account.lineage.died(relative,host.world)
 check(not host._frame(peer).family_portraits.has(relative.id),"Dead relatives leave the next remote portrait snapshot")
 socket.send_text(JSON.stringify({"op":"lineage_color","color":"#32d4a7"}))
 check(await until(func():return messages.any(func(m):return m.get("kind","")=="lineage_color_result")),"Color save gets a real authenticated receipt")
 var receipt: Dictionary=messages.filter(func(m):return m.get("kind","")=="lineage_color_result")[-1]
 check(receipt.ok and host.accounts[welcome.token.sha256_text()].lineage_color=="#32d4a7","Chosen lineage color belongs to the signed-in account")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.accounts[welcome.token.sha256_text()].lineage_color=="#32d4a7" and saved.accounts[welcome.token.sha256_text()].current.organs==selected.organs,"Color is durable without changing saved cell anatomy")
 check(host._lineage_names().any(func(row):return row.root==account.root and row.get("color","")=="#32d4a7"),"Family color is published alongside its public lineage name")
 messages=messages.filter(func(m):return m.get("kind","")!="lineage_color_result")
 socket.send_text(JSON.stringify({"op":"lineage_color","color":"javascript:bad"}))
 check(await until(func():return messages.any(func(m):return m.get("kind","")=="lineage_color_result")),"Invalid color has an explicit rejection")
 check(not messages.filter(func(m):return m.get("kind","")=="lineage_color_result")[-1].ok and account.lineage_color=="#32d4a7","Untrusted strings cannot replace a validated color")
 # One authoritative paid-tissue refund with a durable, idempotent receipt.
 selected.biomass=100
 for kind in ["photosynthesis","propulsion","mitochondrion"]:
  check(host.world._install_for(selected,account.evolution,kind,1),"Ordinary biomass construction succeeds")
 var sold: Dictionary=selected.organs[-1]
 var refund: float=selected.construction_refund(sold)
 check(refund==sold.paid_material*.5 and refund>0,"Paid tissue refunds half its actual payment")
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":4,"action":"remove","args":{"id":sold.id}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(4).is_empty()),"Reabsorption gets a durable receipt")
 check(result(4).ok and is_equal_approx(result(4).get("biomass_refund",-1),refund) and selected.organ_by_id(sold.id).is_empty(),"Receipt reports the finite biomass refund")
 var remaining: int=selected.organs.size()
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==4).size()==2),"Retry returns the original receipt")
 check(selected.organs.size()==remaining and selected.ap==0,"Retry never reabsorbs another organ or creates AP")
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":5,"action":"division_policy","args":{"mode":"budding","automatic":false}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(5).is_empty()),"Independent budding policy has a receipt")
 check(result(5).ok and not selected.automatic_budding,"Automatic modes can be chosen separately")
 # Division readiness is captured by authority even when the camera misses relatives.
 host.world.habitat_geometry.enabled=false
 selected.biomass=200;selected.energy=100;selected.reproduction_retry_at=0
 for i in 3:
  var extra=Sim.Cell.new(host.world.next_id,Vector2(-1500+i*500,-1000));host.world.next_id+=1
  extra.lineage=account.root;extra.add_organ("feeding",0,"graze",false);host.world.cells.append(extra)
  account.lineage.register(extra,selected.id,1,"living",host.world.time)
 frame=host._frame(peer)
 check(frame.division.mitosis.cell==selected.id and frame.division.mitosis.ready and frame.division.mitosis.progress==1,"Authoritative snapshot reports funded readiness with four living relatives")
 var births: int=account.lineage.births;points=selected.ap
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":6,"action":"divide","args":{}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(6).is_empty()),"Paid division returns an authenticated receipt")
 check(result(6).ok and result(6).message.contains("Cell divided") and account.lineage.births==births+1 and selected.ap==0 and host.world.cells[-1].ap==0,"A fifth relative is born with a real receipt and no AP economy")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.accounts[welcome.token.sha256_text()].lineage.births==births+1,"Division and its receipt are durable before success")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==6).size()==2),"Retried division returns its original receipt")
 check(account.lineage.births==births+1 and selected.ap==0 and host.world.cells[-1].ap==0,"Retry cannot duplicate a daughter")
 command.sequence=7;command.edit=account.edit
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(7).is_empty()),"An unfunded second division returns a clear rejection")
 check(not result(7).ok and result(7).message.contains("Resting"),"Rejected division explains actual missing funding")
 # New family settings and fusion use the same authenticated, durable command path.
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":8,"action":"division_policy","args":{"scope":"lineage","automatic":true}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(8).is_empty()),"Family division setting receives a sequenced receipt")
 check(result(8).ok and host.world.cells.filter(func(body):return body.lineage_id()==account.root).all(func(body):return body.automatic_division),"Family automatic division changes only its own current relatives")
 var donor=host.world.cells.filter(func(body):return not body.dead and body.lineage_id()==account.root and body!=selected)[-1]
 for body in host.world.cells:
  if body!=selected and body!=donor:body.position=Vector2(2600+body.id*10,2200);body.previous_position=body.position
 # Emit a real tracer within receptor reach in every backend. Pool metadata
 # patches intentionally do not teleport authoritative numeric particle poses.
 donor.position=selected.organ_position(selected.organs.filter(func(o):return o.kind=="feeding")[0]);donor.previous_position=donor.position
 var family_trace: Dictionary=host.world._emit_pheromone(donor)
 family_trace.expires_at=host.world.time+8
 host.world._commit_spawn_metadata()
 if host.cpu:
  host.world.grid.rebuild(host.world.particles);selected.behavior["family_cues"]=host.world._family_reports(selected)
 check(await until(func():return Sim.FamilyMerging.detected(host.world,selected,donor.id)),"The receiver detects a real emitted family tracer through its active chemistry backend")
 # Selection must commit while the sensed donor is still physically separated.
 donor.position=selected.position+Vector2(450,200);donor.previous_position=donor.position
 check(not Sim.FamilyMerging.touching(host.world,selected,donor),"The network merge starts without physical contact")
 var eligibility: Dictionary=host._frame(peer).merge_available
 check(eligibility.cell==selected.id and eligibility.targets.has(donor.id),"The real socket snapshot exposes only current detected merge target identities")
 var donor_id: int=donor.id;var combined_ap: int=0
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":9,"action":"merge","args":{"id":donor.id}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(9).is_empty()),"Immediate selected fusion receives an authenticated receipt")
 if not result(9).ok:print("FUSION_REJECT ",result(9)," distance=",Sim.Medium.offset(selected.position,donor.position).length()," supports=",selected.support(0)+donor.support(PI))
 check(result(9).ok and not host.world.cells.any(func(body):return body.id==donor_id) and selected.ap==combined_ap and not selected.behavior.has("merge_order"),"Fusion is complete at the receipt with no approach order or resource duplication")
 check(result(9).message=="Family cells merged.","The authoritative receipt confirms completion rather than promising navigation")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(not saved.world.cells.any(func(body):return body.id==donor_id) and saved.accounts[welcome.token.sha256_text()].current.id==selected.id,"Fusion is durable before success and retains the receiver identity")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==9).size()==2),"Retried fusion receives its original receipt")
 check(selected.ap==combined_ap and account.lineage.births==births+1,"Retried fusion cannot duplicate births")
 check(await until(func():return messages.any(func(frame):return frame.get("merges",[]).any(func(event):return event.donor==donor_id and event.receiver==selected.id))),"The real socket delivers the consumed donor's pull-in artwork")
 check(host.world.merge_bursts.size()==1 and host.world.merge_bursts[0].donor==donor_id,"Retried authenticated merge produces one presentation fact and no revived donor")
 # Retired banking/queue commands cannot arm a later surprise birth.
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":10,"action":"division_request","args":{"active":true}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(10).is_empty()),"Obsolete queue command receives a rejection")
 check(not result(10).ok and not selected.division_requested,"Retired queue never changes reproduction")
 command.sequence=11;command.edit=account.edit;command.cell=selected.id+10000;command.action="reproduce";command.args={"mode":"budding"}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(11).is_empty()),"Forged reproduction target is rejected")
 check(not result(11).ok,"Reproduction cannot target another body")
 var unseen=Sim.Cell.new(host.world.next_id,Sim.Medium.wrap_position(selected.position+Vector2(1600,900)));host.world.next_id+=1
 unseen.lineage=account.root;host.world.cells.append(unseen);account.lineage.register(unseen,selected.id,1,"living",host.world.time)
 points=selected.ap
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":12,"action":"merge","args":{"id":unseen.id,"detected":true}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(12).is_empty()),"An undetected family target receives an authenticated rejection")
 check(not result(12).ok and result(12).message.contains("pheromones") and selected.ap==points and host.world.cells.has(unseen),"A forged client detection claim cannot authorize merging or spend resources")
 check(not host._frame(peer).merge_available.targets.has(unseen.id),"Off-camera family portraits do not become merge selection permission")
 socket.close();host.running=false;host.listener.stop();host._finish_snapshots()
 if host.world.resident!=null:
  host.world.resident.gpu.close();await host.world.resident.gpu.closed
 host.queue_free();await process_frame
 print("LIFECYCLE NETWORK: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
