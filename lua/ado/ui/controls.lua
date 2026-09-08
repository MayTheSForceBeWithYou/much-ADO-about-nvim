-- much-ADO-about-nvim UI controls module
-- Displays keybindings by context (game-style "controls" page)
-- Reads from config so it reflects the user's keymap configuration

local M = {}

local config = require('ado.config')

---@type number|nil Controls window ID
local controls_win = nil
---@type number|nil Controls buffer ID
local controls_buf = nil

--- Resolve a key placeholder from config (e.g. "<close>" -> keymaps.close)
---@param key string Raw key or placeholder like "<close>", "<select>", "<refresh>", "<next>", "<prev>"
---@return string
local function resolve_key(key)
  local km = config.get().keymaps or {}
  if key == '<close>' then return km.close or 'q' end
  if key == '<select>' then return km.select or '<CR>' end
  if key == '<refresh>' then return km.refresh or 'R' end
  if key == '<next>' then return km.next_item or 'j' end
  if key == '<prev>' then return km.prev_item or 'k' end
  return key
end

--- Build keybindings table per context: uses placeholders for config-driven keys
---@return table[] List of { context = string, bindings = { { key = string, action = string } } }
local function get_controls_data()
  local km = config.get().keymaps or {}
  return {
    {
      context = 'List Pane',
      bindings = {
        { key = '<close>', action = 'Close the ADO browser' },
        { key = '<select>', action = 'Select item and focus detail pane' },
        { key = '<next>', action = 'Next item' },
        { key = '<prev>', action = 'Previous item' },
        { key = '<refresh>', action = 'Refresh work items list' },
        { key = 's', action = 'Change team / area path scope' },
        { key = 'H', action = 'Shrink list pane width' },
        { key = 'L', action = 'Grow list pane width' },
      },
    },
    {
      context = 'Detail Pane',
      bindings = {
        { key = '<close>', action = 'Close the ADO browser' },
        { key = '<CR>', action = 'Return to list pane' },
        { key = '<BS>', action = 'Return to list pane' },
        { key = 'j', action = 'Scroll down' },
        { key = 'k', action = 'Scroll up' },
        { key = '<C-d>', action = 'Half-page down' },
        { key = '<C-u>', action = 'Half-page up' },
        { key = 'gg', action = 'Go to top' },
        { key = 'G', action = 'Go to bottom' },
        { key = 'e', action = 'Edit State (when cursor is on the State line)' },
        { key = 'a', action = 'Edit Assignee (when cursor is on Assigned To line)' },
        { key = '<Tab>', action = 'Switch between Details and History tabs' },
        { key = 'H', action = 'Shrink list pane width' },
        { key = 'L', action = 'Grow list pane width' },
      },
    },
    {
      context = 'Scope Picker',
      bindings = {
        { key = '<close>', action = 'Cancel and close picker' },
        { key = '<select>', action = 'Select highlighted scope' },
        { key = '<next>', action = 'Next scope' },
        { key = '<prev>', action = 'Previous scope' },
        { key = 'j', action = 'Next scope' },
        { key = 'k', action = 'Previous scope' },
      },
    },
    {
      context = 'Assignee Picker',
      bindings = {
        { key = 'j', action = 'Next item' },
        { key = 'k', action = 'Previous item' },
        { key = '<select>', action = 'Assign selected user' },
        { key = '<close>', action = 'Cancel' },
        { key = '<BS>', action = 'Backspace (delete search character)' },
        { key = 'A-Z/a-z', action = 'Type to search (immediate typeahead)' },
      },
    },
    {
      context = 'Project Picker',
      bindings = {
        { key = '<close>', action = 'Cancel and close picker' },
        { key = '<select>', action = 'Select highlighted project' },
        { key = '<next>', action = 'Next project' },
        { key = '<prev>', action = 'Previous project' },
        { key = 'j', action = 'Next project' },
        { key = 'k', action = 'Previous project' },
      },
    },
  }
end

--- Format a single key for display (bracketed for special keys)
---@param key string
---@return string
local function format_key(key)
  key = resolve_key(key)
  if key == '<CR>' then return 'Enter' end
  if key == '<BS>' then return 'Backspace' end
  if key:sub(1, 1) == '<' and key:sub(-1) == '>' then
    return key:gsub('<', '['):gsub('>', ']')
  end
  return key
end

--- Build the full controls buffer text
---@return string[]
local function build_lines()
  local data = get_controls_data()
  local lines = {}
  local key_width = 12

  table.insert(lines, '')
  table.insert(lines, '  ADO — Controls')
  table.insert(lines, '  ' .. string.rep('═', 42))
  table.insert(lines, '')

  for _, section in ipairs(data) do
    table.insert(lines, '  ┌─ ' .. section.context .. ' ' .. string.rep('─', math.max(0, 38 - #section.context)))
    for _, b in ipairs(section.bindings) do
      local k = format_key(b.key)
      local padding = string.rep(' ', math.max(0, key_width - #k))
      table.insert(lines, '  │  ' .. k .. padding .. '  ' .. b.action)
    end
    table.insert(lines, '  └' .. string.rep('─', 42))
    table.insert(lines, '')
  end

  table.insert(lines, '  Run :Ado help for usage and environment variables.')
  table.insert(lines, '')
  return lines
end

--- Render the controls buffer
local function render()
  if not controls_buf or not vim.api.nvim_buf_is_valid(controls_buf) then return end
  local lines = build_lines()
  vim.bo[controls_buf].modifiable = true
  vim.api.nvim_buf_set_lines(controls_buf, 0, -1, false, lines)
  vim.bo[controls_buf].modifiable = false
  vim.bo[controls_buf].filetype = 'markdown'
end

--- Open the controls window (floating, game-style overlay)
function M.open()
  if controls_win and vim.api.nvim_win_is_valid(controls_win) then
    vim.api.nvim_set_current_win(controls_win)
    render()
    return
  end

  local ui_config = config.get().ui
  local lines = build_lines()
  local width = 56
  local height = math.min(#lines + 2, vim.o.lines - 4)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  controls_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[controls_buf].buftype = 'nofile'
  vim.bo[controls_buf].bufhidden = 'wipe'
  vim.bo[controls_buf].swapfile = false

  controls_win = vim.api.nvim_open_win(controls_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = ui_config.border,
    title = ' Controls ',
    title_pos = 'center',
  })

  vim.keymap.set('n', 'q', function()
    M.close()
  end, { buffer = controls_buf, silent = true, nowait = true, desc = 'Close controls' })
  vim.keymap.set('n', config.get().keymaps.close or 'q', function()
    M.close()
  end, { buffer = controls_buf, silent = true, nowait = true })

  render()
end

--- Close the controls window
function M.close()
  if controls_win and vim.api.nvim_win_is_valid(controls_win) then
    vim.api.nvim_win_close(controls_win, true)
  end
  controls_win = nil
  controls_buf = nil
end

--- Check if the controls window is open
---@return boolean
function M.is_open()
  return controls_win ~= nil and vim.api.nvim_win_is_valid(controls_win)
end

return M
