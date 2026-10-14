# Stickgame — Game Plan

## Game pitch
A 2D stickman army battle game. You control your army's movement while the enemy army wanders on its own. Units attack automatically, and you can hold right mouse over fallen enemies to raise them as permanent members of your army.

**Core hook:** the enemy army is also your recruitment pool. Defeat a new kind of soldier, then turn its fallen members into your own troops.

## Design goals
- Easy to understand: you direct your army's movement; units handle combat automatically.
- Active decisions during battle: choose which corpses to raise and when.
- Long-term progress: raised units remain in your army between battles.
- Small first release: one battlefield, a few unit types, and a short campaign.

## Main game loop
1. Enter the next campaign battle with your army from the previous fight.
2. You direct your army around the arena. The enemy army wanders randomly, and both sides attack automatically when enemies are in range.
3. Enemies leave corpses when defeated. Hold right mouse over a corpse for 0.7 seconds to spend Soul and raise that unit; it joins on completion and becomes a permanent member of your army.
4. At battle end, your army carries forward automatically. Fallen friendly units recover for the next battle, so recruits are not permanently lost.
5. Face stronger stages and new enemy types as the campaign progresses.

## Battle rules
- Use an open 2D arena. The player controls the friendly army's movement; friendly units maintain loose spacing and automatically attack the nearest available enemies in range. Up to two ready allies are assigned to a target per tick before nearby allies fan out; if all nearby targets have pairs, focus fire is allowed. Enemy units wander toward random nearby points until contact, then spread across nearby opponents too.
- Unit bodies use circle collisions and different masses. Crowds push apart in simulation space; shieldbearers yield less than swordsmen and archers. Collisions change position, not combat stats.
- A corpse stays targetable for a short time, then disappears. Holding right mouse over it for 0.7 seconds raises one unit of that type if you have enough Soul. Release or move off to cancel without spending Soul.
- Soul comes from defeating enemies and resets after each battle, so kills create a limited recruitment budget for that fight.
- Raised units join the active fight immediately and remain in the army between battles, even if they fall later.
- The full army deploys automatically in the next battle; difficulty scales with campaign progress and army size.

## Starter unit roster
Keep the first playable version to three distinct roles:
- **Swordsman:** inexpensive close-range unit; reliable baseline.
- **Archer:** ranged damage; fragile if enemies reach it.
- **Shieldbearer:** slow, durable front line; protects nearby allies.

Add more types only after the battle loop is fun, such as spearmen, fast scouts, or a heavy brute. Each new type should have a clear counter or role.

## Campaign flow
- After victory, continue to the next battle with the same army. New enemy types become recruitable after first appearing.
- No camp, unit-inspection, upgrade, or manual army-management screens. The game saves the army in the background.

## Controls and interface
- Use movement input to direct the friendly army around the battlefield.
- Hold right mouse over an enemy corpse to raise it; a gold progress ring and gathering lights show the channel.
- Show health bars, current Soul, and a clear revive cost/readiness indicator.
- Use simple result buttons to continue after victory or retry after defeat.

## Godot implementation outline
Target **Godot 4, 2D, GDScript** for the first version.

Suggested scene boundaries:
- `Main`: starts battles, shows results, and advances or retries the campaign.
- `Battle`: battlefield, camera, unit spawning, and battle UI.
- `Unit`: one reusable scene driven by unit data and current state.
- `Corpse`: clickable remains with a timed cleanup.

Keep unit stats in reusable data resources (for example, a custom `Resource` per unit type), rather than hard-coding separate combat scripts for every class. Save the army and campaign stage in the background; temporary health, positions, Soul, and corpses do not persist between battles.

## Build milestones

### 1. Combat sandbox
- Create one test arena and two teams of stickmen.
- Implement player-directed friendly movement, random enemy roaming, automatic attacks, health, and defeat.
- Use simple placeholder shapes; focus on readable combat, not polished art.

**Done when:** units can fight to a clear win/loss without getting stuck or attacking through the whole map.

### 2. Corpse revival
- Spawn a corpse when an enemy falls.
- Add a short corpse timer and cancellable right-mouse hold detection.
- Spend Soul, spawn the matching friendly unit, and make it join the fight.

**Done when:** the player can choose a corpse, afford or lack the cost, and see the recruited unit fight for their side.

### 3. Persistent army and battle results
- Add victory/defeat and carry recruited units into the next battle automatically.
- Save the army and campaign stage; restore them when the game launches again.
- Return fallen friendly units to the army for the next battle.

**Done when:** recruited units remain in the army after a battle and after restarting the game.

### 4. Campaign flow and combat UI
- Add simple continue/retry buttons and clear Soul and revive-cost displays.
- Advance the campaign automatically after victory; introduce new enemy types in later stages.

**Done when:** the player can complete a battle, continue, and see the same army enter the next one without a management screen.

### 5. More battles and polish
- Add a handful of increasingly difficult battles and introduce the three starter unit types.
- Tune revive costs, battle pacing, and enemy scaling. Add hit feedback, sound, and simple animations.

**Done when:** a new player can understand the controls and complete the first few battles without a tutorial wall.

## First playable scope
The first playable build should contain **one arena, player-controlled army movement, randomly roaming enemies, swordsmen, one enemy corpse type, hold-to-revive, Soul, a win/loss condition, and an army that carries into a second battle**. Add other unit classes and more campaign stages after this loop feels good.

## Out of scope for the first version
Online multiplayer, procedural campaigns, complex formations, equipment, base-building, unit inspection, upgrades, and offline rewards. These add work before the central revive-and-grow loop has been tested.
