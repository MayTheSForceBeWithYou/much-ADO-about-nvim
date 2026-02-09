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

### All Options

```lua
require('ado').setup({
  -- Keybindings
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

## Lazy Loading

To lazy-load much-ADO-about-nvim, configure your plugin manager to load on command:

### lazy.nvim

```lua
{
  'MayTheSForceBeWithYou/much-ADO-about-nvim',
  cmd = 'Ado',
  config = function()
    require('ado').setup()
  end,
}
```

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
