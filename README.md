# Escape Raphael

A first-person horror escape game. Your friend Raphael stopped showing up to
school. You go check on him — he's not himself anymore, and now you're
locked in his basement with something that used to be him.

Built in **Godot 4.3**. No local Android build tools needed — GitHub Actions
builds the APK for you in the cloud every time you push. You never need
Android Studio, the Android SDK, or Gradle on your phone.

## How the build works

1. You edit project files (either by pasting text I give you, or later by
   installing the Godot editor if you get access to a PC/laptop).
2. You `git push` from Termux.
3. GitHub Actions (see `.github/workflows/build-android.yml`) automatically
   exports a debug `.apk`.
4. You download the APK from the **Actions** tab of your repo (or from a
   Release, once we wire that up) and install it with `pm install` or by
   opening the file.

## First-time setup in Termux

```bash
pkg update && pkg upgrade -y
pkg install git -y

git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
```

If this is a brand-new empty GitHub repo, instead do:

```bash
cd escape-raphael          # the folder I gave you
git init
git remote add origin https://github.com/<your-username>/<your-repo>.git
git add .
git commit -m "Project scaffold + CI pipeline"
git branch -M main
git push -u origin main
```

Termux will ask for your GitHub username + a **Personal Access Token**
(not your password — GitHub removed password auth for git). Create one at
github.com → Settings → Developer settings → Personal access tokens →
generate one with `repo` scope, and paste it when Termux asks for a
password.

## Getting the APK after a push

1. Go to your repo on GitHub → **Actions** tab.
2. Click the latest **Build Android APK** run.
3. Scroll down to **Artifacts** → download
   `escape-raphael-debug-apk.zip`.
4. Unzip it (on your phone, any file manager / zip app works) to get
   `escape-raphael-debug.apk`.
5. Install it (you'll need "install unknown apps" allowed for whatever app
   you're opening it with).

## Chunk 2: level greybox (basement + upper floor)

New files this chunk:

```
data/level_data.json          - every wall/floor/ceiling/stairs box + spawn points
scripts/world/LevelBuilder.gd - reads level_data.json and builds the whole
                                 house at runtime (nothing is hand-placed in
                                 the .tscn — edit the JSON to change the layout)
scripts/debug/DebugFlyCam.gd  - TEMPORARY touch-controlled test camera
scenes/Level.tscn             - the level scene (WorldEnvironment + LevelBuilder + DebugFlyCam)
project.godot                 - now points main_scene at Level.tscn so the
                                 APK actually loads something playable
                                 (this will get swapped to the real
                                 MainMenu.tscn in Chunk 5)
```

**13 rooms** across 2 floors, connected by doors and one stairwell:

- **Basement**: Start room (you wake up here) → narrow corridor → Hallway →
  branches to Storage and Boiler rooms → stairs up.
- **Upper floor**: stairs open into the Foyer → Upper Hallway → branches to
  Raphael's Bedroom and a Bathroom, and continues to the Kitchen → Living
  Room, with a Front Entry at the very end (the front door — it's locked,
  narratively; the lock/interaction logic itself comes in a later chunk).

The basement→upstairs stairs are a single sloped ramp (not stepped stairs),
which matters for Chunk 3: Godot's `CharacterBody3D` walks up a ~29° slope
automatically with no extra "stair-stepping" code needed.

### Merging into your existing repo

You already have the Chunk 1 repo cloned in Termux. From inside it:

```bash
# unzip this chunk's files (adjust path to wherever you downloaded it)
unzip -o ~/storage/downloads/escape-raphael-chunk2-level-greybox.zip -d .

git add .
git commit -m "Chunk 2: level greybox (basement + upper floor, 13 rooms, stairs)"
git push
```

This will overwrite `project.godot` with the updated version (only the
`main_scene` line changed) and add the new `data/`, `scripts/world/`,
`scripts/debug/`, and `scenes/` files. It won't touch anything else from
Chunk 1.

### Testing it (superseded — see Chunk 3 section below for current controls)

## Chunk 3: player controller + crank flashlight

New files this chunk:

```
scripts/autoload/GameEvents.gd - global signal bus (autoload), so systems
                                  that don't know about each other yet
                                  (Player <-> Monster AI, Player <-> HUD)
                                  can talk without hard references
scripts/player/Player.gd       - the real player controller: touch move/
                                  look, capsule collision, gravity, and the
                                  full dynamo crank flashlight system
scripts/ui/TouchControls.gd    - CRANK (hold) + LIGHT (tap) buttons and an
                                  energy bar, built in code
scripts/world/Level.gd         - new script on the Level scene root; moves
                                  the Player to level_data.json's
                                  "player_start" marker on load
scenes/Player.tscn             - the player scene (CharacterBody3D + head/
                                  camera + flashlight SpotLight3D)
scenes/Level.tscn              - updated: DebugFlyCam removed, real Player
                                  + TouchControls added
project.godot                  - registers the GameEvents autoload
```

**Controls:**
- Drag the **left half** of the screen to move, the **right half** to look
  around (same scheme as the old debug camera).
- Hold the **CRANK** button (bottom right) to charge the flashlight. 5
  seconds of continuous cranking = 14 seconds of light. Cranking slows you
  by 10% and pings the monster's noise system every ~0.35s so it can find
  you (loud on purpose — Chunk 4 monster AI isn't in yet, so nothing reacts
  to it *yet*, but the hook is live).
- Tap **LIGHT** (bottom right, above CRANK) to toggle the flashlight. It
  drains while on and won't turn on with an empty battery.
- The bar across the top is the flashlight energy meter.

**One manual cleanup step required** — `DebugFlyCam.gd` is no longer
referenced by any scene as of this chunk, so delete it after unzipping:

```bash
rm scripts/debug/DebugFlyCam.gd
rmdir scripts/debug   # only if it's now empty
```

### Merging this chunk into your repo

```bash
cd <your-repo>
# unzip escape-raphael-chunk3-player-flashlight.zip over this folder,
# overwriting project.godot, README.md, and scenes/Level.tscn
rm scripts/debug/DebugFlyCam.gd
rmdir scripts/debug
git add -A
git commit -m "Chunk 3: player controller + crank flashlight"
git push
```

Grab the new APK from the Actions tab like before once the build finishes.

## Project status / roadmap

- [x] Chunk 1: Project scaffold + CI pipeline
- [x] Chunk 2: Basement + upper floor rooms/level greybox (walls, stairs,
      multiple rooms, doors)
- [x] Chunk 3: Player controller + crank flashlight system (5s crank = 14s
      charge, -10% move speed while cranking, cranking noise pings
      GameEvents for the monster to react to)
- [ ] Chunk 4: Monster AI — crawling animation, only moves in darkness,
      freezes mid-frame the instant a light turns on, hunts toward noise
      (connects to GameEvents.player_made_noise /
      GameEvents.flashlight_state_changed, both already emitting)
- [ ] Chunk 5: Real UI — main menu, pause menu, restyle the Chunk 3 energy
      bar/buttons, objective/clue tracker, jumpscare/death screen, repoint
      project.godot's main_scene to the real MainMenu.tscn
- [ ] Chunk 6: Audio — ambient basement drone, crank creak, monster
      breathing/crawl foley, jumpscare stinger, footsteps, UI sounds
- [ ] Chunk 7: Wire in `psx_base_male.glb` as the player body / mirror
      reflection / Raphael's "normal" flashback model

## Folder structure

```
scenes/     .tscn scene files (rooms, menus, player, monster)
scripts/    .gd scripts
assets/models/   3D models (your psx_base_male.glb lives here)
assets/audio/    music/sfx
assets/textures/ textures/materials
```
