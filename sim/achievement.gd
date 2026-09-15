class_name Achievement
extends RefCounted

## Static data for one achievement and the permanent buff it grants.

var key := ""
var display_name := ""
var description := ""
## Badge colour.
var region := Regions.RED
## Shown as a question mark until unlocked.
var hidden := false
## Progress needed. 1 or less shows no progress bar.
var target := 1
## Percent more emission rate; negative is less.
var rate_more_percent := 0
## Percent more orb value.
var value_more_percent := 0


static func make(p_key: String, p_name: String, p_description: String, p_region: int,
		p_rate_more: int, p_value_more: int, p_target: int = 1,
		p_hidden: bool = false) -> Achievement:
	var a := Achievement.new()
	a.key = p_key
	a.display_name = p_name
	a.description = p_description
	a.region = p_region
	a.rate_more_percent = p_rate_more
	a.value_more_percent = p_value_more
	a.target = p_target
	a.hidden = p_hidden
	return a
