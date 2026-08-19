# Project Board GraphQL ID Discovery

> When syncing the project board post-merge, the GraphQL mutation requires the project's
> **GraphQL node ID** (e.g. `PVT_kwHOABFv7s4Bd7mL`), not the project number from
> `gh project list`.

## Problem

`gh project list` returns a project number:

```
$ gh project list --owner '@me' --format json
5: mini pong
4: Perfect Dev Agent Workflow
```

But the GraphQL mutation `addProjectV2ItemById` requires the project's **global node ID**,
which is a different opaque string. Using the project number directly in the mutation
fails with:

```
Could not resolve to a node with the global id of 'PVT_...'.
```

## Solution

Resolve the project number to the GraphQL node ID with a separate query:

```bash
# Resolve project number → GraphQL node ID
gh api graphql -f query='
  query($owner:String!,$number:Int!) {
    user(login:$owner) {
      projectV2(number:$number) {
        id
        title
      }
    }
  }' -f owner="devvi" -F number=5
```

This returns:
```json
{"data":{"user":{"projectV2":{"id":"PVT_kwHOABFv7s4Bd7mL","title":"mini pong"}}}}
```

Use `projectV2.id` in all subsequent GraphQL mutations (`addProjectV2ItemById`,
`updateProjectV2ItemFieldValue`, etc.).

## Full Workflow

```bash
# 1. Find project number
PROJECT_NUM=$(gh project list --owner '@me' --format json | python3 -c "
import json,sys
data=json.load(sys.stdin)
for p in data: print(p['number'])
")

# 2. Resolve GraphQL ID
PROJECT_ID=$(gh api graphql -f query='
  query($o:String!,$n:Int!){user(login:$o){projectV2(number:$n){id}}}' \
  -f o="devvi" -F n=$PROJECT_NUM --jq '.data.user.projectV2.id')

# 3. Use PROJECT_ID in mutations
gh api graphql -f query='
  mutation($p:ID!,$c:ID!) {
    addProjectV2ItemById(input:{projectId:$p,contentId:$c}) { item { id } }
  }' -f project="$PROJECT_ID" -f content="$ISSUE_NODE_ID"
```

## Field ID Discovery

Similarly, field IDs (for Status, Stage, etc.) are GraphQL opaque IDs, not names:

```bash
# List all single-select fields with their GraphQL IDs and option IDs
gh project field-list $PROJECT_NUM --owner '@me' --format json | python3 -c "
import json,sys
data=json.load(sys.stdin)
for f in data['fields']:
    if f['type'] == 'ProjectV2SingleSelectField':
        print(f\"{f['name']} (id={f['id']})\")
        for o in f.get('options', []):
            print(f\"  {o['name']} (id={o['id']})\")
"
```

Use the discovered field IDs and option IDs in `updateProjectV2ItemFieldValue` mutations.

## Why Not `project item-edit`?

`gh project item-edit --field Status --single-select "Done"` uses the CLI's field-name
resolution, which is simpler. But it can fail when the project uses non-standard
field structures. The raw GraphQL path always works and gives you full control over
field IDs and option IDs.
