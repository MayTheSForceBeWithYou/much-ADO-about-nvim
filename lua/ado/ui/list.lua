-- much-ADO-about-nvim UI list module
-- List pane rendering and selection handling
-- This module MUST NOT call HTTP directly

local M = {}

local config = require('ado.config')
local state = require('ado.state')
local layout = require('ado.ui.layout')

---@type number Current cursor line (1-indexed)
local cursor_line = 1

--- Format a work item for display in the list
---@param item table Work item data
---@return string
local function format_item(item)
  -- TODO: Implement proper formatting based on work item fields
  local fields = item.fields or {}
  local id = item.id or '?'
  local title = fields['System.Title'] or 'Untitled'
  local type_name = fields['System.WorkItemType'] or ''
  local item_state = fields['System.State'] or ''

  -- Truncate title if too long
  local max_title_len = 30
  if #title > max_title_len then
    title = title:sub(1, max_title_len - 3) .. '...'
  end

  return string.format('#%-5d [%-8s] %s', id, item_state, title)
end

--- Render the work items list
function M.render()
  local buf = layout.get_list_buf()
  if not buf then return end

  local work_items = state.get('work_items') or {}
  local lines = {}

  if state.is_loading() then
    lines = { 'Loading...' }
  elseif #work_items == 0 then
    lines = { 'No work items found', '', 'Press R to refresh' }
  else
    for _, item in ipairs(work_items) do
      table.insert(lines, format_item(item))
    end
  end

  -- Update buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Restore cursor position
  local win = layout.get_list_win()
  if win and vim.api.nvim_win_is_valid(win) then
    local line = math.min(cursor_line, #lines)
    vim.api.nvim_win_set_cursor(win, { math.max(1, line), 0 })
  end
end

--- Set up list-specific keymaps
---@param buf number Buffer ID
function M.setup_keymaps(buf)
  -- Guard: validate buffer before setting keymaps
  if not buf or buf == 0 or not vim.api.nvim_buf_is_valid(buf) then
    vim.notify('Cannot set list keymaps: invalid buffer', vim.log.levels.ERROR)
    return
  end

  local keymaps = config.get().keymaps
  local opts = { buffer = buf, silent = true, nowait = true }

  vim.keymap.set('n', keymaps.select, function()
    M.select_current()
  end, vim.tbl_extend('force', opts, { desc = 'Select work item' }))

  vim.keymap.set('n', keymaps.next_item, function()
    M.move_cursor(1)
  end, vim.tbl_extend('force', opts, { desc = 'Next item' }))

  vim.keymap.set('n', keymaps.prev_item, function()
    M.move_cursor(-1)
  end, vim.tbl_extend('force', opts, { desc = 'Previous item' }))
end

--- Move the cursor by delta lines
---@param delta number Lines to move (positive = down, negative = up)
function M.move_cursor(delta)
  local work_items = state.get('work_items') or {}
  if #work_items == 0 then return end

  cursor_line = cursor_line + delta
  cursor_line = math.max(1, math.min(cursor_line, #work_items))

  local win = layout.get_list_win()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { cursor_line, 0 })
  end

  -- Update detail view for selected item
  M.select_current()
end

--- Select the current item and update detail view
function M.select_current()
  local work_items = state.get('work_items') or {}
  if #work_items == 0 then return end

  local item = work_items[cursor_line]
  if item then
    state.set('selected_work_item', item)
    require('ado.ui.detail').render()
  end
end

--- Get the current cursor line
---@return number
function M.get_cursor_line()
  return cursor_line
end

--- Reset cursor position
function M.reset_cursor()
  cursor_line = 1
end

return M
