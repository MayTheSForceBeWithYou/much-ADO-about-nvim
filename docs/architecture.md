# Architecture

This document describes the high-level architecture of much-ADO-about-nvim.

## Design Principles

1. **Separation of Concerns**: UI code never calls HTTP directly. API code never manipulates buffers.
2. **Centralized State**: All shared data flows through the state module.
3. **Async Safety**: One request at a time, with stale response gating.
4. **In-Memory Only**: No disk persistence; state resets on plugin reload.

## Module Overview

```
lua/ado/
├── init.lua          # Plugin entry point, coordinates modules
├── config.lua        # Configuration management
├── state.lua         # Centralized state store
├── api.lua           # Azure DevOps REST client
├── requests.lua      # Async orchestration layer
└── ui/
    ├── layout.lua        # Window/split management
    ├── list.lua          # List pane rendering
    ├── detail.lua        # Detail pane rendering
    └── project_picker.lua # Project selection UI
```

### Module Responsibilities

#### `init.lua`
- Exposes `setup()` for user configuration
- Exposes `open()` as the main entry point
- Validates environment before opening UI
- Routes to appropriate UI based on surface (workitems, prs, etc.)

#### `config.lua`
- Stores default configuration values
- Merges user overrides via `setup()`
- Provides `get()` and `get_value()` accessors

#### `state.lua`
- Single source of truth for runtime state
- Stores: org URL, project, work items, selected item, loading state
- Manages request sequence IDs for stale gating
- Future: reactive subscriptions for UI updates

#### `api.lua`
- Wraps Azure DevOps REST API calls
- Uses `curl` via `vim.system()` for HTTP transport
- Builds URLs, headers, and handles JSON encoding
- Includes timeout handling (30s) and response size limits (10MB)
- Parses HTTP status codes and curl errors into user-friendly messages
- **Never touches UI** - only returns data via callbacks

#### `requests.lua`
- Orchestrates async requests with stale gating
- Ensures one request at a time
- Updates state after successful responses
- Provides high-level operations: `load_projects()`, `load_work_items()`

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
└─────────────────────────────┬───────────────────────────────┘
                              │ calls
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        api.lua                              │
│                                                             │
│  • Executes HTTP via curl                                   │
│  • Parses JSON responses                                    │
│  • Returns data via callbacks                               │
│  • NEVER touches buffers/windows                            │
└─────────────────────────────┬───────────────────────────────┘
                              │ writes
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       state.lua                             │
│                                                             │
│  • Central data store                                       │
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

api.request(..., function(err, result)
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

1. Create `lua/ado/ui/pr_list.lua` and `lua/ado/ui/pr_detail.lua`
2. Add API methods in `api.lua` for PR endpoints
3. Add request orchestrators in `requests.lua`
4. Add state fields in `state.lua`
5. Add routing in `init.lua._open_surface()`
6. Add layout support in `layout.lua`

See [Development Guide](development.md) for detailed instructions.
