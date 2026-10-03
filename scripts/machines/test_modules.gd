extends RefCounted
## Throwaway modules for the framework's tests and for poking at it in play. No real
## catalogue lives here: the module groups (excavation, movers, logistics, ...) add their
## own definitions beside this file and register them the same way.

const F = preload("res://scripts/machines/faces.gd")


## A hollow box with a pixel face on top (in), one underneath (out), a power face on its
## left and a signal face on its right. `pass` makes it a toy conduit: each scan it moves
## its contents out of its face 1 into whatever is joined there.
static func defs() -> Array:
	return [
		{
			"id": "test_box", "name": "Test Box", "size": Vector2i(28, 20), "wall": 2,
			"faces": [
				{"type": F.PIXEL, "dir": F.UP, "at": 14, "w": 6, "name": "in"},
				{"type": F.PIXEL, "dir": F.DOWN, "at": 14, "w": 6, "name": "out"},
				{"type": F.POWER, "dir": F.LEFT, "at": 10, "w": 4, "name": "power"},
				{"type": F.SIGNAL, "dir": F.RIGHT, "at": 10, "w": 4, "name": "signal"},
			],
			"pass": {"face": 1, "rate": 3},
		},
		{
			"id": "test_plug", "name": "Test Plug", "size": Vector2i(14, 20), "wall": 2,
			"faces": [
				{"type": F.SIGNAL, "dir": F.LEFT, "at": 10, "w": 4, "name": "signal"},
			],
		},
		{
			"id": "test_cap", "name": "Test Cap", "size": Vector2i(20, 14), "wall": 2,
			"faces": [
				{"type": F.PIXEL, "dir": F.UP, "at": 10, "w": 6, "name": "in"},
			],
		},
	]
