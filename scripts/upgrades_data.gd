extends RefCounted
## Tech-point upgrade table. cost[i] = tech points for level i+1.
## "infinite": true = no max level; the last cost repeats forever.
const CATS := ["Ships", "Troops", "Towers", "Economy", "Defense"]
const UP := {
	"prod":          {"cat": "Ships",   "name": "Production",     "desc": "+15% ship production",        "cost": [3, 5, 7]},
	"fleet_speed":   {"cat": "Ships",   "name": "Engines",        "desc": "+15% fleet speed",            "cost": [2, 4, 6]},
	"hull":          {"cat": "Ships",   "name": "Hull Plating",   "desc": "+15% troops per ship sent",   "cost": [3, 5, 7]},
	"troop_hp":      {"cat": "Troops",  "name": "Troop Armor",    "desc": "+20% troop HP",               "cost": [3, 5, 7]},
	"troop_speed":   {"cat": "Troops",  "name": "Troop Speed",    "desc": "+10% troop speed",            "cost": [2, 4]},
	"unlock_Scout":  {"cat": "Troops",  "name": "Scouts",         "desc": "fast, fragile",               "cost": [2]},
	"unlock_Tank":   {"cat": "Troops",  "name": "Tanks",          "desc": "slow, very tough",            "cost": [4]},
	"unlock_Bomber": {"cat": "Troops",  "name": "Bombers",        "desc": "big core damage",             "cost": [5]},
	"unlock_Shield": {"cat": "Troops",  "name": "Shield Troops",  "desc": "energy shield soaks 40 dmg",  "cost": [5]},
	"unlock_Medic":  {"cat": "Troops",  "name": "Medics",         "desc": "heal nearby troops",          "cost": [6]},
	"tower_dmg":     {"cat": "Towers",  "name": "Tower Damage",   "desc": "+25% tower damage",           "cost": [3, 4, 5, 6, 7]},
	"tower_range":   {"cat": "Towers",  "name": "Tower Range",    "desc": "+12% tower range",            "cost": [3, 4, 5]},
	"tower_rate":    {"cat": "Towers",  "name": "Fire Rate",      "desc": "+20% fire rate",              "cost": [3, 5, 7]},
	"unlock_Frost":  {"cat": "Towers",  "name": "Frost Tower",    "desc": "slows troops 50%",            "cost": [4]},
	"unlock_Missile":{"cat": "Towers",  "name": "Missile Tower",  "desc": "splash damage",               "cost": [5]},
	"unlock_Laser":  {"cat": "Towers",  "name": "Laser Tower",    "desc": "long range, rapid beam",      "cost": [6]},
	"cheap_factory": {"cat": "Economy", "name": "Cheap Factories","desc": "-15% factory cost",           "cost": [2, 4, 6]},
	"max_factories": {"cat": "Economy", "name": "Factory Cap",    "desc": "+5 max factories/planet",     "cost": [2, 3, 4, 5, 6, 7, 8], "infinite": true},
	"shield":        {"cat": "Defense", "name": "Planet Shield",  "desc": "+5 core HP when defending",   "cost": [2, 4, 6]},
	"regen":         {"cat": "Defense", "name": "Garrison Regen", "desc": "+0.2 ships/s on your planets","cost": [3, 5]},
}
