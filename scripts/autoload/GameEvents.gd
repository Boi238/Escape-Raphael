extends Node
## GameEvents - global signal bus (autoload).
##
## Chunk 3 only has a Player emitting these; nothing consumes them yet.
## They exist now so later chunks don't need to reach into Player directly:
##   - Monster AI (Chunk 4) will connect to both signals below.
##   - HUD (Chunk 5) can also connect to flashlight_state_changed if it
##     wants to animate something other than the energy bar.

## Emitted whenever the player makes noise loud enough to matter.
## reveals_position = true means the monster should instantly know exactly
## where the player is (used for crank noise), as opposed to just having a
## rough chance to notice/investigate toward the sound's origin.
signal player_made_noise(position: Vector3, radius: float, reveals_position: bool)

## Emitted the instant the flashlight turns on or off (this frame, not
## next frame). Monster AI (Chunk 4) should connect to this and, if the
## light just turned on, freeze its crawl animation on whatever frame it's
## on at that exact moment.
signal flashlight_state_changed(on: bool)
