extends Node
## Global game state. Loaded automatically as "Game" (see Project > Project Settings > Autoload).
## Anything stored here survives when the game switches scenes.

# --- Change these to your own character names! ---
const HERO_NAME := "Hero"
const ALLY_NAME := "Buddy"
const ENEMY_NAME := "Guard"

var ally_joined := false
var in_dialogue := false      # true while a dialogue box is open (freezes the player)
var enemy_beaten := false
var just_won := false

var hero_max_hp := 20
var hero_hp := 20
var ally_max_hp := 20
var ally_hp := 20
var items := 3

# Where to put the player when coming back from a battle.
var has_return_pos := false
var player_return_pos := Vector2.ZERO


func heal_party() -> void:
	hero_hp = hero_max_hp
	ally_hp = ally_max_hp
	items = 3
