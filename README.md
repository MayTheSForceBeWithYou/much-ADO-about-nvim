# much-ADO-about-nvim

A Neovim-native Azure DevOps client with a terminal-style UI.

## What is much-ADO-about-nvim?

much-ADO-about-nvim brings Azure DevOps directly into Neovim, allowing you to browse and interact with work items without leaving your editor. It provides a split-pane interface with a list view and detail view, similar to terminal-based email clients.

## Status

**Iteration 1 - Foundation**

This is the initial scaffold establishing the plugin architecture. Current features:

- `:Ado` command to launch the browser
- Project selection (when `ADO_PROJECT` is not set), sorted by name
- Work items list view with detail pane
- List filters (State, Assignee) and sort (ID / State)
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
:Ado controls     " Show keybindings by context (game-style controls page)
```

If `ADO_PROJECT` is not set, you'll be prompted to select a project.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ADO_ORG_URL` | Yes | Your Azure DevOps organization URL (e.g., `https://dev.azure.com/myorg`) |
| `ADO_PAT` | Yes | Personal Access Token with appropriate permissions |
| `ADO_PROJECT` | No | Default project. If not set, a project picker is shown. |

## Default Keybindings

### List Pane

| Key | Action |
|-----|--------|
| `q` | Close the ADO browser |
| `<CR>` | Select item and focus detail pane |
| `j` / `k` | Navigate items |
| `R` | Refresh current view |
| `s` | Change team / area path scope |
| `f` | Filter by State (default: hide Closed and Removed) |
| `a` | Filter by Assignee (default: assigned to me) |
| `o` | Cycle sort field (ID / State) |
| `O` | Toggle sort direction (default: ID descending) |
| `d` | Toggle list-only (hide detail; full-width columns) |
| `H` / `L` | Shrink / grow list pane width |

The list header shows the active assignee filter, state filter, and sort. Changing State or Assignee reloads from Azure DevOps (so the 200-item limit applies after filters). `o` / `O` re-sort the current results without refetching.

Press **`d`** to hide the detail pane so the list uses the full window. Rows then include Type, Assignee, the full Title (as width allows), and a Description snippet. Press `d` again (or `<CR>` on an item) to restore the split.

### Detail Pane

| Key | Action |
|-----|--------|
| `q` | Close the ADO browser |
| `<CR>` / `<BS>` | Return to list pane |
| `j` / `k` | Scroll |
| `<C-d>` / `<C-u>` | Half-page scroll |
| `gg` / `G` | Top / bottom |
| `e` | Edit State (when cursor is on the State line) |
| `a` | Edit Assignee (when cursor is on the Assigned To line) |
| `<Tab>` | Switch between Details and History tabs |
| `d` | Hide detail (list-only full-width list) |
| `H` / `L` | Shrink / grow list pane width |

### Project Picker

Shown when `ADO_PROJECT` is not set. Projects load sorted by name (A–Z).

| Key | Action |
|-----|--------|
| `q` | Cancel and close picker |
| `<CR>` | Select highlighted project |
| `j` / `k` | Navigate projects |
| `s` | Toggle name sort ASC / DESC |

### Viewing keybindings in Neovim

Run **`:Ado controls`** to open a floating overlay that lists every keybinding by context (List Pane, Detail Pane, Scope Picker, Project Picker)—like a video game’s controls screen. The overlay uses your configured keymaps from `setup()`. Press `q` to close it.

## Work item list filters and sort

Defaults when you open `:Ado workitems`:

- **State:** hide Closed and Removed
- **Assignee:** only items assigned to the current user (`@Me`)
- **Sort:** ID descending

Use `f` and `a` to change filters (picker includes All states / Anyone, plus states and teammates seen in the current list). Use `o` to switch between ID and State, and `O` to flip ascending/descending.

## Configuration

**Important:** With plugin managers (e.g. lazy.nvim), pass options **inside** `setup({})`. Keys on the plugin spec (e.g. `team_scopes = { ... }` next to `config`) are not passed to the plugin.

```lua
require('ado').setup({
  debug = false,             -- Enable debug logging (visible in :messages)
  team_scopes = {},          -- Optional: restrict scope list (see Team / Area Path below)
  keymaps = {
    close = 'q',
    select = '<CR>',
    refresh = 'R',
    next_item = 'j',
    prev_item = 'k',
  },
  ui = {
    list_width = 60,           -- Width of list pane in columns
    list_width_step = 5,       -- Columns to resize per H/L keypress
    border = 'rounded',
  },
})
```

## Team / Area Path (browser-like)

The plugin behaves like the ADO web UI: it discovers **teams you're a member of** and **remembers your last selected Team/Area Path**.

- **First run (or no cache):** The plugin fetches "my teams" from ADO (`$mine=true`) and shows a scope picker. Each team is listed by area path (e.g. `MyProject\Team Alpha`).
- **Next runs:** Your last selected scope is restored from cache (stored under `stdpath('data')/ado/state.json`), so work items open directly with that filter.
- **Press `s`** in the list pane to change scope; the picker shows your teams (from API/cache) or a config-defined list if you set `team_scopes`.
- **Filtering:** Work items are filtered with `[System.AreaPath] UNDER '<scope>'` in the WIQL query. The active scope is shown in the list header.

### Optional: restrict scopes in config

If you set `team_scopes` in `setup()`, the scope picker only shows those entries (and still remembers the last selected one):

```lua
require('ado').setup({
  team_scopes = {
    'MyProject\\Team Alpha',
    'MyProject\\Team Beta',
  },
})
```

- If `team_scopes` is empty or omitted, the plugin uses teams from the ADO API (and caches them). No config needed for typical use.

## Documentation

- [Architecture](docs/architecture.md) - How the plugin is structured
- [Configuration](docs/configuration.md) - All configuration options
- [Development](docs/development.md) - Contributing and extending the plugin

## License

MIT
