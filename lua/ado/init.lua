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

  -- Create SDK connection
  local sdk = require('ado.sdk')
  state.set('connection', sdk.new(vim.env.ADO_ORG_URL, sdk.auth.pat(vim.env.ADO_PAT)))
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
    '  help         Show this help message',
    '',
    'Environment Variables:',
    '  ADO_ORG_URL  (required) Azure DevOps organization URL',
    '               e.g., https://dev.azure.com/myorg',
    '  ADO_PAT      (required) Personal Access Token',
    '  ADO_PROJECT  (optional) Default project name',
    '',
    'Keybindings (in ADO buffers):',
    '  q            Close the ADO browser',
    '  <CR>         Select item',
    '  j / k        Navigate items',
    '  R            Refresh current view',
    '',
    'For more information, see the docs/ directory.',
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

  -- Help doesn't require environment validation
  if surface == 'help' then
    show_help()
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
    require('ado.ui.layout').open_workitems()
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
