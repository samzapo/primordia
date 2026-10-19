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
 check(host.world.investment.lineages.size()==1 and selected.ap==points,"Duplicate policy changes cannot spend or grant AP")
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
 check(visible.player.ap==selected.ap and visible.evolution.points==selected.ap and account.evolution.points==0,"New and already-open older clients see the selected cell's AP without mutating a shared pool")

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
 # The authenticated sale reverses the current build tier exactly once.
 selected.ap=20
 for kind in ["cilia","photosynthesis","mitochondrion","regenerative"]:
  check(host.world._install_for(selected,account.evolution,kind,1),"Refund fixture builds through the actual AP-funded installation path")
 var sold: Dictionary=selected.organs[-1]
 var refund: int=selected.construction_refund(sold)
 check(sold.construction_ap>=2 and refund==selected.construction_price()-1,"Recycling uses the current tier, not the individual organ price")
 var before_refund: int=selected.ap
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":4,"action":"remove","args":{"id":sold.id}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(4).is_empty()),"Sale receives an authenticated durable receipt")
 check(result(4).get("ap_refund",-1)==refund and result(4).message.contains("%d AP returned" % refund),"The durable receipt reports the actual AP returned")
 check(result(4).ok and selected.organ_by_id(sold.id).is_empty() and selected.ap==before_refund+refund,"Sale returns the current build tier exactly once")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==4).size()==2),"A repeated sale returns its original receipt")
 check(selected.ap==before_refund+refund,"Retrying a sale cannot duplicate its AP refund")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.accounts[welcome.token.sha256_text()].current.ap==selected.ap,"Sale AP refund is already in the saved account")
 # The fourth and third added organs must return3+2 to the same body.
 var relative_ap: int=relative.ap
 check(refund==3,"Four installed added organs have a three-AP return tier")
 sold=selected.organs[-1]
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":5,"action":"remove","args":{"id":sold.id}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(5).is_empty()),"Second successive reabsorption receives a durable receipt")
 check(result(5).ok and result(5).ap_refund==2 and selected.ap==before_refund+5,"Real authenticated successive removals return exactly3+2AP")
 check(relative.ap==relative_ap,"Neither refund changes another relative's balance")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==5).size()==2),"Second reabsorption retries return the original receipt")
 check(selected.ap==before_refund+5,"Retry cannot duplicate the second refund")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.accounts[welcome.token.sha256_text()].current.ap==before_refund+5,"Both refunds are saved before success")
 # Division readiness is captured by authority even when the camera misses relatives.
 host.world.habitat_geometry.enabled=false
 selected.brood_mass=host.world.offspring_quote(selected).material;selected.brood_energy=60;selected.biomass=200;selected.energy=100
 for i in 3:
  var extra=Sim.Cell.new(host.world.next_id,Vector2(-1500+i*500,-1000));host.world.next_id+=1
  extra.lineage=account.root;extra.add_organ("feeding",0,"graze",false);host.world.cells.append(extra)
  account.lineage.register(extra,selected.id,1,"living",host.world.time)
 frame=host._frame(peer)
 check(frame.division.cell==selected.id and frame.division.ready and frame.division.progress==1,"Authoritative snapshot reports funded readiness with four living relatives")
 var births: int=account.lineage.births;points=selected.ap
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":6,"action":"divide","args":{}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(6).is_empty()),"Paid division returns an authenticated receipt")
 check(result(6).ok and result(6).message.contains("Cell divided") and account.lineage.births==births+1 and selected.ap==points+1 and host.world.cells[-1].ap==1,"A fifth relative is born with a real receipt and one AP per parent/daughter")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.accounts[welcome.token.sha256_text()].lineage.births==births+1,"Division and its receipt are durable before success")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==6).size()==2),"Retried division returns its original receipt")
 check(account.lineage.births==births+1 and selected.ap==points+1 and host.world.cells[-1].ap==1,"Retry cannot duplicate a daughter or AP")
 command.sequence=7;command.edit=account.edit
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(7).is_empty()),"An unfunded second division returns a clear rejection")
 check(not result(7).ok and result(7).message.contains("still needed"),"Rejected division explains actual missing funding")
 # New family settings and fusion use the same authenticated, durable command path.
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":8,"action":"division_policy","args":{"scope":"lineage","automatic":true}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(8).is_empty()),"Family division setting receives a sequenced receipt")
 check(result(8).ok and host.world.cells.filter(func(body):return body.lineage_id()==account.root).all(func(body):return body.automatic_division),"Family automatic division changes only its own current relatives")
 var donor=host.world.cells.filter(func(body):return not body.dead and body.lineage_id()==account.root and body!=selected)[-1]
 for body in host.world.cells:
  if body!=selected and body!=donor:body.position=Vector2(2600+body.id*10,2200);body.previous_position=body.position
 donor.position=selected.position+Vector2(selected.support(0)+donor.support(PI)-5,0);donor.previous_position=donor.position
 var family_trace: Dictionary=host.world._emit_pheromone(donor)
 family_trace.p=selected.organ_position(selected.organs.filter(func(o):return o.kind=="feeding")[0]);family_trace.previous=family_trace.p
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
 var donor_id: int=donor.id;var combined_ap: int=selected.ap+donor.ap
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":9,"action":"merge","args":{"id":donor.id}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(9).is_empty()),"Immediate selected fusion receives an authenticated receipt")
 if not result(9).ok:print("FUSION_REJECT ",result(9)," distance=",Sim.Medium.offset(selected.position,donor.position).length()," supports=",selected.support(0)+donor.support(PI))
 check(result(9).ok and not host.world.cells.any(func(body):return body.id==donor_id) and selected.ap==combined_ap and not selected.behavior.has("merge_order"),"Fusion is complete at the receipt with no approach order or extra AP")
 check(result(9).message=="Family cells merged.","The authoritative receipt confirms completion rather than promising navigation")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(not saved.world.cells.any(func(body):return body.id==donor_id) and saved.accounts[welcome.token.sha256_text()].current.id==selected.id,"Fusion is durable before success and retains the receiver identity")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==9).size()==2),"Retried fusion receives its original receipt")
 check(selected.ap==combined_ap and account.lineage.births==births+1,"Retried fusion cannot duplicate AP or births")
 check(await until(func():return messages.any(func(frame):return frame.get("merges",[]).any(func(event):return event.donor==donor_id and event.receiver==selected.id))),"The real socket delivers the consumed donor's pull-in artwork")
 check(host.world.merge_bursts.size()==1 and host.world.merge_bursts[0].donor==donor_id,"Retried authenticated merge produces one presentation fact and no revived donor")
 # Single-division requests use the same authenticated, durable receipt path.
 selected.brood_mass=0;selected.brood_energy=0
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":10,"action":"division_request","args":{"active":true}}
 births=account.lineage.births;points=selected.ap
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(10).is_empty()),"Queued division has a real authenticated receipt")
 check(result(10).ok and result(10).queued and selected.division_requested and not selected.automatic_division and account.lineage.births==births,"Unfunded manual division queues instead of being rejected or enabling continuous auto")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.accounts[welcome.token.sha256_text()].current.division_requested,"The one-shot request is durable before the success receipt")
 frame=host._frame(peer)
 check(frame.division.queued and not frame.division.automatic,"Browser readiness includes the authoritative queued/automatic state")
 for body in host.world.cells:
  if body!=selected:body.automatic_division=false;body.position=Vector2(2600+body.id*10,2200)
 host.world.automatic_reproduction=true
 selected.brood_mass=host.world.offspring_quote(selected).material;selected.brood_energy=60;selected.reproduction_retry_at=0
 host.world._step_reproduction();host.world.automatic_reproduction=false
 check(account.lineage.births==births+1 and not selected.division_requested and selected.ap==points+1,"Authority consumes the queued birth once, preserving per-cell AP")
 check(not host.world.cells[-1].division_requested and not host.world.cells[-1].automatic_division,"The queued birth does not arm its daughter")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==10).size()==2),"A replay receives its retained queue receipt")
 check(not selected.division_requested and account.lineage.births==births+1,"Replaying the completed request cannot re-arm or duplicate its birth")
 command.sequence=11;command.edit=account.edit;command.cell=selected.id+10000
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(11).is_empty()),"Forged division target receives a rejection")
 check(not result(11).ok and not selected.division_requested,"A queued division cannot target another body")
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
 print("FEEDBACK PASS NETWORK: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
