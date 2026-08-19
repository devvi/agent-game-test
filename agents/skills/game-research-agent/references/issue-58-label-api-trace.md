# Issue #58 Session Trace — REST API Label Quirks

> Date: 2026-07-23
> Issue: 58 ([Scene] Store → Bridge → Underpass)
> PR: #99

## 1. `-f labels='["x"]'` returns 422

**Attempted command:**

```bash
gh api repos/$OWNER_REPO/issues/58/labels -X POST -f labels='["workflow/plan"]'
```

**Error response (HTTP 422):**

```json
{"message":"Invalid request.\n\nNo subschema in \"anyOf\" matched.\nFor 'anyOf/0', {\"labels\" => \"[\\\"workflow/plan\\\"]\"} is not an array.\nFor 'anyOf/1', {\"labels\" => \"[\\\"workflow/plan\\\"]\"} is not an array.\nFor 'properties/labels', \"[\\\"workflow/plan\\\"]\" is not an array."}
```

**Root cause:** `-f` flag serializes the value as a string, not a JSON array. The API expects `{"labels": ["workflow/plan"]}` — a JSON array, not a stringified array.

**Fix:** Pipe JSON body via `--input -`:

```bash
echo '{"labels":["workflow/plan"]}' | gh api repos/$OWNER_REPO/issues/58/labels -X POST --input -
```

This succeeds (returns 200 with full label list).

## 2. label DELETE returns 404 (harmless)

**Attempted command:**

```bash
gh api repos/$OWNER_REPO/issues/58/labels/workflow/research -X DELETE
```

**Error response (HTTP 404):**

```json
{"message":"Label does not exist"}
```

**Root cause:** After adding `workflow/plan`, the `workflow/research` label was no longer present — GitHub may have auto-removed it (only one workflow/* label is valid at a time in some setups).

**Fix:** Wrap in `2>/dev/null || true` to make it an idempotent cleanup attempt.

## 3. workflow-chain.yml auto-advance not firing

After squash-merging PR #99, the issue still had `workflow/research` and lacked `workflow/plan`. The workflow-chain.yml action may not trigger on `squash` merge events — only `merge` commits.

**Fix:** Always verify labels post-merge with:

```bash
gh issue view <N> --json labels | python3 -c "import json,sys; print([l['name'] for l in json.load(sys.stdin)['labels']])"
```

If `workflow/plan` is missing, use the REST API fallback (see §1 above).

## 4. `gh pr create` via GraphQL doesn't set labels

The PR created for Issue #58 (PR #99) had `[]` labels (empty) when stage-gate ran its check. The stage-gate auto-fixed it by adding `workflow/research`. This is expected — `gh pr create` creates the PR on GitHub but GraphQL mutations don't apply issue labels to PRs.
