class_name Throw
extends RefCounted
## Ballistic snow throws: landing point against the snow heightfield, buildings, roofs and truck beds.
## A bank taller than the arc stops the throw on its near face — banks really limit basic shovels.

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
	for i in range(160):
		var np := p + vel * dt
		vel.y -= G * dt
		t += dt
		if space:
			var q := PhysicsRayQueryParameters3D.create(p, np, MASK)
			q.collide_with_areas = true
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var col: Object = hit["collider"]
				var hp: Vector3 = hit["position"]
				if col.has_meta("roof_snow"):
					return {"pos": hp, "valid": true, "kind": "roof", "roof": col.get_meta("roof_snow"), "time": t, "v0": v0}
				if col.has_meta("dump_bed"):
					return {"pos": hp, "valid": true, "kind": "bed", "bed": col.get_meta("dump_bed"), "time": t, "v0": v0}
				if col is Area3D:
					pass
				else:
					# Hit a wall / tree / vehicle: the snow drops at its base.
					var gp := Vector3(hp.x, Snow.surface_height(hp.x, hp.z), hp.z)
					return {"pos": gp, "valid": not Snow.is_road(hp.x, hp.z), "kind": "ground", "time": t, "v0": v0}
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
			return {"pos": lp, "valid": Snow.in_map(b.x, b.z) and not Snow.is_road(b.x, b.z), "kind": "ground", "time": t, "v0": v0}
		p = np
	return {"pos": p, "valid": false, "kind": "ground", "time": t, "v0": v0}


## Position along the arc at time t (for projectile visuals).
static func arc_point(start: Vector3, dir2: Vector2, v0: float, angle_deg: float, t: float) -> Vector3:
	var th := deg_to_rad(angle_deg)
	var dir := Vector3(dir2.x, 0, dir2.y).normalized()
	return start + dir * cos(th) * v0 * t + Vector3.UP * (sin(th) * v0 * t - 0.5 * G * t * t)
