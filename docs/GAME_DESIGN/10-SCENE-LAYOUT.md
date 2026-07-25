# 3D Scene Layout

> Reference: [274-feature-mini-walker-3d DESIGN doc](../DESIGN/274-feature-mini-walker-3d.md)

## Overview

The game uses Godot 4.7.1 3D scenes composed of StaticBody3D + CollisionShape3D for world geometry (floor and walls). Scenes provide a bounded walkable area for the player character.

## Scene: `feature-mini-walker-3d.tscn`

The primary 3D scene, implementing a 10×10 world bounded by walls.

### Structure

| Node | Type | Purpose |
|------|------|---------|
| MiniWorld | Node3D (root) | Scene root with script `feature-mini-walker-3d.gd` |
| Floor | StaticBody3D | Ground plane |
| FloorShape | CollisionShape3D | Box collision (10×0.2×10) |
| WallNorth | StaticBody3D | North boundary (z=-5) |
| WallNorthShape | CollisionShape3D | Box collision (0.2×2×10) |
| WallSouth | StaticBody3D | South boundary (z=5) |
| WallSouthShape | CollisionShape3D | Box collision (0.2×2×10) |
| WallEast | StaticBody3D | East boundary (x=5) |
| WallEastShape | CollisionShape3D | Box collision (0.2×2×10) |
| WallWest | StaticBody3D | West boundary (x=-5) |
| WallWestShape | CollisionShape3D | Box collision (0.2×2×10) |

### Parameters

| Property | Value |
|----------|-------|
| World size | 10 × 10 units |
| Floor thickness | 0.2 units |
| Wall height | 2 units |
| Wall thickness | 0.2 units |
| Floor Y position | -0.5 (center), surface at -0.4 |
| Wall Y position | 0 (center) |
| Collision shape type | BoxShape3D |

## Scene: `mini_world.tscn`

Alternative 3D scene with same layout but different wall naming convention and Y-axis alignment (walls sit at y=0 bottom, floor surface at y=0).

| Node | Type | Purpose |
|------|------|---------|
| MiniWorld | Node3D (root) | Scene root with script `mini_world.gd` |
| Floor | StaticBody3D | Ground plane at y=-0.1 (center) |
| CollisionShape3D | CollisionShape3D | Box collision (10×0.2×10) |
| WallFront/Back/Left/Right | StaticBody3D | 4 boundary walls |

### Design Decisions

- **StaticBody3D** chosen over CharacterBody3D for world geometry — world objects don't need movement physics
- **BoxShape3D** used for all collision shapes — simplest and most performant shape for flat planar geometry
- **Sub-resources** (inline `[sub_resource]`) used for shape definitions to keep scenes self-contained
