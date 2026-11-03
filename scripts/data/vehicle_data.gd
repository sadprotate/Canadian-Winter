class_name VehicleData
extends Resource
## Data definition for a drivable vehicle. One shared controller (vehicle.gd) reads these values.

enum Kind { PICKUP, PICKUP_PLOW, ATV, TRACTOR_BLADE, TRACTOR_BLOWER, GRADER, PLOW_TRUCK, ROTARY, DUMP_TRUCK }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.PICKUP
@export var price: int = 0
@export_multiline var description: String = ""
@export var max_speed: float = 14.0          # m/s on clear road
@export var reverse_speed: float = 5.0
@export var acceleration: float = 5.0
@export var brake: float = 12.0
@export var turn_rate: float = 1.4           # rad/s at full steer at moderate speed
@export var wheelbase: float = 3.3
@export var length: float = 5.4
@export var width: float = 2.0
@export var height: float = 1.9
## Snow depth (m) under the wheels at which the vehicle gets stuck.
@export var clearance: float = 0.32
## 0..1 how well the vehicle keeps grip and speed in snow.
@export var traction: float = 0.6
@export var heated_cabin: bool = true
@export var has_plow: bool = false
@export var blade_width: float = 2.4
@export var blade_capacity: float = 3.0      # m3 of berm before stalling
@export var blade_angle_adjustable: bool = true
@export var blade_max_angle_deg: float = 30.0
@export var blade_floor: float = 0.015
@export var has_blower: bool = false
@export var blower_width: float = 1.8
@export var blower_rate: float = 0.6         # m3/s
@export var blower_throw: float = 14.0
@export var dump_capacity: float = 0.0       # m3 (dump truck bed)
@export var body_color: Color = Color(0.42, 0.44, 0.47)
@export var accent_color: Color = Color(0.15, 0.15, 0.16)
@export var engine_sound: StringName = &"engine_truck"
@export var engine_pitch: float = 1.0
