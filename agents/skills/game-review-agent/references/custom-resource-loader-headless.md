# Custom Resource Format Loaders in Godot Headless Mode

> `ResourceLoader.exists()` and `load()` fail for custom resource formats
> (`.dialogue`, `.npc`, `.story`, etc.) registered by addon plugins in
> `--headless --script` mode. The plugin's `ResourceFormatLoader` is not
> initialized because the editor plugin system is inactive.

## The Gap

Addons like `godot_dialogue_manager` register custom resource format loaders
that teach Godot how to interpret `.dialogue` files. In `--headless --script`
mode, these loaders are never registered, so:

```gdscript
ResourceLoader.exists("res://dialogues/office_door.dialogue")  # → false
load("res://dialogues/office_door.dialogue")                    # → null
```

The files **exist on disk** and **work at runtime** (when the plugin initializes
in the full editor or deployed build) — but headless script mode can't see them.

## Detection Signs

- Smoke test (or verification script) shows 12+ `DF:` failures: file exists
  checks returning false.
- The test output shows failures for ALL files of a given custom extension.
- Other resource types (`.gd`, `.tscn`, `.res`) work fine.
- Running `FileAccess.file_exists()` works but `ResourceLoader.exists()` doesn't.

## Fixes (in order of preference)

### 1. Use `FileAccess.file_exists()` for custom formats

In `ResourceLoader.exists()` is designed for Godot's native resource formats.
For files that are plain-text data with a custom extension, use Godot's
filesystem API instead:

```gdscript
# Instead of:
ResourceLoader.exists("res://dialogues/office_door.dialogue")

# Use:
FileAccess.file_exists("res://dialogues/office_door.dialogue")
```

Trade-off: `FileAccess.file_exists()` only proves the file is on disk, not that
it's a valid resource. Combine with a structural validation step if needed
(e.g., open the file, check header format).

### 2. Run the addon's own test suite

If the addon has a test suite that exercises its resource loading, run that
instead of re-inventing the check. The `godot_dialogue_manager` integration
tests passed 86/86 in this session while the smoke test failed 12/12 on
`.dialogue` file checks.

### 3. Verify via `--headless --quit` mode (fail-safe)

If `--script` mode can't test a feature at all, fall back to verifying that
the project loads without parse errors in full-engine mode:

```bash
godot --headless --quit 2>&1
```

This boots the full engine, loads all plugins and autoloads, and exits.
Any parse error or missing-resource crash surfaces here. See
`godot-headless-testing` skill's "Exit Code for CI" section.

## Real-World Trace (PR #247, Issue #215)

| Check | Method | Result | Root Cause |
|-------|--------|--------|------------|
| Smoke test DF checks | `ResourceLoader.exists("res://dialogues/*.dialogue")` | ❌ 12/12 failed | Plugin `ResourceFormatLoader` not active in `--script` mode |
| Dialogue test suite | `load()` + `DialogueManager` API | ✅ 86/86 passed | Test harness initializes DM via its own plugin bootstrap |
| Manual file check | `ls dialogues/*.dialogue` | ✅ All 14 files present | Filesystem has them, Godot's resource cache doesn't |

The lesson: `ResourceLoader.*` is not authoritative for addon-registered
formats in headless mode. Prefer `FileAccess.file_exists()` or the addon's
own test suite.
