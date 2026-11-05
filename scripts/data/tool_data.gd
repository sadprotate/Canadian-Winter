class_name ToolData
extends Resource
## Data definition for a hand tool or walk-behind machine. Edit the .tres files in res://data/tools/.
##
## Shovel-type tools (hands, shovels, pushers, scrapers, sleigh) all share one control scheme:
## hold the primary action and sweep the aim point through the snow to fill the load, release to
## throw it, hold the secondary action to push snow ahead. Their profile is defined by
## capacity / fill_rate / bite (scooping), throw_distance (throwing) and push_width /
## push_strength (pushing). Upgrades scale these values (see ToolController).

enum Kind { HANDS, SHOVEL, PUSHER, SCRAPER, SLEIGH, ELECTRIC_SHOVEL, WALK_BLOWER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.SHOVEL
@export var tier: int = 0
@export var price: int = 0
@export_multiline var description: String = ""
## Width of the scoop / blade edge that cuts through the snow when filling (m).
@export var width: float = 0.4
## Footprint length used for intakes and for digging in place without sweeping (m).
@export var reach: float = 0.45
## Load capacity (m3): how much snow the hands / blade / sleigh tub can carry.
@export var capacity: float = 0.03
## Maximum fill speed while sweeping through deep snow (m3 per second).
@export var fill_rate: float = 0.05
## How deep one pass of the scoop cuts into the snow (m). Deep snow fills a load in a short
## sweep; thin snow needs a long sweep; bare pavement fills nothing.
@export var bite: float = 0.15
## Furthest the scooping aim point can be from the player, measured on the ground (m).
@export var sweep_reach: float = 1.5
## Seconds per scoop when digging in place (aim point not moving).
@export var cycle_time: float = 0.5
## Maximum throw distance (m). Blowers throw automatically through the chute.
@export var throw_distance: float = 3.0
## Residual depth (m) left behind by a blade or scoop.
@export var scrape_floor: float = 0.01
## Continuous intake rate (m3/s) for electric shovels and blowers.
@export var rate: float = 0.0
## Width of the pushing edge (m) when pushing with the secondary action.
@export var push_width: float = 0.4
## Push strength (m3): the berm size the tool can drive ahead before it slows to half speed.
@export var push_strength: float = 0.1
## Walking speed multiplier while the tool is engaged.
@export var engaged_speed_mult: float = 0.85
@export var angle_adjustable: bool = false
@export var max_angle_deg: float = 30.0
## Throw launch angle in degrees.
@export var throw_angle_deg: float = 42.0
@export var primary_color: Color = Color(0.95, 0.5, 0.1)
@export var secondary_color: Color = Color(0.7, 0.72, 0.75)
## False for walk-behind machines (they do not use a tool slot).
@export var uses_slot: bool = true
@export var particle_amount: int = 12
@export var loop_sound: StringName = &""
@export var action_sound: StringName = &""


## Hands and every shovel-type tool use the hold-to-fill / release-to-throw / push scheme.
func is_shovel_type() -> bool:
	return kind == Kind.HANDS or kind == Kind.SHOVEL or kind == Kind.PUSHER or kind == Kind.SCRAPER or kind == Kind.SLEIGH


## Polish 6 §3: the store's text for this tool — the description with the blade width read from
## this profile ({width}: "1.0 m") and the bound keys ({tool_angle} …, Settings.with_keys).
func store_description() -> String:
	var w := "%.1f m" % width if is_equal_approx(snappedf(width, 0.1), width) else "%.2f m" % width
	return Settings.with_keys(description.replace("{width}", w))
