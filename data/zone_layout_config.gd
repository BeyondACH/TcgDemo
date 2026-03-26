extends Resource
class_name ZoneLayoutConfig

# Background image dimensions
const BG_IMAGE_WIDTH := 1008.0
const BG_IMAGE_HEIGHT := 1024.0

# Zone layout ratios (relative to background image)
# Opponent zones (top half of the board)
const OPPONENT_ZONES := {
	life_area = {"left": 0.794, "top": 0.197, "width": 0.157, "height": 0.305},
	remove_area = {"left": 0.760, "top": 0.000, "width": 0.238, "height": 0.334},
	front_line = {"left": 0.264, "top": 0.322, "width": 0.488, "height": 0.166},
	energy_line = {"left": 0.264, "top": 0.195, "width": 0.488, "height": 0.126},
	deck = {"left": 0.043, "top": 0.312, "width": 0.121, "height": 0.159},
	outside_area = {"left": 0.000, "top": 0.000, "width": 0.244, "height": 0.336},
}

# Player zones (bottom half of the board)
const PLAYER_ZONES := {
	life_area = {"left": 0.035, "top": 0.513, "width": 0.175, "height": 0.270},
	remove_area = {"left": 0.000, "top": 0.666, "width": 0.240, "height": 0.334},
	front_line = {"left": 0.248, "top": 0.512, "width": 0.488, "height": 0.166},
	energy_line = {"left": 0.248, "top": 0.679, "width": 0.488, "height": 0.126},
	deck = {"left": 0.812, "top": 0.517, "width": 0.126, "height": 0.151},
	outside_area = {"left": 0.780, "top": 0.670, "width": 0.220, "height": 0.330},
}


## Calculate background display parameters for letterboxing
## Returns: {scale_factor: float, display_width: float, display_height: float, letterbox_offset: float, top_offset: float}
static func calculate_bg_transform(viewport_width: float, viewport_height: float, top_offset: float = 0.0) -> Dictionary:
	var scale_factor := viewport_height / BG_IMAGE_HEIGHT
	var display_width := BG_IMAGE_WIDTH * scale_factor
	var display_height := BG_IMAGE_HEIGHT * scale_factor
	var letterbox_offset := (viewport_width - display_width) / 2.0
	return {
		scale_factor = scale_factor,
		display_width = display_width,
		display_height = display_height,
		letterbox_offset = letterbox_offset,
		top_offset = top_offset,
	}


## Convert zone ratios to absolute pixel rect
## zone_data: {"left": float, "top": float, "width": float, "height": float}
## bg_offset: letterbox offset X
## bg_scale: scale factor
## bg_top_offset: background display rect top offset
static func zone_to_rect(zone_data: Dictionary, bg_offset: float, bg_scale: float, bg_top_offset: float = 0.0) -> Rect2:
	var left: float = zone_data.get("left", 0.0)
	var top: float = zone_data.get("top", 0.0)
	var width: float = zone_data.get("width", 0.0)
	var height: float = zone_data.get("height", 0.0)

	var x := bg_offset + left * BG_IMAGE_WIDTH * bg_scale
	var y := bg_top_offset + top * BG_IMAGE_HEIGHT * bg_scale
	var w := width * BG_IMAGE_WIDTH * bg_scale
	var h := height * BG_IMAGE_HEIGHT * bg_scale

	return Rect2(x, y, w, h)


## Get zone rect for a player
## player_id: "P1" or "P2"
## zone_name: "life_area", "front_line", etc.
static func get_zone_rect(player_id: String, zone_name: String, bg_offset: float, bg_scale: float, bg_top_offset: float = 0.0) -> Rect2:
	var zones: Dictionary
	if player_id == "P1":
		zones = PLAYER_ZONES
	else:
		zones = OPPONENT_ZONES

	var zone_data: Dictionary = zones.get(zone_name, {})
	if zone_data.is_empty():
		return Rect2(0, 0, 100, 100)

	return zone_to_rect(zone_data, bg_offset, bg_scale, bg_top_offset)


## Calculate card size to fit within a zone
## zone_rect: Rect2 of the zone
## max_cards: maximum number of cards to display
## Returns: Vector2 card size
static func calculate_card_size_for_zone(zone_rect: Rect2, max_cards: int = 4) -> Vector2:
	# Card aspect ratio (width:height) approximately 5:7
	var aspect_ratio := 5.0 / 7.0

	# Calculate max card height based on zone height
	var max_height := zone_rect.size.y * 0.9
	var max_width := zone_rect.size.x / (max_cards + 0.5)  # spacing between cards

	# Constrain by aspect ratio
	var card_height := minf(max_height, max_width / aspect_ratio)
	var card_width := card_height * aspect_ratio

	# Ensure minimum readable size
	card_width = maxf(card_width, 60.0)
	card_height = maxf(card_height, 84.0)

	return Vector2(card_width, card_height)
