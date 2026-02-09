# much-ADO-about-nvim

A Neovim-native Azure DevOps client with a terminal-style UI.

## What is much-ADO-about-nvim?

much-ADO-about-nvim brings Azure DevOps directly into Neovim, allowing you to browse and interact with work items without leaving your editor. It provides a split-pane interface with a list view and detail view, similar to terminal-based email clients.

## Status

**Iteration 1 - Foundation**

This is the initial scaffold establishing the plugin architecture. Current features:

- `:Ado` command to launch the browser
- Project selection (when `ADO_PROJECT` is not set)
- Work items list view with detail pane
- Keyboard navigation

### Non-Goals for Iteration 1

- Pull request management
- Pipeline monitoring
- Board/sprint views
- Work item editing/creation
- Offline caching
- Multiple organization support

These features will be added in future iterations.

## Requirements

- Neovim 0.10 or later
- `curl` available in PATH
- Azure DevOps Personal Access Token (PAT)

## Quick Start

### 1. Install the Plugin

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'MayTheSForceBeWithYou/much-ADO-about-nvim',
  config = function()
    require('ado').setup({
      -- Optional configuration
    })
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'MayTheSForceBeWithYou/much-ADO-about-nvim',
  config = function()
    require('ado').setup()
  end,
}
```

### 2. Set Environment Variables

```bash
export ADO_ORG_URL="https://dev.azure.com/your-organization"
export ADO_PAT="your-personal-access-token"
export ADO_PROJECT="your-project-name"  # Optional
```

### 3. Launch

```vim
:Ado              " Show help/usage
:Ado help         " Show help/usage
:Ado workitems    " Open work items browser
```

If `ADO_PROJECT` is not set, you'll be prompted to select a project.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ADO_ORG_URL` | Yes | Your Azure DevOps organization URL (e.g., `https://dev.azure.com/myorg`) |
| `ADO_PAT` | Yes | Personal Access Token with appropriate permissions |
| `ADO_PROJECT` | No | Default project. If not set, a project picker is shown. |

## Default Keybindings

| Key | Action |
|-----|--------|
| `q` | Close the ADO browser |
| `<CR>` | Select item |
| `j` | Next item |
| `k` | Previous item |
| `R` | Refresh current view |

## Configuration

```lua
require('ado').setup({
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
})
```

## Documentation

- [Architecture](docs/architecture.md) - How the plugin is structured
- [Configuration](docs/configuration.md) - All configuration options
- [Development](docs/development.md) - Contributing and extending the plugin

## License

MIT
