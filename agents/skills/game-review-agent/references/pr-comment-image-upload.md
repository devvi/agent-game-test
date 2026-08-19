# Attaching Screenshots to a GitHub PR/Issue Comment (verified 2026-07-31)

Needed for the review-agent E2E evidence requirement: screenshots posted on the PR as
visual proof ("the game really renders and really plays").

## Verified: REST API has NO comment-attachment endpoint

Checked `github/rest-api-description` (api.github.com OpenAPI, 2026-07-31): zero POST
paths for issue/PR comment attachments; all "attachment" mentions are copilot-spaces
and repo-status fields. `gh pr comment` can only post text. Do not search for a REST
attachment endpoint again.

## Primary path: web upload endpoint (what the official UI drag-and-drop uses)

```bash
RESP=$(curl -s -H "Authorization: Bearer $GH_TOKEN" \
  https://github.com/upload/policies/assets \
  -F "name=shot.png" -F "content_type=image/png")
UPLOAD_URL=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['upload_url'])")
curl -s -X PUT --upload-file shot.png "$UPLOAD_URL"
# then reference https://github.com/user-attachments/files/<id>/<name>.png in the comment
```
Status: community-standard (used by many bots); NOT yet live-verified on this setup —
verify once at rollout (Phase 2 of docs/PLAN-e2e-verification-v2.md) before relying on it.

## Fallback: gist raw URL (official REST, always works)

```bash
GIST_URL=$(gh gist create --public /tmp/shot.png | tail -1)
# raw URL: https://gist.githubusercontent.com/<user>/<id>/raw/shot.png — renders inline
```
Public gist pollutes the gist list; prefer primary path.

## Anti-fake-evidence rule

Never post a black/unverified PNG as evidence. Every shot must pass the 4-fold assertion
first (non-black avg, distinct-color count, theme color if declared, frame-to-frame
luminance delta) — see godot-headless-testing skill "Visual Evidence" section.
Black = capture failed = fail-fast; a black image on a PR is a false-pass bug.
