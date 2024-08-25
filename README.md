Use csv exported with landstalker_editor and display in 3d with Godot


# Convert heightmap csv to tscn
```
cd mapdata
python convert_heightmap_to_tscn.py Map240_heightmap.csv template.tscn map.tscn
```


# Hero

The hero is a 2D sprite rendered in 3D:

## Mesh

CharacterBody3d with a MeshInstance3D with a type `QuadMesh` with a size of x 1m and y 2m.

## Surface Material Override

For the sprite image: Surface Material Override, new ORMMaterial3D

Image drag to Albedo/texture (the image colors are wrong)

Billboard mode enabled

## Movements

With a GDScript

https://docs.godotengine.org/en/stable/getting_started/first_3d_game/03.player_movement_code.html

https://www.youtube.com/watch?v=XK5qpEmUA6w&t=286s
