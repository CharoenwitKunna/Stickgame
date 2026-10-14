# Stickgame visual direction

Desktop Godot battlefield, 1280 × 800 logical canvas. Keep movement, recruitment costs, and progression rules; revival now requires a 0.7-second right-mouse hold.

The field is the focus: a painted woodland clearing, worn earth, grass, perimeter trees, and grounded stickman silhouettes. Preserve the green-friendly/red-enemy distinction. Remove the debug grid and make weapons and animation carry unit identity.

## Palette
- HUD and outlines: deep forest `#172622`, charcoal `#12201f`.
- Ground: moss, sage, and muted earth; texture is subdued behind combat.
- Friendly accent: mint `#8bd7b0`.
- Enemy accent: coral `#e58375`.
- Soul and revival: warm gold `#e3c989`.
- Text: parchment `#f1ecd9`, secondary `#b8c8b7`.

## Presentation
- No top HUD, title, counters, or location strip. The battlefield extends to the top edge.
- Keep help, Pause, and New game in a quiet bottom bar; reserve the arena for combat. Corpse tooltips show cost and available Soul.
- Filled heads, bold limbs, readable swords/bows/shields, and directional facing.
- Units select the nearest available opponent, with two attackers per target before nearby allies fan out. If every target is already engaged, overflow units may focus fire.
- Collision circles prevent sprite centers overlapping: archers are light/small, swordsmen medium, and shieldbearers heavy. Heavy units yield less when bodies press together.
- Walk cycles use planted stance feet, lifted swing feet, fixed-length knee joints, counter-swinging arms, and restrained body bounce. Leaning must not drag planted feet.
- Attacks have a fast strike/release followed by follow-through and recovery: sword cuts, bowstring release/reload, and shield thrusts. Keep damage immediate; do not add a cosmetic wind-up that delays combat.
- Bake 8 idle, 16 walking, and 12 attack poses per variant into the shared atlas. More poses must not add live draw calls.
- Soft offset ground shadows. Show health bars for injured units, not every idle soldier.
- Distinct hit, arrow, death, and revival feedback; effects never change combat timing.
- Hold right mouse inside the existing corpse hit radius for 0.7 seconds. Show a filling gold ring, orbiting Soul lights, and percentage feedback. Release, pointer exit, pause, focus loss, or target changes cancel progress without charging Soul.
- Celebrate successful recruitment with a rising spectral soldier, mint/gold sparks, expanding rings, and soft light. Add brief team-colored impact pulses and subtle drifting motes; no camera shake or full-screen flashes.
- Effects use shared textures and bounded counts: 240 particles, 32 impacts, 24 revival bursts, 18 motes. Group impact drawing by texture; keep the battlefield readable.
- Victory/defeat uses a compact in-arena result panel that leaves corpses accessible.
- All button states include visible keyboard focus. Text and controls stay legible at the logical viewport and when downscaled to 960 × 600.

## Assets
Terrain, equipment, particles, and icons are authored locally using Godot drawing. Bundled DejaVu fonts include their license. No external asset or API requests.
