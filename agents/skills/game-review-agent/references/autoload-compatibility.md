# Autoload Compatibility Analysis

> Reference for reviewing DESIGN doc autoload specifications against actual PR `project.godot` registrations.

## Why This Matters

A DESIGN doc may specify autoloads that the implementer cannot actually register because Godot enforces constraints on what can be a singleton. When the review agent sees a deviation, it must determine whether the exclusion is justified.

## Compatibility Rules

### 1. Only `Node`-based scripts can be autoloads

```gdscript
# ✅ Compatible — extends Node
extends Node
class_name StateSystem

# ❌ NOT compatible — extends RefCounted
extends RefCounted
class_name DialogueParser

# ❌ NOT compatible — extends Resource
extends Resource
class_name ItemData
```

Godot refuses to register `RefCounted` or `Resource` subclasses as autoloads with error: *"Can't autoload a non-Node type."*

**How to check quickly:**
```bash
head -1 gdscripts/<script>.gd
```

### 2. `@onready` vars fail in autoload context

Autoloads are created before the scene tree is built. Any `@onready` variable that references a node path will fail at load time:

```gdscript
# ❌ Fails as autoload — $SceneManager resolves in the scene tree, which doesn't exist yet
@onready var scene_manager: Node = $SceneManager

# ✅ Safe — no onready dependencies
var dialogue_data: Dictionary = {}
```

**How to check:**
```bash
grep -n '@onready.*\$' gdscripts/<script>.gd
```

### 3. Complex dependency chains may fail headless

Even if a script is syntactically autoload-compatible, its `_ready()` or `_init()` may call methods or access singletons that don't exist in a headless context:

```gdscript
# ❌ May fail — AudioServer may not be fully initialized in headless mode
func _ready() -> void:
    AudioServer.set_bus_layout(load("res://default.tres"))

# ✅ Safe — no side effects at load time
func _ready() -> void:
    print("Singleton loaded")
```

## Common Patterns from This Project

| Script | extends | Has @onready path? | Autoload-Compatible? | Reason |
|--------|---------|-------------------|---------------------|--------|
| `state_system.gd` | Node | No | ✅ Yes | Pure state management, no scene dependencies |
| `scene_manager.gd` | Node | No | ✅ Yes | Manages scene transitions via signals |
| `constants.gd` | Node | No | ✅ Yes | Data-only, trivial _ready if any |
| `dialogue_runner.gd` | Node | No | ✅ Yes (but complex deps) | Could work, but preloads DialogueParser (RefCounted) |
| `dialogue_parser.gd` | RefCounted | N/A | ❌ No | Extends RefCounted, not Node |
| `scene_base.gd` | Node | Yes (`$SceneManager`, `$CanvasLayer/DialoguePanel`) | ❌ No | @onready paths fail in singleton context |

## Review Workflow

When the review agent encounters a DESIGN doc to PR autoload mismatch:

1. Read the DESIGN doc's autoload table (usually Section 3 of DESIGN docs)
2. Read the actual `project.godot` `[autoload]` section
3. For each script missing from autoloads, check:
   - `extends` type (Node vs RefCounted vs Resource)
   - `@onready` path references
   - Complex dependencies that fail headless
4. Document findings in the review comment
