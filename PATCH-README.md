# Escape Raphael — "player group empty" fix

## What was actually wrong

`player: NOT FOUND (group 'player' empty)` in your diagnostic overlay was
the real, concrete cause of the LIGHT/CRANK/energy-bar problems you've
been seeing — not lighting, not the keystore, not a stale build.

`Player.gd` was never calling `add_to_group("player")`. It only set
physics **layer** 2 ("player") in Chunk 1 — that's a collision layer,
a completely different Godot system from a node **group**. Every lookup
in `TouchControls.gd` and `DebugHUD.gd` that searched
`get_tree().get_nodes_in_group("player")` was searching a group the
Player node had simply never joined. Retrying the lookup (the earlier
"buttons look up Player once at startup" fix) didn't help, because the
group was empty every single time, not just on the first frame.

## What's in this zip

- `scripts/player/Player.gd` — same Chunk 3 mechanics (touch drag
  movement/look, gravity, dynamo flashlight: 5s crank = 14s light,
  -10% move speed while cranking, noise ping every ~0.35s at 30-unit
  radius), **plus the one-line fix**: `add_to_group("player")` in
  `_ready()`.
- `scripts/ui/TouchControls.gd` — CRANK/LIGHT buttons + energy bar,
  rewritten to bind to the player via the group lookup with a
  self-healing retry, so a future scene-load-order change can't
  silently break the buttons again the same way.
- `scripts/debug/DebugHUD.gd` — same diagnostic overlay, bumped to v2.
  Once this patch is applied you should see `player: FOUND` with live
  `flashlight_on` / `energy` / `is_cranking` values instead of the
  "NOT FOUND" line.

This assumes your repo is currently at the state from
`escape-raphael-COMPLETE-v2.zip` / the debug-diagnostics build (the one
these two screenshots came from) — i.e. the keystore fix, lighting
values, stair-climb fix, and button-size fix are already in your repo
from that push. This patch only touches the three files above; it does
not re-touch lighting, the level, or the keystore.

## Deploy (same as always)

```bash
cd ~/Escape-Raphael
git fetch origin
git reset --hard origin/main
unzip -o ~/storage/downloads/escape-raphael-group-fix.zip -d .
git add -A
git commit -m "Fix: Player never joined the 'player' group, so every UI lookup found nothing"
git push
```

Wait for Actions to go green, **uninstall the old app first**, then
install the fresh APK (still on the same permanent keystore from the
last fix, so this should now genuinely install as an update — but a
clean uninstall/reinstall is the safe move either way since the last
several rounds have been confusing enough already).

## How to confirm it worked

Open the app. The yellow debug box at the top should now read:

```
player: FOUND
  flashlight_on=false  energy=14.00  is_cranking=false
```

Tap LIGHT — `flashlight_on` should flip to `true` and the screen should
actually light up. Hold CRANK — `is_cranking` should flip to `true` and
`energy` should tick up in real time. If both of those move, the whole
UI chain is finally working end to end.

Once you've confirmed that, say so and I'll pull the debug overlay back
out (it's meant to be temporary) and we can get back to the actual
roadmap — Chunk 5 (real menu/UI/death screen) is next.
