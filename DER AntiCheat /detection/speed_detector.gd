class_name DERSpeedDetector
extends RefCounted

var last_time = 0
var time_list = []

func check() -> float:
	if Engine.is_editor_hint():
		return 0.0
	
	var now = Time.get_ticks_usec()
	
	if last_time == null:
		last_time = 0
	
	var delta = now - last_time
	
	if last_time > 0:
		if time_list == null:
			time_list = []
		
		time_list.append(delta)
		if time_list.size() > 10:
			time_list.pop_front()
		
		var total = 0.0
		var count = 0
		for t in time_list:
			total += t
			count += 1
		
		var avg = 0.0
		if count > 0:
			avg = total / count
		
		if avg > 0 and delta < avg * 0.8:
			return 0.8
	
	last_time = now
	return 0.0
