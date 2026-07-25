# [Feature] Mini Walker 3D场景(地板+墙壁)

## Architecture
Simple Godot 4.7.1 scene with collision.

## Implementation
- Create .tscn with StaticBody3D floor
- Add CollisionShape3D
- Add walls with StaticBody3D + CollisionShape3D
- Scene script extends Node3D
