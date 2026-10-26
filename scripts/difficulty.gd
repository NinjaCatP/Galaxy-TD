extends RefCounted
## All difficulty tuning in one table. Multipliers of -1 mean "no cap".
##  atk_cap:     max AI attack force as a multiple of the player's weakest planet garrison
##  prod_cap:    max AI per-planet production as a multiple of the player's weakest planet production
##  prod_bonus:  multiplier on AI base production
##  decision:    seconds between AI decisions (reaction speed)
##  build:       seconds between AI factory builds
##  force_timer: AI attacks with whatever it may send if it hasn't attacked for this long
##  min_attack:  smallest force the AI will ever send at a player planet
##  fronts:      how many player planets the AI may attack in one decision
##  target:      "weakest" | "near" | "production"
##  counter:     prioritise planets the player just captured / retake lost ones
##  upg:         chance an attack uses Scout/Tank/Bomber
##  bombers:     prefer Bombers vs towered planets
##  tower_bonus: extra AI tower levels; smart_towers: place towers where they cover most path
##  ai_upg:      AI upgrade level baseline (grows +1 every 4 minutes); also unlocks AI tower types
##  start_ships: AI home planet starting ships
const DATA := {
	"Easy": {"ai_upg": 0, "atk_cap": 1.0, "prod_cap": 1.0, "prod_bonus": 1.0, "decision": 3.0, "build": 15.0, "force_timer": 40.0, "min_attack": 3,
			   "fronts": 1, "target": "weakest", "counter": false, "upg": 0.3, "bombers": false, "tower_bonus": 0, "smart_towers": false, "start_ships": 30},
	"Normal": {"ai_upg": 1, "atk_cap": 1.5, "prod_cap": 1.5, "prod_bonus": 1.0, "decision": 2.5, "build": 12.0, "force_timer": 25.0, "min_attack": 5,
			   "fronts": 1, "target": "near", "counter": false, "upg": 0.4, "bombers": false, "tower_bonus": 0, "smart_towers": true, "start_ships": 35},
	"Hard": {"ai_upg": 2, "atk_cap": 2.5, "prod_cap": -1, "prod_bonus": 1.0, "decision": 2.0, "build": 9.0, "force_timer": 18.0, "min_attack": 8,
			   "fronts": 2, "target": "production", "counter": true, "upg": 0.55, "bombers": false, "tower_bonus": 1, "smart_towers": true, "start_ships": 40},
	"Brutal": {"ai_upg": 3, "atk_cap": -1, "prod_cap": -1, "prod_bonus": 1.4, "decision": 1.2, "build": 6.0, "force_timer": 10.0, "min_attack": 10,
			   "fronts": 3, "target": "production", "counter": true, "upg": 0.7, "bombers": true, "tower_bonus": 2, "smart_towers": true, "start_ships": 50},
}
const ORDER := ["Easy", "Normal", "Hard", "Brutal"]
