# Architecture

This document describes the high-level architecture of much-ADO-about-nvim.

## Design Principles

1. **Separation of Concerns**: UI code never calls HTTP directly. SDK code never manipulates buffers.
2. **Centralized State**: All shared data flows through the state module.
3. **Async Safety**: One request at a time, with stale response gating.
4. **In-Memory Only**: No disk persistence; state resets on plugin reload.
5. **SDK Independence**: Azure DevOps REST logic lives in **ADO_Lua_SDK** (external dependency). Plugin acts as thin orchestration + UI.

## Module Overview

```
much-ADO-about-nvim/
├── lua/ado/
│   ├── init.lua          # Plugin entry point, coordinates modules
│   ├── ado_client.lua    # Centralized SDK connection creation (org, PAT, opts)
│   ├── config.lua        # Configuration management
│   ├── state.lua         # Centralized state store
│   ├── requests.lua      # Async orchestration layer (stale gating)
│   └── ui/
│       # ... (layout, list, detail, pickers, etc.)
│
ADO_Lua_SDK/              # External dependency (local path or ADO_SDK_PATH)
└── lua/ado/sdk/
    ├── init.lua          # Connection factory (WebApi equivalent)
    ├── interfaces.lua    # LuaCATS type annotations
    ├── auth/             # PAT handler
    ├── http/             # RestClient (curl + vim.system), errors
    └── api/              # CoreApi, WorkItemTrackingApi, IdentityApi, PipelinesApi
```

**ADO_Lua_SDK** provides all Azure DevOps REST interaction. The plugin never calls HTTP directly.

### Module Responsibilities

#### `init.lua`
- Exposes `setup()` for user configuration
- Exposes `open()` as the main entry point
- Validates environment before opening UI
- Creates SDK connection and stores it in state
- Routes to appropriate UI based on surface (workitems, prs, etc.)

#### `config.lua`
- Stores default configuration values
- Merges user overrides via `setup()`
- Provides `get()` and `get_value()` accessors

#### `state.lua`
- Single source of truth for runtime state
- Stores: org URL, project, work items, selected item, SDK connection, loading state
- Manages request sequence IDs for stale gating
- Future: reactive subscriptions for UI updates

#### `requests.lua`
- Orchestrates async requests with stale gating
- Ensures one request at a time
- Reads SDK connection from state and calls SDK methods
- Updates state after successful responses
- Provides high-level operations: `load_projects()`, `load_work_items()`

#### `ado_client.lua` (SDK initialization)

Centralizes creation of the Azure DevOps connection. All org URL, PAT, and SDK options flow through here. Uses the external **ADO_Lua_SDK** package.

```lua
local conn = ado_client.create_connection(org_url, pat, { log = require('ado.log') })
```

#### ADO_Lua_SDK (External dependency)

The SDK is a standalone package at `../ADO_Lua_SDK` (or `ADO_SDK_PATH`). It is modeled after [azure-devops-node-api](https://github.com/microsoft/azure-devops-node-api) and has zero dependency on the plugin. Provides: Connection factory, PAT auth, RestClient (curl + vim.system), CoreApi, WorkItemTrackingApi, IdentityApi, PipelinesApi.

#### `ui/layout.lua`
- Creates and manages the split layout
- Owns window and buffer IDs
- Sets up common keybindings
- Provides accessors for other UI modules

#### `ui/list.lua`
- Renders work items in the list pane
- Handles cursor movement and selection
- Updates detail pane on selection change

#### `ui/detail.lua`
- Renders selected work item details
- Formats and displays work item fields

#### `ui/project_picker.lua`
- Floating window for project selection
- Used when `ADO_PROJECT` is not set
- Calls back with selected project name

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        User Action                          │
│                    (keypress, command)                      │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         UI Module                           │
│              (layout, list, detail, picker)                 │
│                                                             │
│  • Interprets user input                                    │
│  • Reads from state                                         │
│  • Renders to buffers                                       │
│  • NEVER calls HTTP directly                                │
└─────────────────────────────┬───────────────────────────────┘
                              │ calls
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      requests.lua                           │
│                                                             │
│  • Orchestrates async operations                            │
│  • Manages stale request gating                             │
│  • Updates state on success                                 │
│  • Converts SDK ApiError → string at boundary               │
└─────────────────────────────┬───────────────────────────────┘
                              │ calls
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    SDK (ado.sdk)                             │
│                                                             │
│  ┌──────────────┐  ┌──────────────────────────────────┐     │
│  │  Connection   │→│  CoreApi / WorkItemTrackingApi    │     │
│  │  (factory)    │  │  (domain methods)                │     │
│  └──────────────┘  └──────────────┬───────────────────┘     │
│                                   │                         │
│                    ┌──────────────▼───────────────────┐     │
│                    │  RestClient (HTTP transport)      │     │
│                    │  curl + vim.system() + errors     │     │
│                    └──────────────┬───────────────────┘     │
│                                   │                         │
│                    ┌──────────────▼───────────────────┐     │
│                    │  AuthHandler (PAT / Bearer)       │     │
│                    └─────────────────────────────────┘     │
│                                                             │
│  • NEVER touches buffers/windows                            │
│  • NEVER reads from plugin state                            │
│  • Returns data via callbacks                               │
│  • Returns structured ApiError on failure                   │
└─────────────────────────────┬───────────────────────────────┘
                              │ writes
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       state.lua                             │
│                                                             │
│  • Central data store                                       │
│  • SDK connection instance                                  │
│  • Request sequence tracking                                │
│  • Loading state                                            │
└─────────────────────────────┬───────────────────────────────┘
                              │ triggers re-render
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         UI Module                           │
│                    (reads updated state)                    │
└─────────────────────────────────────────────────────────────┘
```

## Async Request Gating

To prevent race conditions and stale data:

1. **Sequence IDs**: Each request gets a unique sequence number from state
2. **One at a Time**: New requests are blocked while one is in progress
3. **Stale Check**: When a response arrives, verify its sequence ID is current
4. **Discard Stale**: If sequence ID doesn't match, silently discard the response

```lua
-- Simplified flow
local seq = state.next_request_seq()
state.set_loading(true)

local wit = state.get('connection'):get_work_item_tracking_api()
wit:get_work_items(ids, project, function(err, result)
  state.set_loading(false)

  if not state.is_current_seq(seq) then
    return  -- Stale, ignore
  end

  -- Safe to use result
  state.set('work_items', result)
  ui.render()
end)
```

## Adding New Surfaces

To add a new ADO surface (e.g., Pull Requests):

1. Add a new SDK API client in **ADO_Lua_SDK** (e.g. `api/git_api.lua`) and expose it via Connection
2. Create `lua/ado/ui/pr_list.lua` and `lua/ado/ui/pr_detail.lua`
3. Add request orchestrators in `requests.lua`
4. Add state fields in `state.lua`
5. Add routing in `init.lua._open_surface()`
6. Add layout support in `layout.lua`

See [Development Guide](development.md) for detailed instructions.
