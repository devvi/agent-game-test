# Game autoload 锚点（#572）

> 落盘依据：PR #599（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/572-scaffold-main-entry.md` §2.3。
> 最小单例：版本号 + constants 预加载，作为后续系统（输入/战斗/音频）的统一注册锚点。

## 1. 设计意图

骨架期无 autoload 注册约定，后续 #573 输入控制器、战斗/音频管理器等单例无统一挂载点。本文件建立 **Game 最小锚点**：不堆职责，只做两件事——持有版本号、预加载 constants（供 #573 等后续系统挂接）。

## 2. 类定义与注册

文件：`shandong-wolf/gdscripts/game.gd`（类名 `Game`，extends Node —— autoload 必须 Node）。

```gdscript
const WolfConstants = preload("res://gdscripts/constants.gd")
var game_version: String = WolfConstants.GAME_VERSION
```

注册（`shandong-wolf/project.godot` 新增 `[autoload]` 段，不动 `[application]`/`[display]`）：

```ini
[autoload]
Game="*res://gdscripts/game.gd"
```

`*res://` 前缀是 autoload 必需格式（漏前缀会导致编译检查失败，PRD §5.2-4）。

## 3. 启动链数据流

```
godot --path shandong-wolf/
  ├─ 引擎启动 → project.godot [autoload] 段 → Game 单例初始化（preload constants → game_version=v0.1.0）
  ├─ run/main_scene="res://scenes/Main.tscn" → 实例化（纯声明式 UI，零脚本）
  └─ 首帧渲染: TitleLabel「山东抗日之狼」+ SubtitleLabel + VersionLabel v0.1.0 + PostMergeProbeLabel
```

关键点：autoload 初始化早于主场景 `_ready`（引擎启动即加载）；constants 用 **preload 编译期静态引用**，无初始化顺序问题（PRD §5.2-3）；Game 不引用其他未注册单例。

## 4. 集成点

| Integration | Target Issue | How | Status |
|-------------|:---:|-----|:---:|
| 输入控制器挂接 | #573 | 注册到 Game（autoload 段 Game 之后追加） | ⬜ pending |
| 后续系统（战斗/音频） | #575/#578 | 统一挂接于 Game 锚点 | ⬜ pending |

## 5. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #572 | 逻辑地基（本文件所属） | 已合并（#599） |
