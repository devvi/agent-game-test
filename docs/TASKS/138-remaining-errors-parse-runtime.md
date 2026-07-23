# Tasks: #138 — Parse Error, Missing Scene Nodes, add_child Race (Game Still Won't Run)

> Parent Issue: #138
> Priority: critical
> Estimated: 60 minutes
> Prerequisite: Research PR #139 (merged)
> Design Reference: `docs/DESIGN/138-remaining-errors-parse-runtime.md`

---

## Task Breakdown

### Phase 1 — Parse Errors: `.has()` on Node (A1)

**Rationale:** 5 parse-error sites across 4 files. Fixing `scene_base.gd` propagates to all 7 scene subclasses automatically.

**Files involved:**
- `gdscripts/scene_base.gd` — base class (1 fix → all subclasses)
- `gdscripts/office.gd` — already fixed in-office.gd sites
- `gdscripts/store.gd` — scene subclass
- `gdscripts/street.gd` — scene subclass

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T1 | Fix `.has()` → `"in"` in scene_base.gd | `gdscripts/scene_base.gd` | None | 2 min |
| T2 | Fix `.has()` → `"in"` in office.gd | `gdscripts/office.gd` | None | 2 min |
| T3 | Fix `.has()` → `"in"` in store.gd | `gdscripts/store.gd` | None | 2 min |
| T4 | Fix `.has()` → `"in"` in street.gd | `gdscripts/street.gd` | None | 2 min |

---

#### T1 Details — Fix `.has()` in scene_base.gd

**File:** `gdscripts/scene_base.gd`

**Line 37 — Change:**

```gdscript
# Before:
if gm.has("choices_history") and not gm.choices_history.is_empty():

# After:
if "choices_history" in gm and not gm.choices_history.is_empty():
```

**Verification:** After fix, `godot --headless --quit` shows no "Nonexistent function 'has'" error for `scene_base.gd`.

**Edge cases:**
- `gm` is null → `"choices_history" in null` returns false (no crash)
- `gm` is valid but lacks `choices_history` → `"choices_history" in gm` returns false → short-circuits correctly

---

#### T2 Details — Fix `.has()` in office.gd

**File:** `gdscripts/office.gd`

**Line 52 — Change:**

```gdscript
# Before:
day = int(ss.get("day")) if ss.has("day") else 0

# After:
day = int(ss.get("day")) if "day" in ss else 0
```

**Line 70 — Change:**

```gdscript
# Before:
if gm.has("choices_history") and not gm.choices_history.is_empty():

# After:
if "choices_history" in gm and not gm.choices_history.is_empty():
```

**Verification:** After fix, `godot --headless --quit` shows no "Nonexistent function 'has'" error for `office.gd`.

---

#### T3 Details — Fix `.has()` in store.gd

**File:** `gdscripts/store.gd`

**Line 49 — Change:**

```gdscript
# Before:
if gm.has("choices_history") and not gm.choices_history.is_empty():

# After:
if "choices_history" in gm and not gm.choices_history.is_empty():
```

---

#### T4 Details — Fix `.has()` in street.gd

**File:** `gdscripts/street.gd`

**Line 62 — Change:**

```gdscript
# Before:
if gm.has("choices_history") and not gm.choices_history.is_empty():

# After:
if "choices_history" in gm and not gm.choices_history.is_empty():
```

---

### Phase 2 — Parse Errors: `.get(key, default)` on Node (A2)

**Rationale:** 10 parse-error sites across 4 files. All `ss` references point to StateSystem (Node). Replace with property access.

**Files involved:**
- `gdscripts/bridge.gd` — 3 sites
- `gdscripts/lobby.gd` — 1 site
- `gdscripts/subway_station.gd` — 1 site
- `gdscripts/underpass.gd` — 5 sites

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T5 | Fix `.get(key, default)` in bridge.gd | `gdscripts/bridge.gd` | None | 3 min |
| T6 | Fix `.get(key, default)` in lobby.gd | `gdscripts/lobby.gd` | None | 2 min |
| T7 | Fix `.get(key, default)` in subway_station.gd | `gdscripts/subway_station.gd` | None | 2 min |
| T8 | Fix `.get(key, default)` in underpass.gd | `gdscripts/underpass.gd` | None | 5 min |

---

#### T5 Details — Fix `.get(key, default)` in bridge.gd

**File:** `gdscripts/bridge.gd`

**Line 44:**

```gdscript
# Before:
var will_val: float = ss.get("will", 5.0)
# After:
var will_val: float = ss.will if ss else 5.0
```

**Line 68:**

```gdscript
# Before:
ss.get("conviction", 5.0) <= 3.0
# After:
ss.conviction if ss else 5.0 <= 3.0
```

**Line 81:**

```gdscript
# Before:
ss.get("conviction", 5.0)
# After:
ss.conviction if ss else 5.0
```

---

#### T6 Details — Fix `.get(key, default)` in lobby.gd

**File:** `gdscripts/lobby.gd`

**Line 40:**

```gdscript
# Before:
ss.get("conviction", 5.0)
# After:
ss.conviction if ss else 5.0
```

---

#### T7 Details — Fix `.get(key, default)` in subway_station.gd

**File:** `gdscripts/subway_station.gd`

**Line 50:**

```gdscript
# Before:
ss.get("conviction", 5.0)
# After:
ss.conviction if ss else 5.0
```

---

#### T8 Details — Fix `.get(key, default)` in underpass.gd

**File:** `gdscripts/underpass.gd`

**Line 93:**

```gdscript
# Before:
var hope_val: float = ss.get("hope", 5.0)
# After:
var hope_val: float = ss.hope if ss else 5.0
```

**Line 94:**

```gdscript
# Before:
var conviction_val: float = ss.get("conviction", 5.0)
# After:
var conviction_val: float = ss.conviction if ss else 5.0
```

**Line 106:**

```gdscript
# Before:
ss.get("hope", 5.0)
# After:
ss.hope if ss else 5.0
```

**Line 130:**

```gdscript
# Before:
ss.get("hope", 5.0)
# After:
ss.hope if ss else 5.0
```

**Line 131:**

```gdscript
# Before:
ss.get("conviction", 5.0)
# After:
ss.conviction if ss else 5.0
```

---

### Phase 3 — Parse Errors: `var scene_id` Redeclaration (A3)

**Rationale:** 6 files redeclare `var scene_id: String` which is already declared in `SceneBase`. Follow the proven pattern from PR #137.

**Files involved:** `bridge.gd`, `lobby.gd`, `store.gd`, `street.gd`, `subway_station.gd`, `underpass.gd`

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T9 | Fix `var scene_id` in bridge.gd | `gdscripts/bridge.gd` | None | 2 min |
| T10 | Fix `var scene_id` in lobby.gd | `gdscripts/lobby.gd` | None | 2 min |
| T11 | Fix `var scene_id` in store.gd | `gdscripts/store.gd` | None | 2 min |
| T12 | Fix `var scene_id` in street.gd | `gdscripts/street.gd` | None | 2 min |
| T13 | Fix `var scene_id` in subway_station.gd | `gdscripts/subway_station.gd` | None | 2 min |
| T14 | Fix `var scene_id` in underpass.gd | `gdscripts/underpass.gd` | None | 2 min |

---

**General pattern for all T9–T14:**

```gdscript
# OLD:
var scene_id: String = "lobby"  # (or bridge/store/street/subway_station/underpass)

func _ready() -> void:
    super._ready()
    ...

# NEW:
func _ready() -> void:
    scene_id = "lobby"
    super._ready()
    ...
```

**IMPORTANT:** Set `scene_id` BEFORE `super._ready()` so the base class sees the correct value during `_ready()`.

**Verification for all 6:** After all fixes, `godot --headless --quit` shows no "redeclaration of 'scene_id'" errors.

---

#### T9 Details — bridge.gd

**File:** `gdscripts/bridge.gd`

- **Line 13:** Remove `var scene_id: String = "bridge"`
- In `_ready()`, add `scene_id = "bridge"` before `super._ready()`

---

#### T10 Details — lobby.gd

**File:** `gdscripts/lobby.gd`

- **Line 12:** Remove `var scene_id: String = "lobby"`
- In `_ready()`, add `scene_id = "lobby"` before `super._ready()`

---

#### T11 Details — store.gd

**File:** `gdscripts/store.gd`

- **Line 11:** Remove `var scene_id: String = "convenience_store"`
- In `_ready()`, add `scene_id = "convenience_store"` before `super._ready()`

---

#### T12 Details — street.gd

**File:** `gdscripts/street.gd`

- **Line 13:** Remove `var scene_id: String = "street"`
- In `_ready()`, add `scene_id = "street"` before `super._ready()`

---

#### T13 Details — subway_station.gd

**File:** `gdscripts/subway_station.gd`

- **Line 14:** Remove `var scene_id: String = "subway_station"`
- In `_ready()`, add `scene_id = "subway_station"` before `super._ready()`

---

#### T14 Details — underpass.gd

**File:** `gdscripts/underpass.gd`

- **Line 13:** Remove `var scene_id: String = "underpass"`
- In `_ready()`, add `scene_id = "underpass"` before `super._ready()`

---

### Phase 4 — Runtime Errors (B1–B4)

**Rationale:** 1 runtime crash + 2 null-reference crashes + 1 visual glitch. These don't prevent startup but crash the game on certain paths.

| ID | Task | Files | Dependencies | Est. |
|----|------|-------|-------------|------|
| T15 | Fix `add_child` race via `call_deferred` in scene_manager.gd | `gdscripts/scene_manager.gd` | None | 2 min |
| T16 | Add missing nodes + remove duplicate FadeCurtain in office.tscn | `scenes/office/office.tscn` | None | 15 min |
| T17 | Fix Dialogue3D to instance Dialogue3D.tscn in main.tscn | `scenes/main.tscn` | None | 10 min |

---

#### T15 Details — Fix `add_child` Race in scene_manager.gd

**File:** `gdscripts/scene_manager.gd`

**Line 32 — Change:**

```gdscript
# Before:
scene_root.add_child(_fade_curtain)

# After:
scene_root.add_child.call_deferred(_fade_curtain)
```

**Verification:** After fix, scene transitions do not produce "Parent node is busy setting up children, add_child() failed" error.

**Edge cases:**
- Scene already has a FadeCurtain node → `has_node("FadeCurtain")` returns true → `_setup_fade_curtain()` skips creation entirely → no `add_child`
- Scene does not have FadeCurtain → `call_deferred` queues the add_child for after `_ready()` completes

---

#### T16 Details — Fix office.tscn (Add Nodes + Remove Duplicate)

**File:** `scenes/office/office.tscn`

**Changes:**

1. **Add `ScreensaverText` (Label3D)** under `Environments/` — duplicate the existing `WindowText` block, rename to `ScreensaverText`, adjust position and text content
2. **Add `DesktopText` (Label3D)** under `Environments/` — same pattern, positioned appropriately
3. **Remove the hardcoded `FadeCurtain` block** (approximately lines 133-146)

**Reference node (WindowText):**
```tscn
[node name="WindowText" type="Label3D" parent="Environments"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, -1.5)
script = ExtResource("...")
...
```

**ScreensaverText should be positioned at a different location (e.g., on the monitor screen area). DesktopText on the desk area.**

**Verification:**
- After fix, `office.gd` line 47 (`screensaver_text.text = ...`) does not crash with "Cannot set 'text' on a null value"
- `desktop_text.text = ...` also works
- The fade curtain is created by SceneManager programmatically, not from the scene file

---

#### T17 Details — Fix Dialogue3D in main.tscn

**File:** `scenes/main.tscn`

**Change the Dialogue3D node from typed to instanced:**

```tscn
# BEFORE:
[node name="Dialogue3D" type="Node3D" parent="."]
position = Vector3(0, 1.5, -3)
script = ExtResource("4_dialogue_3d")

# AFTER:
[node name="Dialogue3D" parent="." instance=ExtResource("4_dialogue_3d")]
position = Vector3(0, 1.5, -3)
```

**Verification:**
1. `godot --headless scenes/main.tscn` loads without "Cannot access property 'text' on null" errors
2. `$Dialogue3D/SpeakerLabel`, `$Dialogue3D/DialogueText`, `$Dialogue3D/ChoiceContainer`, `$Dialogue3D/ContinuePrompt` all resolve to valid nodes

**Edge cases:**
- `ExtResource("4_dialogue_3d")` must reference `Dialogue3D.tscn` (not the script). Verify the external resource ID in the `[ext_resource]` section.
- If the Dialogue3D.tscn UID is different, update the resource reference accordingly.

---

## 3. Post-Fix Verification Protocol

### Primary Verification

After all fixes are applied:

```bash
cd /Users/devvi/workspace/agent-game-test
godot --headless --quit
```

**Expected result:**
- Exit code: 0
- Stderr: zero script errors, zero parse errors
- Stdout: clean startup log

**Failure indicators:**
- `SCRIPT ERROR:` prefix in output → specific file/line still broken
- Non-zero exit code → GDScript parser still rejecting something
- `Parent node is busy setting up children` → B1 not fixed

### Secondary Verification (Scene Load Smoke Test)

```bash
godot --headless scenes/main.tscn
```

**Expected result:**
- Loads entry scene without errors
- Dialogue3D display has all child nodes
- Fade curtain is created (or skipped if scene has one)

### Comprehensive Grep for Remaining Instances

After each fix phase, run to verify no stragglers:

```bash
# Check for remaining .has() on non-Dictionary
grep -rn '\.has("' --include='*.gd' gdscripts/

# Check for remaining .get(key, default) patterns
grep -rn '\.get("[a-z]' --include='*.gd' gdscripts/

# Check for remaining var scene_id redeclarations
grep -rn 'var scene_id:' --include='*.gd' gdscripts/
```

---

## 4. Edge Cases to Verify After Fixes

### Fix-Level Edge Cases

| Fix | Edge Case | Expected Behavior |
|:---:|-----------|------------------|
| T1-T4 | `"key" in node` when node is null | Returns false — no crash (GDScript `in` operator is null-safe for existence checks) |
| T5-T8 | `ss` is null (StateSystem not loaded) | Property access via `ss.hope if ss else 5.0` safely falls back to default |
| T9-T14 | `scene_id` set before `super._ready()` already used in base | `scene_id` is accessed in `_configure_environmental_text()` which is called from SceneBase._ready() AFTER the subclass's `_ready()` runs first |
| T15 | `call_deferred` on a node already added | No-op — `add_child` on an already-parented node is ignored |
| T16 | Another scene also has hardcoded FadeCurtain | SceneManager's `has_node("FadeCurtain")` check handles both cases |
| T17 | `Dialogue3D.tscn` has different UID than expected | TSCN resource reference must match — verify before committing |

### Cross-File Edge Cases

| Scenario | Files Involved | Expected Behavior |
|----------|---------------|-------------------|
| StateSystem autoload not registered | All scene scripts with `.get()` calls | Null-guarded property access falls back to defaults |
| GameManager autoload not registered | scene_base.gd, office.gd, store.gd, street.gd | `"choices_history" in null` returns false → early return |
| Scene has no pre-existing FadeCurtain | scene_manager.gd + any .tscn | `call_deferred` adds it after `_ready()` |
| Multiple scene scripts missing `scene_id` fix | Any of the 6 unmodified files | Compile error on first load of that scene |

---

## 5. Rollback Strategy

Each fix is a small, targeted change in its own file. If any fix causes a regression:

1. **Revert individual file change** with `git checkout main -- <file>` and re-verify
2. **File-level isolation:** No fix depends on another fix's changed code path
3. **Test granularity:** `godot --headless --quit` catches all fix categories immediately
4. **TSCN rollback:** If office.tscn or main.tscn edits are wrong, restore from git: `git checkout -- scenes/office/office.tscn`
