# Implementation Gap Analysis — Research → Implementation

> When an implementation issue (#N) follows a separate research issue (#R), the codebase may already contain parts of the DESIGN from the research PR. The plan agent's job is to identify what exists vs. what remains.

## The Problem

The research Design doc describes a complete system. But by the time the implementation issue arrives, some components may already be built (from the research PR or intermediate PRs). The plan agent must NOT design something that already exists — this wastes implement phase effort.

## Systematic Gap Analysis

### Step 1: Read the Research DESIGN doc (`docs/DESIGN/<R>-*.md`)

Extract the **File Manifest** — typically section `## Existing Component Modifications` or `## File Manifest`. Build a checklist:

| Component | Status | File to Check |
|-----------|--------|---------------|
| `navigation_controller.gd` | ❓ | `gdscripts/navigation_controller.gd` |
| `scene_manager.gd` extended | ❓ | `gdscripts/scene_manager.gd` — search for `trigger_zone_transition` |

### Step 2: Check Each File

For each claimed-new or claimed-modified file:

```bash
# Does the file exist?
ls -la gdscripts/navigation_controller.gd 2>/dev/null && echo "EXISTS" || echo "MISSING"

# Does the method/signal/export exist?
grep -n "func trigger_zone_transition" gdscripts/scene_manager.gd
grep -n "exit_label" gdscripts/exit_zone.gd
grep -n "navigation_hint_requested" gdscripts/player_controller.gd
grep -n "navigation_context" gdscripts/game_manager.gd
```

### Step 3: Classify Each Component

| Status | Meaning | Action |
|--------|---------|--------|
| ✅ **Complete** | File exists, all signals/exports/methods from DESIGN are present | Document as "already delivered, no change needed" |
| ⚠️ **Partial** | File exists but missing some DESIGN elements | Document what's missing in "Existing Component Modifications" |
| ❌ **Missing** | File doesn't exist | Design as a "New Component" |
| 🟡 **Different** | File exists but behaves differently than DESIGN assumed | Document the divergence and design resolution |

### Step 4: Create the "Current State vs Target State" Table

In your DESIGN doc, put this table in the Architecture Overview section:

```markdown
### Current State vs Target State

**Already built (#R delivered):**

| Component | Status | Delivered |
|-----------|--------|-----------|
| `scene_manager.gd` | ✅ Complete | `trigger_zone_transition()`, `_show_title_overlay()` |
| `navigation_controller.gd` | ❌ Missing | Not yet created |

**Remaining to implement (#N scope):**

| Component | Status | Action |
|-----------|--------|--------|
| `navigation_controller.gd` | ❌ New file | Create with condition timers, H-key routing |
| `scene_base.gd` | ⚠️ Partial | Add `_setup_navigation()`, virtual methods |
```

### Step 5: Report Cross-References for Dependent Files

When analyzing existing code, check for patterns that show the infrastructure is *already wired* even if the main component is missing:

```gdscript
# If ExitZone._transition() already sets navigation_context on GameManager,
# but navigation_controller.gd doesn't exist yet:
# → The EXIT PATH is wired (exit_label, route_hint propagate to GM)
# → The ENTRY PATH is not (no one reads navigation_context in new scene)
```

## Real Example: #221 → #226

In the actual session (2026-07-25), gap analysis revealed:

| Component | DESIGN #221 Said | Actual Codebase | Action |
|-----------|-----------------|-----------------|--------|
| `scene_title_overlay.gd` | New file | ✅ Exists, complete | No change |
| `nav_fallback.gd` | New file | ✅ Exists, complete | No change |
| `scene_manager.gd` | Extended | `trigger_zone_transition()` ✅, `_show_title_overlay()` ✅ | No change |
| `exit_zone.gd` | Extended | `exit_label` ✅, `route_hint` ✅, `navigation_context` ✅ | No change |
| `game_manager.gd` | Extended | `navigation_context` ✅, `fallback_count` ✅ | No change |
| `player_controller.gd` | Extended | `navigate_hint` ✅, `navigation_hint_requested` ✅ | No change |
| `constants.gd` | Extended | All nav constants ✅ | No change |
| `navigation_controller.gd` | New file | ❌ **Does not exist** | Design for #226 |
| `scene_base.gd` | Extended | ⚠️ Missing `_setup_navigation()`, virtual methods | Design for #226 |
| 7 scene subclass .gd files | Modified | ❌ `_on_condition_text_updated()` overrides | Design for #226 |

Result: The #226 DESIGN doc was able to say "7 of 16 deliverables are already complete" and focus on the 9 remaining items.
