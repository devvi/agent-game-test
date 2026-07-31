#!/usr/bin/env python3
"""create-issues.py — Create GitHub Issues from a game-to-issues plan JSON.

Usage:
  python3 scripts/create-issues.py docs/RAW/game-to-issues-{slug}.json [--repo owner/name]

Behavior (fixed 2026-07-31):
  - Resolves target repo: --repo > game-env/manifest.yaml project.repo > git remote > fallback
  - Topological sort: dependencies created first so body can reference real #N
  - JSON plan `dependencies` are SEQUENTIAL ids (1-N), NOT GitHub numbers.
    They are mapped to real GitHub issue numbers before writing the body.
  - Writes back github_number per issue and meta.status='created'.
  - Exits 1 on dependency cycle or gh failure (no partial silent failure).
"""
import json
import os
import re
import subprocess
import sys


def resolve_repo(cli_repo=None):
    if cli_repo:
        return cli_repo
    # 基于 cwd 的绝对路径（mock os.getcwd 即可测试）
    mf = os.path.join(os.getcwd(), "game-env", "manifest.yaml")
    if os.path.exists(mf):
        repo = _read_manifest_repo(mf)
        if repo:
            return repo
    out = subprocess.run(["git", "remote", "get-url", "origin"],
                         capture_output=True, text=True).stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", out)
    return m.group(1) if m else "devvi/agent-game-test"


def _read_manifest_repo(mf):
    """Read project.repo from manifest.yaml WITHOUT requiring pyyaml.
    yaml.safe_load would be ideal but system Python may lack the module;
    a line-based parse of `project:` + `  repo: <val>` covers the manifest
    we generate (simple 2-space-indented YAML)."""
    try:
        import yaml
        return yaml.safe_load(open(mf)).get("project", {}).get("repo")
    except ImportError:
        try:
            with open(mf) as f:
                in_project = False
                for line in f:
                    stripped = line.strip()
                    if stripped == "project:":
                        in_project = True
                        continue
                    if in_project and re.match(r"^[a-z]", line):
                        break  # left project block
                    if in_project and stripped.startswith("repo:"):
                        return stripped.split(":", 1)[1].strip().strip("\"'")
        except OSError:
            pass
    except Exception:
        pass
    return None


def topo_sort(issues):
    by_id = {i["id"]: i for i in issues}
    ordered, visited, visiting = [], set(), set()

    def visit(i):
        if i["id"] in visited:
            return
        if i["id"] in visiting:
            raise RuntimeError(f"依赖循环: issue {i['id']}")
        visiting.add(i["id"])
        for d in i.get("dependencies", []):
            if d in by_id:
                visit(by_id[d])
        visiting.discard(i["id"])
        visited.add(i["id"])
        ordered.append(i)

    for i in issues:
        visit(i)
    return ordered


def main():
    if len(sys.argv) < 2:
        print("❌ Usage: create-issues.py <plan.json> [--repo owner/name]", file=sys.stderr)
        sys.exit(2)
    plan_file = sys.argv[1]
    cli_repo = None
    if "--repo" in sys.argv:
        cli_repo = sys.argv[sys.argv.index("--repo") + 1]

    repo = resolve_repo(cli_repo)
    print(f"📦 目标仓库: {repo}")

    with open(plan_file) as f:
        data = json.load(f)
    issues = data["issues"]

    try:
        ordered = topo_sort(issues)
    except RuntimeError as e:
        print(f"❌ {e} — 请先修复依赖图", file=sys.stderr)
        sys.exit(1)

    id2number = {}
    for issue in ordered:
        labels = list(issue["labels"])
        milestone = issue.get("milestone", "full")
        labels.append(f"version/{milestone}")

        body = (
            f"## 功能描述\n{issue['description']}\n\n"
            f"## 上下文\n{issue['context']}\n\n"
            f"## 版本\n{milestone}\n\n"
            f"## 验收条件\n"
            + "\n".join(f"- [ ] {ac}" for ac in issue["acceptance_criteria"])
        )
        deps = issue.get("dependencies", [])
        if deps:
            dep_numbers = [id2number[d] for d in deps if d in id2number]
            if dep_numbers:
                body += f"\n\n## 前置依赖\n{', '.join(f'#{n}' for n in dep_numbers)}"

        result = subprocess.run([
            "gh", "issue", "create",
            "--repo", repo,
            "--title", issue["title"],
            "--label", ",".join(labels),
            "--body", body,
        ], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"❌ 创建失败: {issue['title']} — {result.stderr.strip()}", file=sys.stderr)
            sys.exit(1)
        number = int(result.stdout.strip().rstrip("/").split("/")[-1])
        id2number[issue["id"]] = number
        issue["github_number"] = number
        print(f"✅ #{number} {issue['title']}")

    data["meta"]["status"] = "created"
    with open(plan_file, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"✅ 共创建 {len(ordered)} 个 Issue → {repo}")


if __name__ == "__main__":
    main()
