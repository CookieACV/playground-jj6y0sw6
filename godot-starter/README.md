# Team Up RPG Starter (Godot 4)

A starter project for a 2D RPG: walk through the map, meet a friend who joins your team,
then fight an enemy together in a turn-based battle with a dodge phase.

## How to open it
1. Download this `godot-starter` folder.
2. Open **Godot 4.3 or newer**, click **Import**, and pick the `project.godot` file in this folder.
3. Press **F5** (or the ▶ Play button at the top right) to play.

## Controls
| Key | What it does |
|---|---|
| Arrow keys | Move / pick menu options / dodge |
| Enter or Space | Talk, next line, confirm |
| Esc | Go back (in the battle's ally menu) |

## What's in the game
1. **Start**: you walk right from the start area.
2. **Meet your ally**: walk up to the orange character and press Enter. They join and follow you.
3. **The enemy**: the red triangle blocks the bad guy area. If you go alone, you get pushed back.
4. **Battle**: pick FIGHT / ACT / ITEM for the hero, then FIGHT / HEAL for the ally,
   then dodge the falling bullets with the red square. Win by hitting the enemy's HP to 0,
   or use ACT until mercy reaches 100%.
5. **Bad guy area**: the gate at the far right is where your next scene goes.

## Make it yours
- **Your art**: replace the PNG files in `assets/` with your own (same file names).
  - `hero_1.png`, `hero_2.png`: your character (standing, walking)
  - `ally_1.png`, `ally_2.png`: your ally
  - `enemy.png`: the enemy
  - Want more walking frames? Open `scenes/player.tscn`, click **AnimatedSprite2D**,
    and drag more images into the **SpriteFrames** panel at the bottom.
- **Names**: change `HERO_NAME`, `ALLY_NAME`, `ENEMY_NAME` at the top of `scripts/game.gd`.
- **What characters say**: edit the lines in `scripts/ally.gd`.
- **HP, damage, items**: `scripts/game.gd` (HP, items) and `scripts/battle.gd` (damage, enemy HP, bullet speed).
- **The map**: open `scenes/overworld.tscn` and move things around in the editor.

## Files
| File | What it is |
|---|---|
| `scenes/overworld.tscn` + `scripts/overworld.gd` | The map |
| `scenes/player.tscn` + `scripts/player.gd` | Your character |
| `scenes/ally.tscn` + `scripts/ally.gd` | The friend who joins you |
| `scenes/dialogue_box.tscn` + `scripts/dialogue_box.gd` | The text box |
| `scenes/battle.tscn` + `scripts/battle.gd` | The battle |
| `scripts/danger_zone.gd` | Starts the battle when you walk into it |
| `scripts/end_gate.gd` | Entrance to the bad guy area (build this next!) |
| `scripts/game.gd` | Saved info (HP, names, who joined) shared by every scene |

## Ideas for next steps
- Build the bad guy area as a new scene and load it from `scripts/end_gate.gd`.
- Add different bullet patterns in `_update_dodge()` in `scripts/battle.gd`.
- Add music: drop an `.ogg` file in, add an **AudioStreamPlayer** node, turn on **Autoplay**.
- Keep it free to share: fan characters belong to their creators.
