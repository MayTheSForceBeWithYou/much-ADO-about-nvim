-- much-ADO-about-nvim UI scope picker module
-- Team/Area Path scope selection UI
-- Scopes: config.team_scopes if set, else state.team_area_paths (from "my teams" API / cache)

local M = {}

local config = require('ado.config')
local state = require('ado.state')

---@type number|nil Picker window ID
local picker_win = nil
---@type number|nil Picker buffer ID
local picker_buf = nil
---@type function|nil Callback when scope is selected
local on_select_callback = nil
---@type number Current cursor line (1-indexed)
local cursor_line = 1

--- Header line count (title + divider + blank)
local HEADER_LINES = 3

--- Get list of scope strings to show: config team_scopes first, else API/cached team area paths
---@return string[]
local function get_scopes()
  local from_config = config.get().team_scopes or {}
  if #from_config > 0 then
    return from_config
  end
  return state.get('team_area_paths') or {}
end

--- Render the scope list
local function render()
  if not picker_buf then return end

  local scopes = get_scopes()
  local lines = {}

  -- Header
  table.insert(lines, 'Select Team / Area Path')
  table.insert(lines, string.rep('=', 40))
  table.insert(lines, '')

  if #scopes == 0 then
    table.insert(lines, 'No teams available')
    table.insert(lines, '')
    table.insert(lines, 'Fetching teams… or add team_scopes in setup()')
  else
    for _, scope in ipairs(scopes) do
      table.insert(lines, scope)
    end
  end

  vim.bo[picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].modifiable = false

  -- Position cursor on first scope (line after header)
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    local first_scope_line = HEADER_LINES + 1
    vim.api.nvim_win_set_cursor(picker_win, { first_scope_line, 0 })
    cursor_line = first_scope_line
  end
end

--- Select the current scope
local function select_current()
  local scopes = get_scopes()
  if #scopes == 0 then return end

  -- Adjust for header lines
  local scope_index = cursor_line - HEADER_LINES
  if scope_index < 1 or scope_index > #scopes then
    return
  end

  local scope = scopes[scope_index]
  if not scope then return end
  local cb = on_select_callback
  state.set('area_path', scope)
  -- Persist so next time we restore this scope (browser-like)
  local org_url = state.get('org_url')
  local project = state.get('project')
  if org_url and project then
    require('ado.cache').set_last_area_path(org_url, project, scope)
  end
  M.close()
  if cb then cb(scope) end
end

--- Move cursor by delta
---@param delta number
local function move_cursor(delta)
  local scopes = get_scopes()
  if #scopes == 0 then return end

  local first_scope_line = HEADER_LINES + 1
  local last_scope_line = HEADER_LINES + #scopes

  cursor_line = cursor_line + delta
  cursor_line = math.max(first_scope_line, math.min(cursor_line, last_scope_line))

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
  end, { buffer = picker_buf, desc = 'Cancel scope selection' })

  vim.keymap.set('n', keymaps.select, function()
    select_current()
  end, { buffer = picker_buf, desc = 'Select scope' })

  vim.keymap.set('n', keymaps.next_item, function()
    move_cursor(1)
  end, { buffer = picker_buf, desc = 'Next scope' })

  vim.keymap.set('n', keymaps.prev_item, function()
    move_cursor(-1)
  end, { buffer = picker_buf, desc = 'Previous scope' })

  vim.keymap.set('n', 'j', function()
    move_cursor(1)
  end, { buffer = picker_buf })

  vim.keymap.set('n', 'k', function()
    move_cursor(-1)
  end, { buffer = picker_buf })
end

--- Open the scope picker
---@param callback function Called with selected scope string (or nil if cancelled)
function M.open(callback)
  on_select_callback = callback

  -- Create floating window for picker
  local ui_config = config.get().ui
  local scopes = get_scopes()
  local width = 50
  local height = math.max(8, HEADER_LINES + #scopes + 2)
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
    title = ' Select Team Scope ',
    title_pos = 'center',
  })

  setup_keymaps()
  render()
end

--- Close the scope picker
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
