# Manual Tests — ADO Lua SDK Migration (Kickoff)

Tests for the first migrated vertical slice: **project listing via the ADO Lua SDK**.

## Environment

```bash
export ADO_ORG_URL=https://dev.azure.com/YOUR_ORG
export ADO_PAT=YOUR_PAT_TOKEN
export ADO_LUA_SDK_DEV_PATH=/home/n8/dev/Lua/ADO_Lua_SDK

# Optional: skip project picker
export ADO_PROJECT=YourProject
```

## Test 1 — SDK client loads without error

```vim
:lua local c, err = require('ado.ado_client').get(); print(c and "SDK OK" or "FAIL: " .. tostring(err))
```

**Expected:** `SDK OK`

**Failure modes:**
- `ADO SDK not available` → `ADO_LUA_SDK_DEV_PATH` not set or Neovim not restarted
- `ado.client load error` → SDK path wrong or files missing
- `Auth error` → `ADO_PAT` empty or malformed

## Test 2 — Project picker shows real projects from the SDK

```vim
:Ado workitems
```

If `ADO_PROJECT` is not set, a project picker should appear.

**Expected:**
- Picker lists your organization's projects (same list as before the refactor)
- Select a project → moves on to team/area path selection → work items appear

**Signs of success:**
- No error notifications
- Project list matches what you see in `https://dev.azure.com/YOUR_ORG`

## Test 3 — Graceful error when PAT is missing

```bash
# Unset PAT in a separate test session
unset ADO_PAT
nvim
```

```vim
:Ado workitems
```

**Expected:** An error notification:
`ADO SDK unavailable: ADO_PAT not set`
(or the standard env-validation error from the plugin itself)

The plugin should NOT crash or show a Lua traceback.

## Test 4 — Graceful error when SDK path is not set

```bash
unset ADO_LUA_SDK_DEV_PATH
nvim
```

```vim
:Ado workitems
```

**Expected:** An error notification:
`ADO SDK unavailable: ADO SDK not available. Set ADO_LUA_SDK_DEV_PATH=...`

## Test 5 — Debug logging shows SDK path

```vim
" Enable debug in init/lazy config:
require("ado").setup({ debug = true })
:Ado workitems
```

**Expected in :messages:**
```
[ADO] load_projects: fetching via ADO Lua SDK
[ADO] load_projects: received N projects
```

(Look for `via ADO Lua SDK` to confirm the new path is active, not the old SDK.)

## What has NOT changed

- Team/area path selection — still uses old SDK (`state.connection`)
- Work item listing — still uses old SDK
- Work item detail / state edit / assignee update — still uses old SDK
- `:Ado help` and `:Ado controls` — unaffected

These will be migrated in subsequent sessions per `REFACTOR_PLAN.md`.
