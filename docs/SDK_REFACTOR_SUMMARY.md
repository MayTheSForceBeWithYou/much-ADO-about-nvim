# SDK Refactor Summary

This document summarizes the refactor that extracted Azure DevOps REST logic into an external **ADO_Lua_SDK** package.

## Goals Achieved

1. **Removed all direct HTTP logic from the plugin** – No more curl, vim.system, auth headers, or request-building inside the plugin.
2. **Replaced with ADO_Lua_SDK calls** – All Azure DevOps REST interactions go through the SDK.
3. **Plugin acts as**:
   - **UI layer** – Buffers, keymaps, rendering (unchanged)
   - **Command layer** – `:Ado workitems`, `:Ado pipelines`, etc. (unchanged)
   - **Thin orchestration layer** – `requests.lua` and `ado_client.lua` call the SDK; no HTTP in plugin code.

## Updated Plugin Structure

```
much-ADO-about-nvim/
├── plugin/ado.lua           # Adds SDK to rtp, defines :Ado command
├── lua/ado/
│   ├── init.lua             # Creates connection via ado_client
│   ├── ado_client.lua       # NEW: Centralized SDK initialization
│   ├── config.lua
│   ├── state.lua
│   ├── requests.lua        # Calls state.get('connection') → SDK methods
│   ├── cache.lua
│   ├── log.lua
│   └── ui/                  # Unchanged
└── (lua/ado/sdk/ REMOVED)
```

## New: ADO_Lua_SDK Package

Location: `../ADO_Lua_SDK` (sibling to this plugin) or `$ADO_SDK_PATH`.

```
ADO_Lua_SDK/
└── lua/ado/sdk/
    ├── init.lua             # Connection factory
    ├── interfaces.lua       # LuaCATS types
    ├── auth/pat_handler.lua
    ├── http/rest_client.lua # curl + vim.system
    ├── http/errors.lua
    └── api/
        ├── client_base.lua
        ├── core_api.lua
        ├── work_item_tracking_api.lua
        ├── identity_api.lua
        └── pipelines_api.lua
```

## Summary of Removed Duplicated Logic

| Removed from Plugin | Now In SDK |
|---------------------|------------|
| `lua/ado/sdk/` (entire tree) | `ADO_Lua_SDK/lua/ado/sdk/` |
| RestClient (curl, URL building, JSON) | `ado.sdk.http.rest_client` |
| Auth (PAT → Basic header) | `ado.sdk.auth.pat_handler` |
| CoreApi, WorkItemTrackingApi, IdentityApi, PipelinesApi | `ado.sdk.api.*` |
| Error factory (transport, http, parse, validation) | `ado.sdk.http.errors` |

## New SDK Methods Added

None. The refactor was a 1:1 extraction. All existing SDK methods are present in ADO_Lua_SDK:

- **CoreApi**: `get_projects`, `get_project`, `get_teams`, `get_team_members`
- **WorkItemTrackingApi**: `query_by_wiql`, `get_work_items`, `get_work_item`, `get_work_item_type`, `get_work_item_type_states`, `update_work_item`
- **IdentityApi**: `search`
- **PipelinesApi**: `list_pipelines`, `list_runs`, `get_run`

## SDK Client Initialization

**`lua/ado/ado_client.lua`** centralizes initialization:

```lua
-- Create connection with org URL, PAT, and optional log
local conn = ado_client.create_connection(org_url, pat, { log = require('ado.log') })
```

The plugin's `init.lua` calls this once during `initialize()` and stores the connection in state. All `requests.lua` and UI code read `state.get('connection')` and call SDK methods on it.

## Error Handling

Unchanged. SDK returns `ApiError` tables; `requests.lua` converts to strings at the boundary before notifying the user. Error types: `transport`, `http`, `parse`, `validation`.

## User-Facing Changes

- **Commands**: No change. `:Ado help`, `:Ado workitems`, `:Ado pipelines`, `:Ado controls` work as before.
- **UI**: No change.
- **Setup**: Users must ensure **ADO_Lua_SDK** is on the runtimepath. Options:
  1. Sibling directory `../ADO_Lua_SDK` (auto-detected)
  2. `ADO_SDK_PATH` env var
  3. lazy.nvim dependency: `{ dir = '/path/to/ADO_Lua_SDK', lazy = true }`

## Tests

- `tests/minimal_init.lua` prepends the SDK path so `require('ado.sdk')` resolves.
- SDK tests in `tests/ado/sdk/` load the external SDK (mocked rest client).
- Run tests with plenary installed; SDK path is resolved via `../ADO_Lua_SDK` or `ADO_SDK_PATH`.
