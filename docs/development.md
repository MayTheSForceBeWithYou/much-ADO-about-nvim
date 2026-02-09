# Development Guide

This document covers the project layout, how to extend the plugin, and debugging tips.

## Project Layout

```
much-ADO-about-nvim/
├── plugin/
│   └── ado.lua              # Plugin entrypoint, defines :Ado command
├── lua/
│   └── ado/
│       ├── init.lua         # Main module, coordinates everything
│       ├── config.lua       # Configuration defaults and merging
│       ├── state.lua        # Centralized in-memory state
│       ├── api.lua          # Azure DevOps REST client
│       ├── requests.lua     # Async request orchestration
│       └── ui/
│           ├── layout.lua       # Window/buffer management
│           ├── list.lua         # List pane rendering
│           ├── detail.lua       # Detail pane rendering
│           └── project_picker.lua # Project selection floating window
├── docs/
│   ├── architecture.md      # High-level architecture
│   ├── configuration.md     # Configuration reference
│   └── development.md       # This file
└── README.md
```

## Neovim Version Requirements

much-ADO-about-nvim requires **Neovim 0.10 or later**.

APIs used that require 0.10+:
- `vim.system()` for subprocess execution
- Floating window `title` and `title_pos` options
- `vim.base64.encode()` for PAT encoding

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/MayTheSForceBeWithYou/much-ADO-about-nvim.git
   cd much-ADO-about-nvim
   ```

2. Link to your Neovim packages:
   ```bash
   # For testing during development
   ln -s $(pwd) ~/.local/share/nvim/site/pack/dev/start/much-ADO-about-nvim
   ```

3. Set environment variables:
   ```bash
   export ADO_ORG_URL="https://dev.azure.com/your-org"
   export ADO_PAT="your-pat"
   export ADO_PROJECT="TestProject"
   ```

4. Reload Neovim and test:
   ```vim
   :Ado
   ```

## Adding a New ADO Surface

This guide walks through adding Pull Requests as a new surface.

### Step 1: Add State Fields

In `lua/ado/state.lua`, add fields for the new surface:

```lua
---@class AdoState
-- ... existing fields ...
---@field pull_requests table|nil List of pull requests
---@field selected_pr table|nil Currently selected PR
```

Update `M.reset()`:

```lua
function M.reset()
  state = {
    -- ... existing fields ...
    pull_requests = nil,
    selected_pr = nil,
  }
end
```

### Step 2: Add API Methods

In `lua/ado/api.lua`, add methods for the PR endpoints:

```lua
--- Fetch pull requests for a repository
---@param project string Project name
---@param repository string Repository name
---@param callback function Callback(err, pull_requests)
function M.get_pull_requests(project, repository, callback)
  M.request('GET', string.format('git/repositories/%s/pullrequests', repository), {
    project = project,
    query = {
      ['api-version'] = '7.0',
      ['searchCriteria.status'] = 'active',
    },
  }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response.value or {})
  end)
end
```

### Step 3: Add Request Orchestrator

In `lua/ado/requests.lua`:

```lua
--- Fetch and load pull requests for a repository
---@param repository string Repository name
---@param callback function|nil Called after PRs are loaded
function M.load_pull_requests(repository, callback)
  local project = state.get('project')
  if not project then
    vim.notify('No project selected', vim.log.levels.ERROR)
    return
  end

  M.execute(
    function(cb) api.get_pull_requests(project, repository, cb) end,
    function(prs)
      state.set('pull_requests', prs)
      if callback then callback(prs) end
    end
  )
end
```

### Step 4: Create UI Modules

Create `lua/ado/ui/pr_list.lua`:

```lua
-- Pull request list rendering
local M = {}

local state = require('ado.state')
local layout = require('ado.ui.layout')

function M.render()
  -- Similar to list.lua but for PRs
end

function M.setup_keymaps(buf)
  -- PR-specific keymaps
end

return M
```

Create `lua/ado/ui/pr_detail.lua`:

```lua
-- Pull request detail rendering
local M = {}

function M.render()
  -- Render PR details: title, description, reviewers, etc.
end

return M
```

### Step 5: Add Layout Support

In `lua/ado/ui/layout.lua`, add a new layout function:

```lua
function M.open_pullrequests()
  -- Similar to open_workitems() but uses pr_list and pr_detail
end
```

### Step 6: Add Routing

In `lua/ado/init.lua`, update `_open_surface()`:

```lua
function M._open_surface(surface)
  if surface == 'workitems' then
    require('ado.ui.layout').open_workitems()
  elseif surface == 'prs' or surface == 'pullrequests' then
    require('ado.ui.layout').open_pullrequests()
  else
    vim.notify('Unknown surface: ' .. surface, vim.log.levels.WARN)
  end
end
```

### Step 7: Update Command Completion

In `plugin/ado.lua`, update the completion function:

```lua
complete = function()
  return { 'workitems', 'prs' }
end,
```

## Debugging Tips

### Print Debugging

Use `vim.notify()` or `print()` for quick debugging:

```lua
vim.notify(vim.inspect(some_table), vim.log.levels.DEBUG)
```

### Check State

```vim
:lua print(vim.inspect(require('ado.state').get('work_items')))
```

### Check API Responses

Temporarily add logging to `api.lua`:

```lua
function M.request(method, endpoint, opts, callback)
  -- ... existing code ...

  vim.system(curl_args, {}, function(obj)
    vim.notify('API Response: ' .. obj.stdout, vim.log.levels.DEBUG)
    -- ... rest of callback handling
  end)
end
```

### Inspect Buffers and Windows

```vim
" List all buffers
:ls

" Check buffer options
:lua print(vim.inspect(vim.bo[bufnr]))

" List all windows
:lua print(vim.inspect(vim.api.nvim_list_wins()))
```

### Test API Manually

```bash
curl -s -u ":$ADO_PAT" \
  "https://dev.azure.com/your-org/_apis/projects?api-version=7.0" \
  | jq
```

## Code Style Guidelines

1. **Use LuaLS annotations** for type hints
2. **Document public functions** with purpose and parameters
3. **Keep modules focused** on single responsibility
4. **Use `vim.notify()`** for user-facing messages
5. **Prefer `vim.schedule()`** for UI updates from async callbacks

## Running Tests

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) as the test framework.

### Prerequisites

Install plenary.nvim via your plugin manager. It should be available at one of:
- `~/.local/share/nvim/lazy/plenary.nvim` (lazy.nvim)
- `~/.local/share/nvim/site/pack/packer/start/plenary.nvim` (packer)

### Running All Tests

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

### Running a Single Test File

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/ado/state_spec.lua"
```

### Test Structure

```
tests/
├── minimal_init.lua        # Minimal Neovim config for tests
└── ado/
    ├── state_spec.lua      # State module tests
    └── config_spec.lua     # Config module tests
```

### Writing Tests

Tests use the busted-style syntax provided by plenary:

```lua
describe('module_name', function()
  local module

  before_each(function()
    -- Reset module state before each test
    package.loaded['ado.module_name'] = nil
    module = require('ado.module_name')
  end)

  it('does something', function()
    assert.equals(expected, module.some_function())
  end)
end)
```
