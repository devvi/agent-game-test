# Bug Investigation Techniques for Godot Compile/Runtime Errors

## When This Is Needed

Research issues with `bug` label (not feature requests) require different
exploration techniques. The standard feature-research workflow (search for
code patterns, read design docs) is insufficient — you must **trace each
error message to its exact source**, verify API compatibility, and
distinguish cache/stale-import issues from source-level errors.

## Initial Triage

### Parse Error Messages Into Triplets

Every Godot error message has the form:

```
SCRIPT ERROR: <error description>
  File: res://path/to/file.gd
  Line: <N>
```

Extract a table:

| File | Line | Error | Severity |
|------|------|-------|:--------:|
| `gdscripts/office.gd` | 12 | `The member "scene_id" already exists in parent class SceneBase` | ❌ Cannot load |
| `gdscripts/dialogue_display_3d.gd` | 44 | `Cannot call method 'get_children' on a null value.` | ⚠️ Runtime crash |

Severity classification:
- **❌ Cannot load** — script or scene fails to parse; game won't start
- **⚠️ Runtime crash** — script loads but crashes on specific code path
- **⁉️ Missing resource** — asset not found; may be silent (null) or noisy

## Trace-Back Investigation

### 1. Parent Class Inheritance Issues

Member redeclaration errors (`"member X already exists in parent class Y"`)
require reading **both** the error file AND the parent class:

```bash
# Read the error file at the specific line
read_file gdscripts/office.gd --line 12

# Read the parent class for the declaration
read_file gdscripts/scene_base.gd
```

**GDScript 2.0 rule:** Subclasses CANNOT redeclare inherited `var` members.
Fix: remove `var` from the redeclaration, set the value in `_ready()`.

```gdscript
# WRONG — compile error:
var scene_id: String = "office"

# RIGHT — set value without redeclaring:
func _ready() -> void:
    scene_id = "office"
    super._ready()
```

### 2. API Compatibility Verification

"Too many arguments" errors mean you're calling a method with more args than
it accepts. **Do not assume** an object has a `get(key, default)` method:

```bash
# Check if the object actually has the method you're calling
rg 'func get\(' gdscripts/state_system.gd
rg 'get' gdscripts/state_system.gd | grep -i 'func\|var'
```

**Common Godot 4 gotchas:**
- `Node.get()` takes exactly 1 argument (StringName key) — no default value
- Custom properties with `get:` blocks are accessed as `object.property`,
  not `object.get("property", default)`
- To read a property with fallback: `object.property if object else default`
- To read a Dictionary with default: `dict.get("key", default)` — Dictionary's
  `.get()` IS 2-arg, but Node's `.get()` is NOT

```gdscript
# WRONG — Node.get() only accepts 1 arg:
var val = ss.get("hope", 5.0)

# RIGHT — property access:
var val = ss.hope if ss else 5.0

# RIGHT (for Dictionary):
var val = some_dict.get("hope", 5.0)
```

### 3. Null Reference Trace

Null reference errors (`"Cannot call method X on a null value"`) require
checking the `@onready` path resolution:

```bash
# Find the @onready declaration
rg '@onready.*choice_container' gdscripts/dialogue_display_3d.gd

# Check if the node actually exists in the scene file
rg -p 'ChoiceContainer' scenes/dialogue/Dialouge3D.tscn
```

The `$Path` syntax resolves at `_ready()` time. If the node path is correct
(confirmed in the scene file), the null reference may be:
- A scene variant that lacks that child node
- Headless test context without the full scene tree
- A node that was renamed after the path was written

Fix: add a null guard before the dangerous call:

```gdscript
func _setup_choice_pool() -> void:
    _choice_labels.clear()
    if choice_container == null:
        return
    for child in choice_container.get_children():
        ...
```

### 4. Scene File Format Verification

Scene file parse errors (`"Parse Error. [Resource file ...tscn:N]"`) may be:
- **Actual file corruption** — invalid syntax, invisible characters
- **Stale import cache** — the file is valid but Godot's cache is stale

**Step 1: Inspect the file at the reported line:**

```bash
# Check for invisible/control characters
sed -n '<N>p' scenes/office/office.tscn | xxd

# Compare with surrounding lines for formatting consistency
sed -n '<N-2>,<N+2>p' scenes/office/office.tscn

# Check for UTF-8 BOM
head -c 3 scenes/office/office.tscn | xxd
# BOM = ef bb bf (UTF-8) — if present, remove with:
# sed -i '1s/^\xEF\xBB\xBF//' scenes/office/office.tscn
```

A clean hexdump (no control chars, proper ASCII) suggests **import cache**,
not file corruption.

**Step 2: Clear the import cache:**

```bash
# Find stale cache entries
find .godot/imports/ -name "*.office*" -o -name "*office*" 2>/dev/null

# Delete the relevant cache files
rm -rf .godot/imports/  # Nuclear option — re-imports everything next launch
# OR selectively:
find .godot/imports/ -name "*office*" -delete 2>/dev/null
```

**Step 3: Force re-import:**

```bash
godot --headless --quit  # Triggers full re-import
```

### 5. Missing Resource Verification

"Loader not found" or "No loader" errors for asset files (WAV, PNG, etc.)
require checking whether the file actually exists and is valid:

```bash
# Check if the file exists
ls -la assets/audio/footstep_office.wav

# Check the file type and format
file assets/audio/footstep_office.wav

# Compare with working files of the same type
file assets/audio/rain_loop.wav  # Working reference
```

**Common causes:**
- File exists on disk but Godot hasn't imported it yet (fresh clone)
- Sample rate / format difference from working files (e.g., 44100Hz vs 22050Hz)
- File is tracked by git but `.godot/imports/` cache is stale
- File UID mismatch in `.godot/` metadata

**Investigation flow:**

```
File on disk?          No  →  Create or restore the file
    │
    Yes
    │
Similar files load?    No  →  Compare format/bitrate with working files
    │                       →  Convert to matching format
    │
    Yes
    │
Import cache stale?    →  Delete .godot/imports/<cache-entry>
                        →  Re-run Godot to re-import
```

**Fix:** Clear the import cache and re-import. If the file format differs
from working files (e.g., 44100Hz vs 22050Hz WAV), convert:

```bash
ffmpeg -i footstep_office.wav -ar 22050 footstep_office.wav
```

If import still fails, the file may be missing its Godot import metadata.
Open the Godot editor once to trigger full import.

## Verification

After applying all fixes, verify with:

```bash
godot --headless --quit
echo "Exit code: $?"
```

Exit code 0 with no error output = all bugs fixed.

```bash
godot --headless --quit 2>&1 | grep -i "error\|SCRIPT ERROR\|Parse Error\|No loader"
```

If the output is empty, all errors are resolved.

## Common GDScript Compile Error Patterns

| Error Pattern | Likely Cause | Fix |
|---------------|-------------|-----|
| `"member X already exists in parent class Y"` | Subclass redeclares inherited `var` | Remove `var`, set in `_ready()` |
| `"Too many arguments for X()"` | Calling with more args than signature allows | Check actual method signature in the object's source |
| `"Cannot call method X on a null value"` | `@onready` path doesn't resolve | Add null guard, check node existence in scene file |
| `"Parse Error. [Resource file ...]"` | Corrupt or stale import | Check hexdump; clear import cache if file is clean |
| `"No loader found for resource"` | Missing or unimported asset | Verify file on disk; clear import cache |
| `"Invalid call. Nonexistent function X in base Y"` | Typo in method name or missing method | Check method name spelling in the object's source |
| `"Parser Error: Unexpected token"` | Syntax error, often from merge conflict residue | Check file for `<<<<<<<`, `>>>>>>>`, `=======` merge markers |
