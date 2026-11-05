class_name Throw
extends RefCounted
## Ballistic snow throws: landing point against the snow heightfield, buildings, roofs and truck beds.
## A bank taller than the arc stops the throw on its near face — banks really limit basic shovels.
##
## Polish 5 §3: snow that would enter a building (a wall, a window, an open door or a roof: any
## volume in Buildings) stops at the building's outer face and falls at the foot of that wall,
## outside — the landing is there, so the indicator shows it and the volume lands in the snow.
## The road rule is gone (Decision 12): a landing on the street is like any other.

const G := 9.8
const MASK := 1 | (1 << 6) | (1 << 7)   # world, roof catchers, dump-truck beds


static func compute(world: World3D, start: Vector3, dir2: Vector2, dist: float, angle_deg: float, exclude: Array = []) -> Dictionary:
	dist = maxf(dist, 0.3)
	var th := deg_to_rad(angle_deg)
	var v0 := sqrt(dist * G / maxf(sin(2.0 * th), 0.2))
	var dir := Vector3(dir2.x, 0, dir2.y).normalized()
	var vel := dir * cos(th) * v0 + Vector3.UP * sin(th) * v0
	var p := start
	var t := 0.0
	var dt := 0.035
	var space := world.direct_space_state if world else null
	# The buildings near the throw's path (it can't fly further than it takes to fall a metre below
	# the ground from its start).
	var vy := sin(th) * v0
	var t_fall := (vy + sqrt(vy * vy + 2.0 * G * maxf(start.y + 1.0, 0.0))) / G
	var s2 := Vector2(start.x, start.z)
	var d2n := Vector2(dir.x, dir.z)
	var blds := Buildings.along(s2, s2 + d2n * (cos(th) * v0 * t_fall + 0.5), Buildings.SKIN + 0.5)
	for i in range(160):
		var np := p + vel * dt
		vel.y -= G * dt
		t += dt
		var be := Buildings.entry(p, np, blds) if not blds.is_empty() else {}
		if space:
			var q := PhysicsRayQueryParameters3D.create(p, np, MASK)
			q.collide_with_areas = true
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var col: Object = hit["collider"]
				var hp: Vector3 = hit["position"]
				var ht := p.distance_to(hp) / maxf(p.distance_to(np), 1e-6)
				if not be.is_empty() and float(be["t"]) <= ht:
					return _at_building(be["b"], start, dir2, v0, angle_deg)
				if col.has_meta("roof_snow"):
					# A roof: the snow stops at the building's face and falls (it used to join the
					# roof's own snow layer, which isn't part of the snow on the ground).
					var rb := _building_of(Vector2(hp.x, hp.z))
					if not rb.is_empty():
						return _at_building(rb, start, dir2, v0, angle_deg)
					return {"pos": hp, "valid": true, "kind": "roof", "roof": col.get_meta("roof_snow"), "time": t, "v0": v0}
				if col.has_meta("dump_bed"):
					return {"pos": hp, "valid": true, "kind": "bed", "bed": col.get_meta("dump_bed"), "time": t, "v0": v0}
				if col is Area3D:
					pass
				else:
					# A building's wall (or anything within its walls' skin): stopped at its face.
					var wb := Buildings.at(Vector2(hp.x, hp.z), Buildings.SKIN)
					if not wb.is_empty() and hp.y < float(wb["top"]) + 0.5:
						return _at_building(wb, start, dir2, v0, angle_deg)
					# Hit a tree / vehicle / fence: the snow drops at its base.
					var gp := Vector3(hp.x, Snow.surface_height(hp.x, hp.z), hp.z)
					return {"pos": gp, "valid": true, "kind": "ground", "time": t, "v0": v0}
		if not be.is_empty():
			return _at_building(be["b"], start, dir2, v0, angle_deg)
		var h := Snow.surface_height(np.x, np.z)
		if np.y <= h or not Snow.in_map(np.x, np.z):
			# Refine against the surface.
			var a := p
			var b := np
			for k in range(5):
				var m := (a + b) * 0.5
				if m.y <= Snow.surface_height(m.x, m.z):
					b = m
				else:
					a = m
			var lp := Vector3(b.x, Snow.surface_height(b.x, b.z), b.z)
			return {"pos": lp, "valid": Snow.in_map(b.x, b.z), "kind": "ground", "time": t, "v0": v0}
		p = np
	return {"pos": p, "valid": false, "kind": "ground", "time": t, "v0": v0}


## The building a roof catcher hit belongs to (the nearest footprint to the hit point).
static func _building_of(p: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for b in Buildings.near(p, 1.0):
		var r: Rect2 = b["rect"]
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = b
	return best


## Polish 5 §3: a throw that would enter building `bl` stops where its path meets the building's
## outer face (on the arc, at whatever height it is there) and falls straight down the wall to the
## snow at its foot, outside. The landing ("pos") is that foot; "stop" / "stop_time" let the clump
## show the stop and the fall.
static func _at_building(bl: Dictionary, start: Vector3, dir2: Vector2, v0: float, angle_deg: float) -> Dictionary:
	var th := deg_to_rad(angle_deg)
	var f := Buildings.foot(bl, Vector2(start.x, start.z), dir2)
	var ft: Vector2 = f["foot"]
	var gy := Snow.surface_height(ft.x, ft.y)
	var ts := float(f["s"]) / maxf(v0 * cos(th), 0.01)
	var stop := arc_point(start, dir2, v0, angle_deg, ts)
	var face: Vector2 = f["face"]
	stop = Vector3(face.x, maxf(stop.y, gy), face.y)
	var fall := sqrt(2.0 * maxf(stop.y - gy, 0.0) / G)
	return {"pos": Vector3(ft.x, gy, ft.y), "valid": Snow.in_map(ft.x, ft.y), "kind": "ground", "time": ts + fall, "v0": v0,
		"stop": stop, "stop_time": ts, "building": bl["id"]}


## Position along the arc at time t (for projectile visuals).
static func arc_point(start: Vector3, dir2: Vector2, v0: float, angle_deg: float, t: float) -> Vector3:
	var th := deg_to_rad(angle_deg)
	var dir := Vector3(dir2.x, 0, dir2.y).normalized()
	return start + dir * cos(th) * v0 * t + Vector3.UP * (sin(th) * v0 * t - 0.5 * G * t * t)
