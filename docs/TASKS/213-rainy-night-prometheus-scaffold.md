# Tasks: #213 — 雨夜普罗摩茨项目骨架 (Rainy Night Prometheus Scaffold)

> Parent Issue: #213
> Agent: plan-agent
> Date: 2026-07-24

---

## Task Breakdown

### Phase 1: Implement Scaffold (Implement Phase)

| # | Task | Description | Est. Effort |
|---|------|-------------|-------------|
| 1.1 | Create directory structure | `mkdir -p rainy-night-prometheus/{gdscripts,scenes,dialogues/json,assets/{materials,audio},tests}` | ~2 min |
| 1.2 | Create symlinks for 6 core scripts | `ln -s ../../gdscripts/xxx.gd` in `rainy-night-prometheus/gdscripts/` for each of the 6 scripts | ~2 min |
| 1.3 | Create icon symlink | `ln -s ../assets/icon.png rainy-night-prometheus/assets/icon.png` | ~1 min |
| 1.4 | Write `project.godot` | Create project config with name, renderer, display, autoloads, and input mappings | ~5 min |
| 1.5 | Write `README.md` | Project documentation with setup instructions | ~3 min |
| 1.6 | Write `.gitkeep` files (optional) | Touch `.gitkeep` in empty directories to ensure Git tracks them | ~1 min |
| 1.7 | Verify symlinks | `readlink` each symlink, `diff` with target | ~2 min |
| 1.8 | Run Godot headless validation | `godot --path rainy-night-prometheus/ --headless --quit` | ~10 sec |
| 1.9 | Git add and commit | `git add rainy-night-prometheus/ && git commit` | ~1 min |

### Phase 2: Verification & Tests (Post-Implement)

| # | Task | Description | Est. Effort |
|---|------|-------------|-------------|
| 2.1 | Create test runner | `rainy-night-prometheus/tests/` with test descriptors for scaffold validation | ~10 min |
| 2.2 | Run all scaffold tests | Execute the GDScript test runner with `--headless` | ~30 sec |
| 2.3 | Cross-platform symlink test | Verify symlinks work on macOS (CI environment) | ~1 min |

### Phase 3: CI Integration

| # | Task | Description | Est. Effort |
|---|------|-------------|-------------|
| 3.1 | Update CI config | Add `godot --path rainy-night-prometheus/ --headless --quit` to CI pipeline | ~5 min |
| 3.2 | Update or bypass `stage-gate.py` | Ensure stage gate handles the sub-project correctly | ~5 min |

---

## Dependencies Between Tasks

```
1.1 (Directories)
  └─ 1.2 (Symlinks) ── 1.3 (Icon)
       └─ 1.7 (Verify symlinks)
            ├─ 1.4 (project.godot)
            │    └─ 1.8 (Godot validation)
            └─ 1.5 (README.md)
                 └─ 1.6 (.gitkeep) ── 1.9 (Git commit)
                                       └─ 2.x (Tests)
```

---

## Verification Checklist (Commit-Ready)

- [ ] All 6 symlinks resolve to correct target files
- [ ] `godot --path rainy-night-prometheus/ --headless --quit` exits with code 0
- [ ] `git ls-files -s` shows `120000` mode for all symlinks
- [ ] Required directories all exist and are non-empty (via `.gitkeep` or actual files)
- [ ] `project.godot` has `config/name="Rainy Night Prometheus"`
- [ ] All 5 autoload entries in `project.godot` point to `res://gdscripts/` paths
- [ ] `README.md` documents the project purpose and setup steps
