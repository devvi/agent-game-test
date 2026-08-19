# Addon Classification Research Pattern

## Problem

When researching a GitHub addon referenced in an issue, it's easy to assume its `.tres` / resource files can be directly used at runtime in the game. Some highly-starred addons are **editor-only** — their resource files depend on `EditorSettings`, `EditorInterface`, or other editor-only APIs.

## Case: godot-minimal-theme (Issue #216)

**Addon:** `passivestar/godot-minimal-theme` (3781⭐)
**Claim:** "集成 godot-minimal-theme 作为基础 UI 主题"
**Reality:** The addon's `minimal_theme.tres` is a Godot **Editor** theme — it calls:

```gdscript
var settings : EditorSettings = EditorInterface.get_editor_settings()
base_color = settings.get_setting('interface/theme/base_color')
```

These APIs are unavailable at game runtime. Additionally, since Godot 4.6, this theme is already the **default editor theme**, so no installation is needed.

**What the project actually needs:** A custom **runtime** `Theme.tres` resource with the project's neon color palette (`#0a0a12`, `#4a90d9`, `#ff3355`), not the addon's editor theme file.

## Investigation Protocol

When an issue asks to integrate a third-party addon/theme/library:

### Step 1: Check README for runtime vs editor classification

```bash
curl -sL "https://raw.githubusercontent.com/{owner}/{repo}/main/README.md" | head -50
```

Keywords to flag as editor-only:
- `EditorSettings`, `EditorInterface`
- `editor_settings`, `get_editor_interface`
- "editor theme", "editor plugin"
- "Install in Editor Settings"
- Mentions of `@tool` script (tool scripts can mix runtime + editor, but inspect further)

### Step 2: Inspect the actual resource files

Don't trust the README alone — download and read the `.tres` / resource file:

```bash
# For releases
curl -sL "https://api.github.com/repos/{owner}/{repo}/releases/latest" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); [print(a['browser_download_url']) for a in d.get('assets',[])]"

# Download and read the actual tres file
curl -sL "<asset_url>" -o /tmp/asset.tres
head -50 /tmp/asset.tres
```

### Step 3: Check the GDScript source

Look for the actual GDScript referenced in the `.tres`:

```
[sub_resource type="GDScript" id="..."]
```

Read its content to see if it imports `EditorInterface`, `EditorSettings`, or `EditorPlugin`.

### Step 4: Check Godot version compatibility note

From the README: check minimum Godot version mentioned. Since Godot 4.6, `godot-minimal-theme` is the **default** built-in editor theme:

> "This theme has been ported to Godot natively and is the new default theme starting with Godot 4.6. You don't need to install it anymore."

If the project is on Godot 4.7+, this note confirms the addon is editor-only and already integrated.

### Step 5: Determine the correct runtime approach

| If the addon is... | Then... |
|-------------------|---------|
| Editor-only theme | Create a **new** runtime `Theme.tres` resource with the project's color palette |
| Runtime addon with `.tres` resources | Copy the `.tres` file into `assets/` and adapt colors |
| Plugin with autoload | Install as addon, register autoload in `project.godot` |
| Scene/resource pack | Import `.tscn`/`.tres` into `addons/` or `assets/` |

## Key Lesson

**Do not assume a star count or GitHub popularity guarantees runtime usability.** A 3781⭐ addon can still be entirely editor-only. Always inspect the actual resource file content before writing the PRD approach recommendation.
