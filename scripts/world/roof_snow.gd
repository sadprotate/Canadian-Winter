class_name RoofSnow
extends MeshInstance3D
## Simplified roof snow layer: soft pillows over each roof plane whose thickness follows the
## shared roof depth (snowfall) plus snow the player threw onto this roof.

var planes: Array = []
var house_index := -1
var _shown := -1.0


func setup(p: Array, idx: int) -> void:
	planes = p
	house_index = idx
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	refresh(true)


func refresh(force := false) -> void:
	var d := Snow.roof_total(house_index)
	if not force and absf(d - _shown) < 0.025:
		return
	_shown = d
	var kit := MeshKit.new()
	build(kit, planes, d)
	mesh = kit.commit() if not kit.is_empty() else null


## The pillows for roof depth `d` over `p` (the planes setup() takes), added to `kit`.
static func build(kit: MeshKit, p: Array, d: float) -> void:
	var mat := Mats.snow_soft()
	for pl in p:
		var a: Vector3 = pl[0]
		var b: Vector3 = pl[1]
		var c: Vector3 = pl[2]
		var dd: Vector3 = pl[3]
		var ex := (b - a)
		var sx := ex.length()
		var x_axis := ex / maxf(sx, 0.001)
		var slope := (dd - a)
		var n := x_axis.cross(slope).normalized()
		if n.y < 0.0:
			n = -n
		var z_axis := x_axis.cross(n).normalized()
		var sz := absf(slope.dot(z_axis))
		var center := (a + b + c + dd) * 0.25 + n * 0.02
		var xf := Transform3D(Basis(x_axis, n, z_axis), center)
		# A small plane (porch gable, dormer) can't carry a metre-deep pillow: deep roof snow is
		# drawn no thicker than about a third of the plane's slope length.
		var dv := minf(d, 0.15 + 0.3 * minf(sz, sx))
		var droop := minf(0.12 + dv * 0.25, 0.35)
		var w := sx + 0.1
		if pl.size() > 4:
			# This edge (pl[4]: 0 = the a end, 1 = the b end) meets a house wall: the pillow ends at
			# the wall instead of reaching through it into the rooms behind (pass 5 §3).
			var ov := 0.05 + droop * 0.5 + 0.02
			w -= ov
			xf.origin += x_axis * (ov * 0.5 * (1.0 if int(pl[4]) == 0 else -1.0))
		kit.pillow(mat, xf, w, sz + 0.25, dv, droop, 10, 2.6)
