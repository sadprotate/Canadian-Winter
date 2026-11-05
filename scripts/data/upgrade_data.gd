class_name UpgradeData
extends Resource
## A purchasable upgrade (tool stats, clothing, property, weather technology).

enum Category { TOOL, MACHINE, VEHICLE, CLOTHING, PROPERTY, WEATHER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.TOOL
@export var price: int = 0
@export_multiline var description: String = ""
## Stat key read by gameplay code, e.g. "shovel_capacity", "throw_distance", "cold_protection".
@export var stat: StringName = &""
## Multiplier or value applied for the stat (multipliers stack multiplicatively).
@export var value: float = 1.0
## Upgrade id that must be owned first ("" for none).
@export var requires: StringName = &""
## True if the upgrade is a physical item collected at the store (e.g. truck plow install).
@export var requires_pickup: bool = false
## Polish 5 §13 (Decision 8): an item's own upgrade level (built by ItemUpgrades, not a .tres): the
## item type it belongs to ("" for the upgrades that aren't an item's: clothing, weather, property),
## its track and its level (1 = the first).
@export var item: StringName = &""
@export var track: StringName = &""
@export var level: int = 0
