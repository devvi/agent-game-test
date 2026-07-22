#!/usr/bin/env python3
"""Hemingway Writing Constraint Validator - CLI tool.

Validates dialogue JSON and GDScript files against domain-specific
Hemingway writing constraints (max sentences, max chars per sentence).
Supports --fix (auto-truncate), --report (markdown output), and --domain override.

Usage:
    python scripts/validate_hemingway.py                          # auto-discover files
    python scripts/validate_hemingway.py dialogues/bartender.json  # specific file(s)
    python scripts/validate_hemingway.py --fix                     # auto-fix violations
    python scripts/validate_hemingway.py --report review.md        # generate report
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

# Domain limits (must mirror GDScript DOMAIN_LIMITS)
RULES = {
    "narration":    {"max_sentences": 3, "max_chars": 25},
    "dialogue":     {"max_sentences": 1, "max_chars": 25},
    "signage":      {"max_sentences": 1, "max_chars": 15},
    "choice_text":  {"max_sentences": 1, "max_chars": 30},
    "echo_variant": {"max_sentences": 1, "max_chars": 25},
}
DEFAULT_DOMAIN = "narration"

SENTENCE_ENDS = {".", "!", "?"}
CJK_ENDS = {"。", "！", "？"}
ALL_ENDS = SENTENCE_ENDS | CJK_ENDS
CJK_RANGE = range(0x4E00, 0xA000)  # CJK Unified Ideographs


def split_sentences(text: str) -> list[str]:
    """Split text into sentences. Must mirror GDScript _split_sentences()."""
    sentences = []
    current = ""
    i = 0
    while i < len(text):
        current += text[i]
        ch = text[i]
        if ch in ALL_ENDS:
            # CJK delimiters split unconditionally; English require space/newline/EOS
            is_cjk = ch in CJK_ENDS
            is_end = False
            if is_cjk:
                is_end = True
            else:
                is_end = (i + 1 >= len(text) or text[i + 1] in (" ", "\n", "\t"))
            if is_end:
                sentences.append(current.strip())
                current = ""
                if i + 1 < len(text) and text[i + 1] == " ":
                    i += 1
        i += 1
    if current.strip():
        sentences.append(current.strip())
    return sentences


def has_cjk(text: str) -> bool:
    """Check if text contains CJK unified ideographs."""
    for ch in text:
        if ord(ch) in CJK_RANGE:
            return True
    return False


def truncate_sentence(sentence: str, max_chars: int) -> str:
    """Truncate a single sentence. Must mirror GDScript _truncate_sentence()."""
    if len(sentence) <= max_chars:
        return sentence
    stripped = sentence.rstrip(".!?。！？")
    if len(stripped) <= max_chars:
        return stripped + "…"
    truncated = stripped[:max_chars]
    if has_cjk(sentence):
        return truncated + "…"
    last_space = truncated.rfind(" ")
    if last_space > 0:
        truncated = truncated[:last_space]
    return truncated.strip() + "…"


def validate_text(text: str, domain: str) -> dict:
    """Validate a single text string against domain rules.
    Returns dict with violation info or empty dict if clean."""
    limits = RULES.get(domain, RULES[DEFAULT_DOMAIN])
    max_sent = limits["max_sentences"]
    max_chars = limits["max_chars"]

    sentences = split_sentences(text)
    violations = []

    # Check sentence count
    if len(sentences) > max_sent:
        violations.append({
            "type": "sentence_count",
            "actual": len(sentences),
            "limit": max_sent,
            "detail": f"{len(sentences)} sentences exceeds limit of {max_sent}",
        })

    # Check char count per sentence
    for idx, sent in enumerate(sentences):
        if len(sent) > max_chars:
            violations.append({
                "type": "char_count",
                "sentence_index": idx,
                "actual": len(sent),
                "limit": max_chars,
                "detail": f"Sentence {idx + 1}: {len(sent)} chars exceeds limit of {max_chars}: "
                          f"\"{sent[:30]}{'...' if len(sent) > 30 else ''}\"",
            })

    if violations:
        return {
            "text": text,
            "domain": domain,
            "violations": violations,
            "sentences": sentences,
            "was_truncated": True,
            "truncated_text": _apply_truncation(text, domain),
        }
    return {}


def _apply_truncation(text: str, domain: str) -> str:
    """Apply truncation rules (mirrors GDScript truncate() logic)."""
    limits = RULES.get(domain, RULES[DEFAULT_DOMAIN])
    max_sent = limits["max_sentences"]
    max_chars = limits["max_chars"]

    sentences = split_sentences(text)

    # Sentence limit first
    if len(sentences) > max_sent:
        sentences = sentences[:max_sent]
        having = sentences[-1].rstrip(".!?。！？") + "…"
        sentences[-1] = having

    # Char limit per sentence
    truncated = []
    for sent in sentences:
        truncated.append(truncate_sentence(sent, max_chars))

    result = ""
    for i, s in enumerate(truncated):
        if i > 0:
            result += " "
        result += s
    return result


def extract_texts(file_path: str) -> list[dict]:
    """Extract text strings from a file with their locations and domain hints.
    Returns list of dicts: {text, line, col, domain_hint}."""
    path = Path(file_path)
    ext = path.suffix.lower()

    try:
        content = path.read_text(encoding="utf-8")
    except Exception as e:
        return [{"error": f"Cannot read file: {e}", "line": 0, "col": 0}]

    if ext == ".json":
        return _extract_from_json(content, file_path)
    elif ext == ".gd":
        return _extract_from_gdscript(content, file_path)
    else:
        return [{"error": f"Unsupported file type: {ext}", "line": 0, "col": 0}]


def _extract_from_json(content: str, file_path: str) -> list[dict]:
    """Extract text fields from dialogue JSON."""
    results = []
    try:
        data = json.loads(content)
    except json.JSONDecodeError as e:
        return [{"error": f"JSON parse error: {e}", "line": e.lineno, "col": e.colno}]

    # Walk all nodes for "text" fields
    nodes = data.get("nodes", {}) if isinstance(data, dict) else {}
    for node_id, node in nodes.items():
        if not isinstance(node, dict):
            continue
        # Main node text
        if "text" in node and isinstance(node["text"], str):
            domain = node.get("domain", "dialogue")  # Default dialogue for JSON dialogue files
            line = _find_line_number(content, node["text"], node_id)
            results.append({
                "text": node["text"],
                "line": line,
                "col": 1,
                "domain_hint": domain,
                "node_id": node_id,
            })
        # Choice text
        for choice in node.get("choices", []):
            if isinstance(choice, dict) and "text" in choice and isinstance(choice["text"], str):
                line = _find_line_number(content, choice["text"], node_id)
                results.append({
                    "text": choice["text"],
                    "line": line,
                    "col": 1,
                    "domain_hint": "choice_text",
                    "node_id": node_id,
                })
    return results


def _find_line_number(content: str, text: str, node_id: str) -> int:
    """Approximate line number for a text within JSON content."""
    lines = content.split("\n")
    for i, line in enumerate(lines, 1):
        if text in line:
            return i
    # Fallback: find the node_id
    for i, line in enumerate(lines, 1):
        if f'"{node_id}"' in line:
            return i
    return 1


def _extract_from_gdscript(content: str, file_path: str) -> list[dict]:
    """Extract text assignments from GDScript files."""
    results = []
    lines = content.split("\n")
    # Match patterns like: text = "..."  or  .text = "..."
    pattern = re.compile(r'\.?\btext\s*=\s*"((?:[^"\\]|\\.)*)"')

    for i, line in enumerate(lines, 1):
        for match in pattern.finditer(line):
            text_val = match.group(1)
            if text_val.strip():
                results.append({
                    "text": text_val,
                    "line": i,
                    "col": match.start() + 1,
                    "domain_hint": "narration",  # Default for GDScript
                })
    return results


def default_domain_for_file(file_path: str) -> str:
    """Determine default domain based on file location."""
    path = Path(file_path)
    if "dialogues" in path.parts:
        return "dialogue"
    return DEFAULT_DOMAIN


def report_violations(violations: list, args) -> int:
    """Print violations and return exit code."""
    if not violations:
        print("All texts pass Hemingway constraints.")
        return 0

    print(f"\n{len(violations)} text(s) with violations:\n")
    for v in violations:
        print(f"  File: {v['file']}")
        print(f"  Line: {v['line']}")
        if v.get("node_id"):
            print(f"  Node: {v['node_id']}")
        print(f"  Domain: {v['domain']}")
        print(f"  Text: \"{v['text'][:60]}{'...' if len(v['text']) > 60 else ''}\"")
        for vi in v["violations"]:
            print(f"    {vi['detail']}")
        print()
    return 1


def generate_report(violations: list, output_path: str):
    """Generate a markdown report of violations."""
    lines = ["# Hemingway Writing Constraint Violations", ""]
    if not violations:
        lines.append("All texts pass Hemingway constraints.")
    else:
        lines.append(f"**{len(violations)} violation(s) found.**\n")
        for v in violations:
            lines.append(f"## File: `{v['file']}`")
            lines.append(f"- **Line:** {v['line']}")
            if v.get("node_id"):
                lines.append(f"- **Node:** `{v['node_id']}`")
            lines.append(f"- **Domain:** {v['domain']}")
            lines.append(f"- **Text:** `{v['text'][:80]}`")
            lines.append("")
            for vi in v["violations"]:
                lines.append(f"- {vi['detail']}")
            lines.append("")

    Path(output_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Report written to {output_path}")


def fix_violations(violations: list) -> int:
    """Apply --fix truncation to files with violations."""
    fixed_count = 0
    # Group by file
    by_file: dict[str, list] = {}
    for v in violations:
        by_file.setdefault(v["file"], []).append(v)

    for file_path, file_violations in by_file.items():
        path = Path(file_path)
        ext = path.suffix.lower()
        content = path.read_text(encoding="utf-8")

        if ext == ".json":
            data = json.loads(content)
            nodes = data.get("nodes", {})
            for v in file_violations:
                if v.get("node_id") and v["node_id"] in nodes:
                    node = nodes[v["node_id"]]
                    if node.get("text") == v["text"]:
                        node["text"] = _apply_truncation(v["text"], v["domain"])
                        fixed_count += 1
                    # Fix choices too
                    for choice in node.get("choices", []):
                        if isinstance(choice, dict) and choice.get("text") == v["text"]:
                            choice["text"] = _apply_truncation(v["text"], v["domain"])
                            fixed_count += 1
            path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        elif ext == ".gd":
            # For GDScript, replace text strings in-line
            for v in file_violations:
                old_text = v["text"]
                new_text = _apply_truncation(old_text, v["domain"])
                if old_text != new_text:
                    content = content.replace(f'"{old_text}"', f'"{new_text}"', 1)
                    fixed_count += 1
            path.write_text(content, encoding="utf-8")

    print(f"Fixed {fixed_count} violation(s) in-place.")
    return fixed_count


def auto_discover_files() -> list[str]:
    """Auto-discover dialogue JSON and GDScript files."""
    files = []
    for pattern in ["dialogues/*.json", "gdscripts/*.gd"]:
        matches = sorted(Path(".").glob(pattern))
        files.extend(str(m) for m in matches)
    return files


def main():
    parser = argparse.ArgumentParser(
        description="Hemingway Writing Constraint Validator",
    )
    parser.add_argument("files", nargs="*", help="Files to validate (default: auto-discover)")
    parser.add_argument("--fix", action="store_true", help="Auto-truncate violations in-place")
    parser.add_argument("--report", metavar="PATH", help="Generate markdown report at PATH")
    parser.add_argument("--domain", default=None, help="Override domain for all texts")
    args = parser.parse_args()

    files = args.files if args.files else auto_discover_files()
    if not files:
        print("No files found to validate.")
        sys.exit(0)

    all_violations = []
    for file_path in files:
        if not Path(file_path).exists():
            print(f"File not found: {file_path}")
            continue

        texts = extract_texts(file_path)

        for entry in texts:
            if "error" in entry:
                print(f"[{file_path}:{entry.get('line', 0)}] {entry['error']}")
                all_violations.append({
                    "file": file_path,
                    "line": entry.get("line", 0),
                    "text": f"[Error: {entry['error']}]",
                    "violations": [{"type": "error", "detail": entry["error"]}],
                    "domain": "error",
                })
                continue

            domain = args.domain or entry["domain_hint"] or default_domain_for_file(file_path)
            result = validate_text(entry["text"], domain)
            if result:
                all_violations.append({
                    "file": file_path,
                    "line": entry["line"],
                    "node_id": entry.get("node_id", ""),
                    "text": entry["text"],
                    "domain": domain,
                    "violations": result["violations"],
                })

    exit_code = report_violations(all_violations, args)

    if args.fix and all_violations:
        fix_violations(all_violations)

    if args.report:
        generate_report(all_violations, args.report)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
