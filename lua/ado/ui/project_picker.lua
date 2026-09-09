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
---@type 'asc'|'desc'
local sort_dir = 'asc'

--- Header line count (title + divider + blank)
local HEADER_LINES = 3

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

--- Projects sorted by name (case-insensitive)
---@return table[]
local function sorted_projects()
  local projects = {}
  for _, project in ipairs(state.get('projects') or {}) do
    projects[#projects + 1] = project
  end
  table.sort(projects, function(a, b)
    local na = (a.name or ''):lower()
    local nb = (b.name or ''):lower()
    if sort_dir == 'desc' then
      return na > nb
    end
    return na < nb
  end)
  return projects
end

--- Render the project list
---@param opts table|nil Optional: { keep_name = string } to keep cursor on a project
local function render(opts)
  if not picker_buf then return end
  opts = opts or {}

  local projects = sorted_projects()
  local lines = {}
  local dir_label = sort_dir == 'desc' and 'DESC' or 'ASC'

  -- Header
  table.insert(lines, string.format('Select a Project  (name %s, s to toggle)', dir_label))
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

  local first_project_line = HEADER_LINES + 1
  local target_line = first_project_line
  if opts.keep_name then
    for i, project in ipairs(projects) do
      if project.name == opts.keep_name then
        target_line = HEADER_LINES + i
        break
      end
    end
  end

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    local max_line = math.max(1, #lines)
    target_line = math.max(1, math.min(target_line, max_line))
    vim.api.nvim_win_set_cursor(picker_win, { target_line, 0 })
    cursor_line = target_line
  end
end

--- Select the current project
local function select_current()
  local projects = sorted_projects()
  if #projects == 0 then return end

  local project_index = cursor_line - HEADER_LINES
  if project_index < 1 or project_index > #projects then
    return
  end

  local project = projects[project_index]
  if not project then return end
  local cb = on_select_callback
  M.close()
  if cb then cb(project.name) end
end

--- Move cursor by delta
---@param delta number
local function move_cursor(delta)
  local projects = sorted_projects()
  if #projects == 0 then return end

  local first_project_line = HEADER_LINES + 1
  local last_project_line = HEADER_LINES + #projects

  cursor_line = cursor_line + delta
  cursor_line = math.max(first_project_line, math.min(cursor_line, last_project_line))

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_set_cursor(picker_win, { cursor_line, 0 })
  end
end

--- Toggle name sort between ASC and DESC
local function toggle_sort()
  local projects = sorted_projects()
  local keep_name
  local project_index = cursor_line - HEADER_LINES
  if project_index >= 1 and project_index <= #projects then
    keep_name = projects[project_index].name
  end
  sort_dir = sort_dir == 'asc' and 'desc' or 'asc'
  render({ keep_name = keep_name })
end

--- Set up keymaps for the picker
local function setup_keymaps()
  if not picker_buf then return end

  local keymaps = config.get().keymaps

  vim.keymap.set('n', keymaps.close, function()
    local cb = on_select_callback
    M.close()
    if cb then cb(nil) end
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

  vim.keymap.set('n', 's', function()
    toggle_sort()
  end, { buffer = picker_buf, desc = 'Toggle name sort ASC/DESC' })
end

--- Open the project picker
---@param callback function Called with selected project name (or nil if cancelled)
function M.open(callback)
  on_select_callback = callback
  sort_dir = 'asc'

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
  sort_dir = 'asc'
end

--- Check if the picker is open
---@return boolean
function M.is_open()
  return picker_win ~= nil and vim.api.nvim_win_is_valid(picker_win)
end

return M
