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
 socket.send_text(JSON.stringify({"op":"hello","invite":OS.get_environment("PRIMORDIA_INVITE"),"snapshot_ack":true}))
 check(await until(func():return messages.any(func(m):return m.get("kind","")=="welcome")),"Fixture account signs in")
 var welcome: Dictionary=messages.filter(func(m):return m.get("kind","")=="welcome")[0]
 var account: Dictionary=host.accounts[welcome.token.sha256_text()]
 var selected=host._selected(account)
 var points: int=account.evolution.points
 var command: Dictionary={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":1,"action":"investment","args":{"scope":"lineage","kind":"producer"}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(1).is_empty()),"Investment command returns a durable receipt")
 check(result(1).ok and account.evolution.points==points and host.world.investment.lineages[account.root]=="producer","Changing strategy is free and scoped to the authenticated family")
 var saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.world.investment.lineages[account.root]=="producer","Successful policy edit is already in the checkpoint")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==1).size()==2),"Retried policy command returns its original receipt")
 check(host.world.investment.lineages.size()==1 and account.evolution.points==points,"Duplicate policy changes cannot spend or grant AP")
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
 # The authenticated sale returns only the recorded paid cost minus one.
 account.evolution.points=20
 for kind in ["cilia","photosynthesis","mitochondrion"]:
  check(host.world._install_for(selected,account.evolution,kind,1),"Refund fixture builds through the actual AP-funded installation path")
 var sold: Dictionary=selected.organs[-1]
 var refund: int=selected.construction_refund(sold)
 check(sold.construction_ap>=2 and refund==sold.construction_ap-1,"The organ records its actual progressive purchase price")
 var before_refund: int=account.evolution.points
 command={"op":"command","epoch":host.epoch,"cell":selected.id,"edit":account.edit,"sequence":4,"action":"remove","args":{"id":sold.id}}
 socket.send_text(JSON.stringify(command))
 check(await until(func():return not result(4).is_empty()),"Sale receives an authenticated durable receipt")
 check(result(4).ok and selected.organ_by_id(sold.id).is_empty() and account.evolution.points==before_refund+refund,"Sale returns paid AP minus one exactly once")
 socket.send_text(JSON.stringify(command))
 check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==4).size()==2),"A repeated sale returns its original receipt")
 check(account.evolution.points==before_refund+refund,"Retrying a sale cannot duplicate its AP refund")
 saved=Codec.new().restore(host.store.load_latest().graph)
 check(saved.accounts[welcome.token.sha256_text()].evolution.points==account.evolution.points,"Sale AP refund is already in the saved account")
 socket.close();host.running=false;host.listener.stop();host._finish_snapshots()
 if host.world.resident!=null:
  host.world.resident.gpu.close();await host.world.resident.gpu.closed
 host.queue_free();await process_frame
 print("FEEDBACK PASS NETWORK: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
