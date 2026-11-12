# Gameplay Design — Electric Tile Challenge 3D

## Core loop

1. Enter the arena on the green **START** pad (safe zone).
2. Level banner shows, then the **REVEAL** phase begins.
3. Memorize the layout (mode-dependent, below).
4. Lights out — **GO!**
5. Walk the safe route with the joystick; jump button hops over nothing in
   particular, but feels great and is fully physics-driven.
6. Touch a lethal tile → zap: sparks, screen flash, camera shake, robot
   electrocution animation, truth reveal (green path / red danger), results.
7. Reach the gold **FINISH** pad → victory: confetti, jingle, stars, next level.

## Challenge modes

| Mode | Reveal | Rule | Pressure |
|---|---|---|---|
| **Memory** | Safe path (green pulse) vs danger (red pulse) for `mem_time` seconds | any safe tile is steppable in any order | memorization |
| **Timed** | Quick 2 s hint | any safe tile steppable | beat `time_limit` |
| **Pattern** | The safe tiles light up one-by-one in order (rising notes) | tiles must be re-stepped in the exact same order | sequence memory |

### Flipper hazards (Expert & Master tiers)
Some tiles carry an alternating charge: half of their period is safe, half is
lethal, with an orange warning pulse before flipping to danger. Off-path
flippers act as optional stepping stones during their safe window; on-path
flippers are mandatory timing gates. Getting caught standing on one when it
flips = zap.

## Scoring & progression

- **Stars**: 1 star finish, 2 stars beat `par_time`, 3 stars beat `gold_time`.
- **Best times** are stored per level.
- **Unlock rule**: level N+1 unlocks when level N has at least 1 star.
- Progress persists to `user://save_data.json` (Android app data).

## Tile visual language

- Green glow — safe / correct
- Red glow — lethal
- Teal glow — idle / neutral accent
- Orange pulse — flipper about to turn lethal
- White flash — correct step confirmation
- Gold — finish / victory

## Player & camera

- Third-person stylized robot droid (procedural, code-animated): idle breathing,
  walk/run cycles with knee bend, air tuck, landing squash, victory hops with
  raised arms, electrocution jitter with visor flicker.
- Movement: camera-relative, analog magnitude (joystick tilt = walk→run),
  ~5.2 m/s run speed, 6.4 m/s jump impulse, 16 m/s² gravity, floor snap.
- **Smart Follow camera** (default): smoothly trails the player and gently
  re-centers behind their heading. **Manual** camera: drag to orbit, pinch to
  zoom (wheel on desktop), pitch clamped, ray-based wall-clip prevention.
  Settings: camera mode, sensitivity, haptics.

## Touch controls

- Left half: floating virtual joystick (spawn where you touch, 30 px grab
  margin, visual ring + knob).
- Right bottom: large round JUMP button.
- Right side: drag anywhere (not over UI) to orbit; two fingers to pinch zoom.
- Android back button: opens pause in-game; leaves screens from menus.
- Pause menu: resume, restart, music/SFX sliders, quit. Results screen:
  retry / next / levels / menu.

## Audio

- Music: menu loop (laid-back synth), gameplay loop (driving pulse), crossfaded.
- SFX: UI clicks, countdown beeps, footsteps, jump/land, reveal chimes,
  rising sequence notes, electric zap, failure sting, warning beeps, star ping,
  victory riser. Independent Music/SFX bus volumes in settings + pause menu.
