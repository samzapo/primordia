extends SceneTree
const Regions=preload("res://scripts/particle_regions.gd")
func _initialize() -> void:
	for total in [1000,10000,100000]:
		var store=Regions.new()
		for i in total: store.put({"alive":true,"p":Vector2(i*512,0),"amount":.3},0)
		var start:=Time.get_ticks_usec()
		var updates:=0
		for tick in 2000:
			var packets: Array=store.take_due(1+tick*.001,256,8)
			updates+=packets.size()
			store.put_all(packets,1+tick*.001)
			store.keys_in(Vector2.ZERO,Vector2(1200,900))
		print("COLD_STORE_SCALING ",JSON.stringify({"stored_packets":total,"mean_service_us":(Time.get_ticks_usec()-start)/2000.,"updates":updates,"scheduler_entries":store.due.size()}))
	quit()
