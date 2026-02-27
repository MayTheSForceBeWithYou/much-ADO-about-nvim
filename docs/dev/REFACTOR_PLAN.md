# Refactor Plan — Migrate much-ADO-about-nvim to ADO Lua SDK

## Goal

Replace all direct HTTP calls in the plugin with calls to the ADO Lua SDK
(`/home/n8/dev/Lua/ADO_Lua_SDK`), keeping UI behavior unchanged and never blocking
the Neovim event loop.

---

## Current commands / endpoints

| requests.lua function | Old SDK call | ADO Lua SDK equivalent | Status |
|-----------------------|-------------|------------------------|--------|
| `load_projects` | `conn:get_core_api():get_projects(cb)` | `client.projects:list({}, opts)` → `res.data.value` | ✅ **Done** |
| `load_teams` | `conn:get_core_api():get_teams(project, opts, cb)` | `client.projects:list_teams(project, params, opts)` → `res.data.value` | ⬜ |
| `load_team_members` | `conn:get_core_api():get_team_members(project, team_id, cb)` | `client.projects:list_team_members(project, team_id, {}, opts)` → `res.data.value` | ⬜ |
| `load_work_items` (WIQL) | `wit:query_by_wiql(wiql, project, cb)` | `client.work_items:run_wiql(wiql, {project=p}, opts)` → `res.data.workItems` | ⬜ |
| `load_work_items` (batch) | `wit:get_work_items(ids, project, cb)` | `client.work_items:get_batch(ids, {project=p}, opts)` → `res.data.value` | ⬜ |
| `load_states_for_wit` | `wit:get_work_item_type_states(type, project, cb)` | `client.work_items:get_type_states(type, {project=p}, opts)` → `res.data.value` | ⬜ |
| `ensure_layout` (WIT type) | `wit:get_work_item_type(type, project, cb)` | `client.work_items:get_type(type, {project=p}, opts)` → `res.data` | ⬜ |
| `update_state` | `wit:update_work_item(id, project, patch, cb)` | `client.work_items:update(id, patch, {project=p}, opts)` | ⬜ |
| `update_assignee` | `wit:update_work_item(id, project, patch, cb)` | `client.work_items:update(id, patch, {project=p}, opts)` | ⬜ |
| `search_identities` | `conn:get_identity_api():search(query, cb)` | `client.identity:search(query, {}, opts)` → `res.data.identities` | ⬜ |

---

## Migration order (easy → hard)

### Phase 1 — Core / projects (done in kickoff)
1. ✅ `load_projects` — simplest GET, no project scoping

### Phase 2 — Teams (low risk, same pattern)
2. `load_teams` — GET with `$mine` param; maps to `client.projects:list_teams()`
   - Response shape: `res.data.value` (array of team objects)
   - Note: SDK uses `params["$mine"] = true`; old SDK used `opts.mine = true`
3. `load_team_members` — GET per-team; called in a loop with pending counter
   - Pattern unchanged; just swap the inner API call

### Phase 3 — Work items (core data path)
4. `load_work_items` (WIQL + batch) — two sequential async calls
   - WIQL → `client.work_items:run_wiql(wiql, {project=p}, opts)` → `res.data.workItems`
   - Batch → `client.work_items:get_batch(ids, {project=p}, opts)` → `res.data.value`
5. `ensure_layout` — GET WIT type; parses `xmlForm` from `res.data.xmlForm`

### Phase 4 — Mutations
6. `update_state` — PATCH; Content-Type `application/json-patch+json` must be in headers
   - SDK's `work_items:update()` sets this automatically ✓
7. `update_assignee` — same PATCH pattern

### Phase 5 — Identity
8. `search_identities` — GET against vssps; SDK handles URL rewrite automatically

---

## Response shape mapping

| Old SDK callback arg | ADO Lua SDK `res` field |
|----------------------|-------------------------|
| `projects` (array) | `res.data.value` |
| `teams` (array) | `res.data.value` |
| `team_members` (array) | `res.data.value` |
| `refs` from WIQL (array of `{id,url}`) | `res.data.workItems` |
| `work_items` (array) | `res.data.value` |
| `state_names` (array of strings) | `res.data.value[i].name` |
| `wit_def` with `xmlForm` | `res.data.xmlForm` |
| `updated` work item | `res.data` |
| `identities` (array) | `res.data.identities` |

---

## Callback convention difference

| | Old SDK | ADO Lua SDK |
|-|---------|-------------|
| Argument order | `callback(err, result)` | `opts.callback(res, err)` |
| Error object | `err.message` (string-like) | `err.message`, `err.type`, `err.status` |
| Result | value directly (array/table) | wrapped in `res.data.*` |

Adapter pattern used in `load_projects` and should be reused for all migrations:

```lua
ado_client.DOMAIN:METHOD(params, {
  callback = function(res, err)
    if err then cb(err.message, nil) return end
    cb(nil, res.data and res.data.VALUE_KEY or {})
  end,
})
```

---

## Cleanup after full migration

Once all functions are migrated:
- Remove `state.connection` and its initialization in `lua/ado/init.lua`
- Delete `lua/ado/sdk/` (old mini-SDK: http/, auth/, api/)
- Remove `require('ado.sdk')` from `lua/ado/init.lua`
- Consider calling `require('ado.ado_client').reset()` in `initialize()` so the client
  picks up env-var changes when the user re-opens the plugin

---

## Notes

- The `load_team_members` function uses a parallel pending-counter pattern (fires
  N concurrent requests). This is already async-safe; just swap the API calls.
- `ensure_layout` is fire-and-forget (errors are silent). Keep that behavior.
- `load_states_for_wit` bypasses `M.execute()` (no stale gating). Keep that too.
- `search_identities` also bypasses `M.execute()`. Keep.
