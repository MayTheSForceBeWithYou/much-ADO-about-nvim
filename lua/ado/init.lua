-- much-ADO-about-nvim main module
-- Coordinates plugin initialization and high-level operations

local M = {}

local config = require('ado.config')
local state = require('ado.state')

--- Validate that required environment variables are set
---@return boolean ok
---@return string? error_message
local function validate_env()
  local org_url = vim.env.ADO_ORG_URL
  local pat = vim.env.ADO_PAT

  if not org_url or org_url == '' then
    return false, 'ADO_ORG_URL environment variable is required'
  end

  -- Validate URL format
  if not org_url:match('^https?://') then
    return false, 'ADO_ORG_URL must start with http:// or https://'
  end

  -- Normalize: strip trailing slash for consistency
  if org_url:sub(-1) == '/' then
    org_url = org_url:sub(1, -2)
    vim.env.ADO_ORG_URL = org_url
  end

  if not pat or pat == '' then
    return false, 'ADO_PAT environment variable is required'
  end

  return true, nil
end

--- Initialize the plugin state and SDK connection
local function initialize()
  state.reset()
  state.set('org_url', vim.env.ADO_ORG_URL)
  state.set('project', vim.env.ADO_PROJECT or nil)

  -- Create SDK connection via centralized client (uses ADO_Lua_SDK)
  local ado_client = require('ado.ado_client')
  state.set('connection', ado_client.create_connection(vim.env.ADO_ORG_URL, vim.env.ADO_PAT, {
    log = require('ado.log'),
  }))
end

--- Display help/usage information
local function show_help()
  local help_lines = {
    'much-ADO-about-nvim - Azure DevOps client for Neovim',
    '',
    'Usage: :Ado [command]',
    '',
    'Commands:',
    '  workitems    Browse work items (list + detail view)',
    '  pipelines    Browse pipelines (list → runs → run detail)',
    '  controls     Show keybindings by context (game-style controls page)',
    '  help         Show this help message',
    '',
    'Environment Variables:',
    '  ADO_ORG_URL  (required) Azure DevOps organization URL',
    '               e.g., https://dev.azure.com/myorg',
    '  ADO_PAT      (required) Personal Access Token',
    '  ADO_PROJECT  (optional) Default project name',
    '',
    'Keybindings (in list pane):',
    '  q            Close the ADO browser',
    '  <CR>         Select item and focus detail pane',
    '  j / k        Navigate items',
    '  R            Refresh current view',
    '  s            Change team / area path scope',
    '  H / L        Shrink / grow list pane width',
    '',
    'Keybindings (in detail pane):',
    '  q            Close the ADO browser',
    '  <CR> / <BS>  Return to list pane',
    '  j / k        Scroll  |  <C-d> / <C-u>  Half-page  |  gg / G  Top / bottom',
    '  e            Edit State (when cursor is on the State line)',
    '  H / L        Shrink / grow list pane width',
    '',
    'Team / Area Path (browser-like):',
    '  By default the plugin fetches "my teams" from ADO and remembers',
    '  your last selected Team/Area Path (stored in data dir).',
    '  Optional: restrict the list with team_scopes in setup():',
    '    require("ado").setup({',
    '      team_scopes = { "Project\\\\Team 1", "Project\\\\Team 2" },',
    '    })',
    '',
    '  Run :Ado controls to view all keybindings by context.',
  }

  for _, line in ipairs(help_lines) do
    vim.api.nvim_echo({{ line }}, false, {})
  end
end

--- Open the Azure DevOps browser
---@param surface string|nil The surface to open (default: 'help')
function M.open(surface)
  -- Handle empty string from command args
  if not surface or surface == '' then
    surface = 'help'
  end

  -- Help and controls don't require environment validation
  if surface == 'help' then
    show_help()
    return
  end
  if surface == 'controls' then
    require('ado.ui.controls').open()
    return
  end

  -- Validate environment
  local ok, err = validate_env()
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  -- Initialize state
  initialize()

  -- Check if project is set
  local project = state.get('project')
  if not project then
    -- Open project picker
    require('ado.ui.project_picker').open(function(selected_project)
      if selected_project then
        state.set('project', selected_project)
        M._open_surface(surface)
      end
    end)
  else
    M._open_surface(surface)
  end
end

--- Open a specific surface (internal)
---@param surface string
function M._open_surface(surface)
  if surface == 'workitems' then
    local cache = require('ado.cache')
    local org_url = state.get('org_url')
    local project = state.get('project')
    -- Restore last selected area path from cache (browser-like: remember last Team/Area)
    if not state.get('area_path') and org_url and project then
      local last = cache.get_last_area_path(org_url, project)
      if last and last ~= '' then
        state.set('area_path', last)
      end
    end
    local area_path = state.get('area_path')
    local scopes = config.get().team_scopes or {}
    -- If still no scope: need user to pick. Prefer config list; else use "my teams" from API (cached or fetch).
    if not area_path then
      if #scopes > 0 then
        require('ado.ui.scope_picker').open(function(selected)
          if selected then
            if org_url and project then
              cache.set_last_area_path(org_url, project, selected)
            end
            M._open_surface(surface)
          end
        end)
        return
      end
      -- No config scopes: load teams from API (or cache), then show picker
      require('ado.requests').load_teams({ mine = true }, function(paths)
        if #paths > 0 then
          require('ado.ui.scope_picker').open(function(selected)
            if selected then
              if org_url and project then
                cache.set_last_area_path(org_url, project, selected)
              end
              M._open_surface(surface)
            end
          end)
        else
          -- No teams or API error: open work items without scope (all items)
          require('ado.ui.layout').open_workitems()
        end
      end)
      return
    end
    require('ado.ui.layout').open_workitems()
  elseif surface == 'pipelines' then
    require('ado.ui.pipelines_list').open()
  else
    vim.notify('Unknown command: ' .. surface .. '. Run :Ado help for usage.', vim.log.levels.WARN)
  end
end

--- Refresh the current view
function M.refresh()
  local requests = require('ado.requests')
  local list = require('ado.ui.list')

  requests.load_work_items(function()
    list.render()
  end)
end

--- Setup function for user configuration
---@param opts table|nil User configuration options
function M.setup(opts)
  config.setup(opts)
end

return M
