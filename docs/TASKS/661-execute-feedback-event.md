# Tasks: [Bug] 打击反馈 execute 事件缺失（E2E 截图链路修复）

> **Parent Issue:** #661
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **参考:** docs/DESIGN/661-execute-feedback-event.md（§7 实现阶段细化）

---

## Phase 1: resolve_plan.py — 契约扩展（P0，先锁契约）

- [ ] Task 1 (`scripts/e2e/resolve_plan.py`): `_GROUP_PROMOTED` 元组尾部追加 `"autoplay"`（组级 autoplay 覆盖顶层，first-wins，与 #673 main_scene 提升同构）
- [ ] Task 2 (`scripts/e2e/resolve_plan.py`): `resolve()` 新增 `scene_groups` 输出 —— 遍历激活组，shots 按组级 `main_scene`（缺省 = 顶层）归类为 `{main_scene: [shot, ...]}`；保留单值 `main_scene`/`shots` 输出与 `groups_activated`

## Phase 2: test_e2e_resolve.py — 回归断言（P0，TDD 先写）

- [ ] Task 3 (`tests/pipeline/test_e2e_resolve.py`): 新增 TestGroupAutoplayPromotion —— A1 组级 autoplay 提升 / A2 first-wins / A3 无 autoplay 组顶层透传
- [ ] Task 4 (`tests/pipeline/test_e2e_resolve.py`): 新增 TestSceneGroups —— B1 单场景 1 key / B2 snow_night+feedback 双场景拆分 / B3 同场景合并去重 / B4 单值输出向后兼容
- [ ] Task 5: 运行 `python3 -m unittest discover -s tests/pipeline -v` 确认新增断言先红（契约未实现）→ 实现后全绿

## Phase 3: run-e2e-review.sh — 多场景拆分（P0）

- [ ] Task 6 (`scripts/run-e2e-review.sh`): P5 段 resolve 之后读取 `scene_groups`；SCENE_COUNT<=1 走原路径（行为不变）；>1 时生成 sub-plan（每组独立 `main_scene`/`shots`/`out_dir`）并逐次调用 capture（每场景一个 godot 进程）
- [ ] Task 7 (`scripts/run-e2e-review.sh`): 产物合并到 `$OUT/shots/`（shot name 天然去重）；analyze_bmp 4 重防伪断言对合并集运行；failed_shots 上报不静默跳过

## Phase 4: e2e_shots.json — fb 冻结帧接线（P0）

- [ ] Task 8 (`shandong-wolf/e2e_shots.json`): feedback 组声明 `autoplay`：`tweaks: [{node: /root/CaptureRig, prop: freeze_effects, value: true}, {node: /root/CaptureRig, prop: auto_cycle_frames, value: 200}]`（DESIGN 579 §2.6 契约 + settle 不跨态）

## Phase 5: E2E 复验（P1，AC5 验收）

- [ ] Task 9: 以 `gdscripts/reaction_controller.gd` 为 diff 运行 `scripts/run-e2e-review.sh`（L3 visual 层）—— fb_execute.png 经 analyze_bmp 防伪断言（火花/刀光非空、非纯对峙帧）
- [ ] Task 10: 检查 results.json 各 fb shot state 与期望一致（settle 不跨态验证）；截图提交用户裁决（AC6，agent 不评星）

## Phase 6: 可选 — 真实 SwordArc 端到端单测（P2）

- [ ] Task 11 (`shandong-wolf/tests/test_reaction_controller.gd`, 可选): 真实 ReactionController + StickFigure + SwordArc 实例 → `trigger_feedback("execute", {target_entity})` → `arc.trigger_burst()` 被调用断言

---

## 前置依赖

- [ ] **PR #673（#586 implement）合并** —— main_scene 提升 + 数字 state 直比是本设计地基；worktree-commit.sh 的 merge main 自动处理；若 #673 未合并则实现期需先合入其 resolve_plan.py / e2e_capture.gd 改动

## 红线（照 DESIGN §10）

- 绝不触碰 `shandong-wolf/gdscripts/` 战斗代码；不碰 `scenes/e2e_feedback_capture.tscn`（#662）；不写可运行测试文件（本 TASKS 是 checklist，测试代码归 implement agent）
