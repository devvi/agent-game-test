#!/usr/bin/env python3
"""verify-plan.py — programmatic Completeness Gate (C1-C6) checker for game-to-issues plans.

Born from the 2026-07-31 self-drill: eyeballing the gate missed a C5.5
orphan-component false positive and a vague acceptance criterion. Run this
BEFORE showing the plan to the user — it makes C1-C6 mechanical.

Usage:
  python3 scripts/verify-plan.py docs/RAW/game-to-issues-{slug}.json
  python3 scripts/verify-plan.py <plan.json> --path-map "开场:2,顾客A:7,结算:10"

Exit code 1 on any gate failure; prints each gate result.
"""
import json
import re
import sys


def load_plan(path):
    with open(path) as f:
        return json.load(f)


def check_json(plan):
    issues = plan.get("issues", [])
    ids = [i["id"] for i in issues]
    ok = plan.get("meta", {}).get("total_issues") == len(issues)
    ok = ok and len(ids) == len(set(ids))
    print(f"  C0 JSON/ids: {'✅' if ok else '❌'}")
    return ok


def check_dag(plan):
    edges = [(e["from"], e["to"]) for e in plan.get("dependency_graph", {}).get("edges", [])]
    nodes = set(n for e in edges for n in e)
    visited, stack = set(), set()
    cycle = False

    def has_cycle(n):
        nonlocal cycle
        if n in visited:
            return
        if n in stack:
            cycle = True
            return
        stack.add(n)
        for f, t in edges:
            if f == n:
                has_cycle(t)
        stack.discard(n)
        visited.add(n)

    for n in nodes:
        has_cycle(n)
    print(f"  C6 DAG: {'✅ acyclic' if not cycle else '❌ HAS CYCLE'}")
    return not cycle


def check_assembly_loop(plan):
    """C5.5: [Integration] assembly issue deps = all mvp FEATURE components;
    [Test] issue depends on assembly; no orphan feature components.
    Infrastructure (Scaffold/CI/data-model — not player-experienced) is exempt."""
    issues = plan.get("issues", [])
    asm = [i for i in issues if "[Integration]" in i["title"]]
    tests = [i for i in issues if "[Test]" in i["title"] or "[Playtest]" in i["title"]]
    ok = True
    if not asm:
        print("  C5.5: ❌ 无 [Integration] 组装 Issue")
        return False
    if not tests:
        print("  C5.5: ❌ 无 [Test] 端到端验证 Issue")
        return False

    a = asm[0]
    t = tests[0]
    # infrastructure = not directly player-experienced; taste-draft (v4) =
    # 品味内容(文案/数值/命名)由人定稿, 不进依赖链也不进组装 — 与基础设施同类豁免
    infra_markers = ("[Scaffold]", "CI", "骨架", "脚手架", "数据模型", "data model")
    mvp_ids = [i["id"] for i in issues if i.get("milestone") == "mvp"]
    feature_ids = [
        i["id"] for i in issues
        if i["id"] in mvp_ids and i["id"] != a["id"] and i["id"] != t["id"]
        and not any(m in i["title"] for m in infra_markers)
        and i.get("content_ownership") != "taste-draft"
    ]
    orphans = [cid for cid in feature_ids if cid not in a["dependencies"]]
    deps_ok = a["dependencies"] == sorted(set(a["dependencies"]))  # sanity, no dups
    test_dep_ok = t["dependencies"] == [a["id"]]

    print(f"  组装 #{a['id']} deps={sorted(a['dependencies'])}")
    print(f"  验证 #{t['id']} deps={t['dependencies']} (应为 [{a['id']}])")
    if orphans:
        print(f"  C5.5: ❌ 孤儿组件（不在组装 deps）: {orphans}")
        ok = False
    elif test_dep_ok:
        print("  C5.5: ✅ 组件→组装→验证 闭环完整（基础设施除外）")
    else:
        print(f"  C5.5: ❌ 验证 Issue 未依赖组装 ({t['dependencies']})")
        ok = False
    if not deps_ok:
        print("  C5.5: ❌ 组装 deps 含重复")
        ok = False
    return ok


def check_acceptance_quality(plan):
    """C4: flag vague acceptance criteria (short, or '好看/感觉/可发现' without specifics)."""
    vague = []
    for i in plan.get("issues", []):
        for ac in i.get("acceptance_criteria", []):
            if len(ac) < 8 or any(w in ac for w in ("好看", "感觉", "体验好")):
                vague.append(f"#{i['id']}: {ac}")
            if "可发现" in ac and "浅层" not in ac:
                vague.append(f"#{i['id']} 分层验收不可测: {ac}")
    print(f"  C4 验收可测性: {'✅' if not vague else '❌ ' + ' | '.join(vague)}")
    return not vague


def check_path_map(plan, path_map):
    """C1: each complete_path step maps to an existing issue id (--path-map '开场:2,结算:10')."""
    if not path_map:
        print("  C1 路径映射: ⏭️ 跳过（未提供 --path-map）")
        return True
    ids = {i["id"] for i in plan.get("issues", [])}
    missing = [step for step, iid in path_map.items() if iid not in ids]
    print(f"  C1 路径映射: {'✅' if not missing else '❌ 无此 Issue: ' + str(missing)}")
    return not missing


def main():
    if len(sys.argv) < 2:
        print("Usage: verify-plan.py <plan.json> [--path-map '开场:2,结算:10']")
        sys.exit(2)
    plan_path = sys.argv[1]
    path_map = {}
    if "--path-map" in sys.argv:
        raw = sys.argv[sys.argv.index("--path-map") + 1]
        for pair in raw.split(","):
            if ":" in pair:
                step, iid = pair.rsplit(":", 1)
                path_map[step.strip()] = int(iid)

    plan = load_plan(plan_path)
    print(f"验证: {plan_path} ({plan.get('meta', {}).get('title', '?')})")
    results = [
        check_json(plan),
        check_dag(plan),
        check_assembly_loop(plan),
        check_acceptance_quality(plan),
        check_path_map(plan, path_map),
    ]
    print("\n" + ("✅ ALL GATES PASS — 可进入用户确认" if all(results) else "❌ GATE FAILED — 返回 Step 2 补充 Issue"))
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
