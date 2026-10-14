# Stickgame

Playable Godot 4 prototype. Move your stickman army into roaming enemies, let the units fight, then raise fallen enemies into permanent recruits.

## Play

Double-click `Play.cmd` on Windows. It uses Godot installed on PATH.

To edit the game, import `project.godot` in Godot 4 and press **F5**. Tested with Godot 4.7.1.

## Controls

- **WASD / arrow keys:** move the entire army.
- **Left-click terrain:** send the army to that point. Keyboard movement cancels the destination.
- **Hold right mouse over an enemy corpse for 0.7 seconds:** recruit it using Soul. Release or move off to cancel; switching corpses starts a fresh hold. Keep holding and move to another corpse to recruit again.
- **Space / Escape:** pause or resume.

Your army is green; enemies are red. Attacks are automatic. Enemies roam until they spot your army, then approach to attack.

Each enemy kill earns 2 Soul. Swordsmen cost 2, archers 3, and shieldbearers 4. When attacks are ready, units favor the nearest enemy with fewer than two allies assigned that tick; if every nearby target has a pair, focus fire is allowed. Each enemy independently pursues a nearby target, also spreading across the closest available opponents. Circle-body collisions give swordsmen, archers, and heavier shieldbearers different spacing and push weight. Corpse rings last 14 seconds. Hover a corpse to see its cost and your available Soul. Holding fills a gold ring and gathers orbiting Soul lights; completion releases a rising spirit, mint/gold sparks, and expanding rings. Soul is spent only on completion. Pause, focus loss, leaving the window, and opening New game cancel the hold. There is no top HUD; the battlefield fills that space. Pause and New game remain in the bottom bar. After victory, corpses stop expiring so you can recruit before continuing.

Recruits are saved immediately. Fallen friendly units recover for the next battle, including after defeat. Soul resets between battles. Stage 2 introduces archers; stage 3 introduces shieldbearers. Later stages increase the enemy count based on stage and army size.

Saves use Godot's `user://army.json` (outside the project folder). Closing during combat restarts the saved stage next time; it does not restore positions or health. **New game** asks for confirmation before replacing progress.

## Tests

```powershell
.\run_godot.ps1 -Mode test
.\run_godot.ps1 -Mode preview
.\run_godot.ps1 -Mode smoke
.\run_godot.ps1 -Mode bench
.\run_godot.ps1 -Mode live
.\run_godot.ps1 -Mode profile
```

The gameplay suite runs 67 checks covering movement, combat, hold-to-revive, persistence, victory/defeat, input routing, cancellation, overlapping/expired corpses, bounded effects, and corrupt saves. It also runs 3,745 exact simulation comparisons between the spatial-grid simulation and independent linear-targeting/pairwise-collision references, including casualties, recruitment, dense piles, cell boundaries, equal-distance ties, and varied frame times. Combat checks verify that a four-archer volley splits across two nearby targets and that mixed unit bodies physically separate. Atlas tests validate all 432 poses, complete tile borders, 3,600 animation selections, planted feet, knee geometry, seamless walk looping, and attack recovery. Allocation-reuse tests add 610 checks covering actual buffer reuse, stale candidates, deaths, ordering, grid-threshold transitions, stage resets, and recruitment. Tests use temporary save files and leave your army untouched. The preview test captures combat, revival channel/completion, pause, victory, defeat, and a 960 × 600 window in `tests/preview*.png`; smoke launches the normal game and closes after 180 frames.

## Files

- `scripts/battle_model.gd`: movement, nearest-target assignment, combat, circle-body collisions, corpses, recruitment.
- `scripts/main.gd`: input, bottom controls, tooltips, and battle flow.
- `scripts/scenery.gd`: static terrain and foliage, retained on a separate canvas.
- `scripts/battlefield_view.gd`: sprite rendering, health bars, corpses, and particles.
- `scripts/soldier_atlas.gd`: shared sprite texture and animation-frame selection.
- `scripts/soldier_painter.gd`: source artwork used only by the offline baker.
- `scripts/effect_textures.gd`: shared particle, slash, and arrow textures.
- `tools/bake_soldiers.gd`: regenerates `assets/soldiers.png`; launcher mode `bake`.
- `assets/`: generated sprite atlas, bundled fonts, and font license.
- `DESIGN.md`: palette and visual direction.
- `scripts/save_store.gd`: validated JSON saves with temporary-file replacement.
- `tests/`: gameplay and rendering checks.

This build uses procedural art for a woodland clearing, animated stickmen, and combat/revival effects. Perimeter scenery is decorative and does not block movement. No upgrades, inspection screens, asset downloads, multiplayer, or offline simulation. Army growth is uncapped. Spatial grids reduce targeting/separation work for spread-out armies; dense piles still have quadratic worst-case cost.

## Optimization measurements

Local Windows Godot 4.7.1, Compatibility renderer, AMD Radeon graphics. Same seeded workloads; CPU work, not FPS or GPU time:

| Workload | Previous build | Sprite-conversion build |
| --- | ---: | ---: |
| Simulation, 10 units | 0.094 ms/tick | 0.092 ms/tick |
| Simulation, 128 units | 4.669 ms/tick | 2.789 ms/tick |
| Simulation, 256 units | 17.451 ms/tick | 5.653 ms/tick |
| Draw-command construction, 10 units | 4.248 ms/frame | 0.195 ms/frame |
| Draw-command construction, 128 units | 53.695 ms/frame | 1.036 ms/frame |

Simulation: mean of five seeded trials, 15 warm-up ticks then 30 measured ticks each. Drawing: 30 measured frames after five warm-up frames. `bench` reports mean, median, and p95.

The hotspot profile found 128 mixed soldiers consuming 60.704 of 61.461 ms in the draw callback; outlined limbs alone took 28.750 ms, shadow ellipses 8.296 ms. Engine draw calls dropped from 7,372 to 439 after sprite conversion. Active combat exposed another ~4.9 ms/frame of particle drawing, addressed with shared particle textures rather than regenerated circles.

`live` measures actual running scenes, automatic combat, particles, and UI with a 60 FPS cap: 20 warm-up frames, 120 measured frames. A post-sprite-conversion run held ~60 FPS at 128 mixed units (16.54 ms mean frame interval, 17.63 ms p95). The 256-unit stress case averaged 24.19 ms/frame (~41 FPS), 30.83 ms p95; very large active battles remain slower. Physics CPU is timed directly per callback, not through Godot's periodically refreshed Performance monitor.

### Allocation-reuse pass

`scripts/battle_model.gd` retains bucket objects between ticks, reuses one separation-candidate buffer, and shares an immutable empty-cell fallback. Targeting ranks are overwritten in current array order instead of rebuilding their map; collected deaths erase their entries. New battles release cached grid contents. Candidate results are borrowed until the next query, not independent snapshots.

A paired headless benchmark compares the previous fresh-storage paths with reuse: nine seeds, 60 warm-up ticks and 120 measured ticks per seed, alternating timing order. At 128 units: 3.176 → 2.905 ms/tick (~8.6% less CPU). At 256: 6.384 → 6.005 ms/tick (~5.9%). Ten-unit timing was effectively unchanged (0.112 → 0.114 ms). These are simulation CPU results, not an FPS gain; live 256-unit performance remains variable and below 60 FPS. Benchmark command:

```powershell
.\run_godot.ps1 -Mode allocbench
```

Reuse retains previously occupied cell containers within a battle, trading some retained storage for fewer array/map allocations. It does not eliminate backing-buffer growth or sorting. Gameplay and sequential pair/target order are unchanged.

### Workarounds and tradeoffs

- Soldier limbs, weapons, shadows, corpse art, and timer rings are baked once into `assets/soldiers.png`. Live units use two textured quads plus health bars. The 1536 × 3072 RGBA atlas is shared (~18 MiB uncompressed GPU storage), not duplicated per unit.
- Idle/walk/attack use 8/16/12 poses, for both teams and damage flashes. Walking has a planted stance and lifted swing foot, articulated knees, counter-swinging arms, and restrained body bounce. Swords strike quickly and recover; archers release/reload their bowstring; shields thrust and settle. Damage timing and simulation are unchanged. Corpse timers have 64 visual steps; actual corpse expiration is unchanged. Recruitment now requires a 0.7-second hold. Run launcher mode `bake` after editing the source artwork.
- Particles, glows, melee slashes, and arrows use shared textures. Revival and impact rings reuse the baked atlas; impact drawing is grouped by texture. Limits: 240 particles, 32 impact pulses, 24 revival bursts, and 18 ambient motes. No combat ticks are skipped.
- With the added effects, the latest live benchmark measured 17.515 ms/frame at 128 units (~57 FPS) and 33.064 ms at 256 (~30 FPS). These runs vary; do not infer unchanged FPS from the caps. Live draw-command CPU at 128 units was 1.588 ms/frame, with animation/effects processing at 0.493 ms/frame.
- Targeting uses a moving spatial grid for large armies, checks the containing cell first, prunes impossible cells, and preserves original array-order ties.
- Circle-body collisions use 12/14/16 px radii for archers/swords/shieldbearers and lighter/heavier inverse-mass response. Separation tests nearby cells in pair order; after pushes it updates the grid and re-queries. Crowded rows fall back locally, not by degrading the entire army to all-pairs. Small armies bypass the grid.
- Grids require O(n) auxiliary references/indices. Sparse workloads avoid most all-pairs checks; crowded local clusters use an ordered local fallback. Dense worst cases remain quadratic. Unit order, damage, RNG progression, death, recruitment, and save format are preserved.

### Pair-first combat and body physics

`MAX_ATTACKERS_PER_TARGET` is two: each ready attacker picks the nearest target not already assigned a pair this tick; if no target is available, it falls back to the nearest enemy. Enemy approach uses the same pair-first assignment so they spread across the friendly line. Custom circle collisions use 12 px archers, 14 px swordsmen, and 16 px shieldbearers; inverse masses make shields harder to displace. This avoids rigid-body node overhead and keeps deterministic simulation order.

Latest local Godot 4.7.1 profile (seeded, units held alive): simulation averaged 4.274 ms/tick at 128 units and 8.046 ms/tick at 256. One active live run measured 16.778 ms/frame at 128 and 53.699 ms/frame at 256; frame time varies substantially as large armies converge and fight. That 256-unit stress case remains slow. Unit order, damage, RNG progression, death, recruitment, and save format are preserved.
