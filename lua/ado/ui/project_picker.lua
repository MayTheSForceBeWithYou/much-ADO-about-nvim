-- much-ADO-about-nvim UI project picker module
-- Project selection UI when ADO_PROJECT is not set
-- This module MUST NOT call HTTP directly

local M = {}

local config = require('ado.config')
local state = require('ado.state')
local requests = require('ado.requests')

---@type number|nil Picker window ID
local picker_win = nil
---@type number|nil Picker buffer ID
local picker_buf = nil
---@type function|nil Callback when project is selected
local on_select_callback = nil
---@type number Current cursor line (1-indexed)
local cursor_line = 1

--- Format a project for display
---@param project table Project data
---@return string
local function format_project(project)
  local name = project.name or 'Unknown'
  local description = project.description or ''

  if #description > 40 then
    description = description:sub(1, 37) .. '...'
  end

  if description ~= '' then
    return string.format('%-30s  %s', name, description)
  else
    return name
  end
end

--- Render the project list
local function render()
  if not picker_buf then return end

  local projects = state.get('projects') or {}
  local lines = {}

  -- Header
  table.insert(lines, 'Select a Project')
  table.insert(lines, string.rep('=', 40))
  table.insert(lines, '')

  if state.is_loading() then
    table.insert(lines, 'Loading projects...')
  elseif #projects == 0 then
    table.insert(lines, 'No projects found')
    table.insert(lines, '')
    table.insert(lines, 'Check your ADO_ORG_URL and ADO_PAT')
  else
    for _, project in ipairs(projects) do
      table.insert(lines, format_project(project))
    end
  end

  vim.bo[picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].modifiable = false

  -- Position cursor on first project (line 4, after header)
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    local first_project_line = 4
    vim.api.nvim_win_set_cursor(picker_win, { first_project_line, 0 })
    cursor_line = first_project_line
  end
end

--- Select the current project
local function select_current()
  local projects = state.get('projects') or {}
  if #projects == 0 then return end

  -- Adjust for header lines
  local project_index = cursor_line - 3
  if project_index < 1 or project_index > #projects then
    return
  end

  local project = projects[project_index]
  if project and on_select_callback then
    M.close()
    on_select_callback(project.name)
  end
end

--- Move cursor by delta
---@param delta number
local function move_cursor(delta)
  local projects = state.get('projects') or {}
  if #projects == 0 then return end

  local first_project_line = 4
  local last_project_line = 3 + #projects

  cursor_line = cursor_line + delta
  cursor_line = math.max(first_project_line, math.min(cursor_line, last_project_line))

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_set_cursor(picker_win, { cursor_line, 0 })
  end
end

--- Set up keymaps for the picker
local function setup_keymaps()
  if not picker_buf then return end

  local keymaps = config.get().keymaps

  vim.keymap.set('n', keymaps.close, function()
    M.close()
    if on_select_callback then
      on_select_callback(nil)
    end
  end, { buffer = picker_buf, desc = 'Cancel project selection' })

  vim.keymap.set('n', keymaps.select, function()
    select_current()
  end, { buffer = picker_buf, desc = 'Select project' })

  vim.keymap.set('n', keymaps.next_item, function()
    move_cursor(1)
  end, { buffer = picker_buf, desc = 'Next project' })

  vim.keymap.set('n', keymaps.prev_item, function()
    move_cursor(-1)
  end, { buffer = picker_buf, desc = 'Previous project' })

  vim.keymap.set('n', 'j', function()
    move_cursor(1)
  end, { buffer = picker_buf })

  vim.keymap.set('n', 'k', function()
    move_cursor(-1)
  end, { buffer = picker_buf })
end

--- Open the project picker
---@param callback function Called with selected project name (or nil if cancelled)
function M.open(callback)
  on_select_callback = callback

  -- Create floating window for picker
  local ui_config = config.get().ui
  local width = 60
  local height = 20
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype = 'nofile'
  vim.bo[picker_buf].bufhidden = 'wipe'
  vim.bo[picker_buf].swapfile = false

  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = ui_config.border,
    title = ' Azure DevOps Projects ',
    title_pos = 'center',
  })

  setup_keymaps()

  -- Load and render projects
  requests.load_projects(function()
    render()
  end)

  -- Initial render (shows loading state)
  render()
end

--- Close the project picker
function M.close()
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_close(picker_win, true)
  end

  picker_win = nil
  picker_buf = nil
  on_select_callback = nil
  cursor_line = 1
end

--- Check if the picker is open
---@return boolean
function M.is_open()
  return picker_win ~= nil and vim.api.nvim_win_is_valid(picker_win)
end

return M
