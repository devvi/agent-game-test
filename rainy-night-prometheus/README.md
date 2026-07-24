# Rainy Night Prometheus

A narrative-driven CRPG set in a rainy nightscape.

## Getting Started

### Prerequisites
- Godot 4.7.1
- Git with symlink support

### Clone & Run

```bash
git clone <repo-url>
cd agent-game-test
godot --path rainy-night-prometheus/ --headless --quit
```

To open in the Godot editor:
```bash
godot --path rainy-night-prometheus/ --editor
```

### Project Structure

- `project.godot` — Independent Godot project configuration
- `gdscripts/` — Symlinks to shared CRPG scripts from `urban-night-walker` (root project)
- `scenes/` — Rainy Night Prometheus scene files
- `dialogues/json/` — Dialogue JSON files
- `assets/` — Materials, audio, and icon resources
- `tests/` — Test scripts

### Symlinks & Cross-Project Script Sharing

This project reuses 6 core scripts from `urban-night-walker` via symlinks:
- `dialogue_runner.gd`, `dialogue_parser.gd`, `state_system.gd`
- `scene_manager.gd`, `scene_base.gd`, `constants.gd`

**Windows users:** Enable symlink support before cloning:
```bash
git config --global core.symlinks true
```

### Verification

```bash
godot --path rainy-night-prometheus/ --headless --quit
# Expected: exit code 0, no errors
```

## License

Same as parent repository.
