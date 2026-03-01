# Configuration

This document covers all configuration options for much-ADO-about-nvim.

## Environment Variables

much-ADO-about-nvim uses environment variables for Azure DevOps authentication and defaults. All variables use the `ADO_` prefix.

### Required Variables

#### `ADO_ORG_URL`

The base URL of your Azure DevOps organization.

```bash
export ADO_ORG_URL="https://dev.azure.com/your-organization"
```

For on-premises Azure DevOps Server:

```bash
export ADO_ORG_URL="https://your-server/tfs/your-collection"
```

#### `ADO_PAT`

Your Personal Access Token for authentication.

```bash
export ADO_PAT="your-personal-access-token"
```

### Optional Variables

#### `ADO_PROJECT`

Default project to use. If not set, a project picker is displayed on launch.

```bash
export ADO_PROJECT="MyProject"
```

#### `ADO_SDK_PATH`

Path to the ADO_Lua_SDK package (local dependency). If not set, the plugin looks for a sibling `ADO_Lua_SDK` directory relative to the plugin root. Set this when the SDK is installed elsewhere.

```bash
export ADO_SDK_PATH="/path/to/ADO_Lua_SDK"
```

## Security Notes for PAT Usage

Your Personal Access Token is sensitive. Follow these best practices:

### Do

- Store your PAT in a secure credential manager or encrypted file
- Use environment variables set by your shell profile
- Create PATs with minimal required permissions
- Set expiration dates on your PATs
- Rotate PATs regularly

### Don't

- Hardcode PATs in scripts or configuration files
- Commit PATs to version control
- Share PATs between users
- Create PATs with full access when limited access suffices

### Recommended Setup

Use a tool like `direnv` or source from a secure location:

```bash
# ~/.config/ado/credentials (chmod 600)
export ADO_PAT="your-token-here"
```

```bash
# ~/.bashrc or ~/.zshrc
if [ -f ~/.config/ado/credentials ]; then
  source ~/.config/ado/credentials
fi
export ADO_ORG_URL="https://dev.azure.com/myorg"
export ADO_PROJECT="MyProject"
```

### Required PAT Permissions

For full functionality, your PAT needs:

| Scope | Permission | Used For |
|-------|------------|----------|
| Work Items | Read | Viewing work items |
| Project and Team | Read | Listing projects |

Future surfaces will require additional permissions (Code: Read for PRs, Build: Read for Pipelines, etc.).

## Plugin Configuration

Configure much-ADO-about-nvim by calling `setup()` with an options table.

```lua
require('ado').setup({
  -- Your options here
})
```

### Commands

| Command | Description |
|---------|-------------|
| `:Ado` or `:Ado help` | Show usage and environment variables |
| `:Ado workitems` | Open work items browser (list + detail) |
| `:Ado controls` | Show keybindings by context (game-style overlay; no auth required) |

### All Options

```lua
require('ado').setup({
  -- Enable debug logging (visible in :messages)
  debug = false,

  -- Optional: restrict scope picker to these area paths (e.g. "Project\\Team 1").
  -- If empty, the plugin fetches "my teams" from ADO and caches them.
  team_scopes = {},

  -- Keybindings (used in list, detail, and pickers; :Ado controls shows these)
  keymaps = {
    -- Key to close the ADO browser
    close = 'q',

    -- Key to select/open an item
    select = '<CR>',

    -- Key to refresh the current view
    refresh = 'R',

    -- Key to move to next item in list
    next_item = 'j',

    -- Key to move to previous item in list
    prev_item = 'k',
  },

  -- UI settings
  ui = {
    -- Width of the list pane (columns)
    list_width = 40,

    -- Border style for floating windows
    -- Options: 'none', 'single', 'double', 'rounded', 'solid', 'shadow'
    border = 'rounded',
  },
})
```

### Default Values

If you call `setup()` without any arguments, these defaults are used:

```lua
{
  keymaps = {
    close = 'q',
    select = '<CR>',
    refresh = 'R',
    next_item = 'j',
    prev_item = 'k',
  },
  ui = {
    list_width = 40,
    border = 'rounded',
  },
}
```

## Example Configurations

### Minimal Setup

```lua
-- Just use defaults
require('ado').setup()
```

### Custom Keybindings

Keybindings you set in `keymaps` are used in the list pane, detail pane, and pickers (scope, project). Run **`:Ado controls`** to see the full controls overlay with your configured keys.

```lua
require('ado').setup({
  keymaps = {
    close = '<Esc>',
    select = '<CR>',
    refresh = '<C-r>',
    next_item = '<C-n>',
    prev_item = '<C-p>',
  },
})
```

### Wider List Pane

```lua
require('ado').setup({
  ui = {
    list_width = 60,
  },
})
```

### Borderless Floating Windows

```lua
require('ado').setup({
  ui = {
    border = 'none',
  },
})
```

## Team / Area Path and Cache

- **Cache location:** `stdpath('data')/ado/state.json` stores the last selected area path per (org, project) and an optional list of teams per project.
- **team_scopes:** If you set `team_scopes` in `setup()`, the scope picker only shows those entries. Pass them inside `setup({})`, not as a key on the plugin spec (e.g. with lazy.nvim, put `team_scopes = { ... }` inside the table passed to `require('ado').setup()`).
- If `team_scopes` is empty, the plugin uses the Teams API (`$mine=true`) to list teams you're a member of and caches the result.

## Lazy Loading

To lazy-load much-ADO-about-nvim, configure your plugin manager to load on command:

### lazy.nvim

The plugin depends on **ADO_Lua_SDK** as a local dependency. Add it to your spec:

```lua
{
  'MayTheSForceBeWithYou/much-ADO-about-nvim',
  cmd = 'Ado',
  dependencies = {
    -- Local SDK (adjust path to your ADO_Lua_SDK location)
    { dir = '~/dev/Azure/ADO_Lua_SDK', lazy = true },
  },
  config = function()
    require('ado').setup()
  end,
}
```

Or set `ADO_SDK_PATH` in your environment so the plugin finds the SDK automatically.

### packer.nvim

```lua
use {
  'MayTheSForceBeWithYou/much-ADO-about-nvim',
  cmd = 'Ado',
  config = function()
    require('ado').setup()
  end,
}
```
