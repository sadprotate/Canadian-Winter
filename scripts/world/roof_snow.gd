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
	var mat := Mats.snow_soft()
	for pl in planes:
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
		kit.pillow(mat, xf, sx + 0.1, sz + 0.25, dv, minf(0.12 + dv * 0.25, 0.35), 10, 2.6)
	mesh = kit.commit() if not kit.is_empty() else null
