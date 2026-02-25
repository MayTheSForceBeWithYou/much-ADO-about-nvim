-- much-ADO-about-nvim UI list module
-- List pane rendering and selection handling
-- This module MUST NOT call HTTP directly

local M = {}

local config = require('ado.config')
local log = require('ado.log')
local state = require('ado.state')
local layout = require('ado.ui.layout')

---@type number Current cursor line (1-indexed, includes header offset)
local cursor_line = 1
---@type number Number of header lines before work items start
local header_offset = 0

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

  -- Scope header
  local area_path = state.get('area_path')
  if area_path then
    table.insert(lines, string.format('Scope: %s (UNDER) | Limit: 200', area_path))
    table.insert(lines, string.rep('-', 40))
  end
  header_offset = #lines

  if state.is_loading() then
    table.insert(lines, 'Loading...')
  elseif #work_items == 0 then
    table.insert(lines, 'No work items found')
    table.insert(lines, '')
    table.insert(lines, 'Press R to refresh')
  else
    for _, item in ipairs(work_items) do
      table.insert(lines, format_item(item))
    end
  end

  -- Update buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Restore cursor position (ensure it's on a work item line, not header)
  local win = layout.get_list_win()
  if win and vim.api.nvim_win_is_valid(win) then
    local line = math.max(header_offset + 1, math.min(cursor_line, #lines))
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
    -- Focus the detail pane so the user can scroll/read it
    local detail_win = layout.get_detail_win()
    if detail_win and vim.api.nvim_win_is_valid(detail_win) then
      vim.api.nvim_set_current_win(detail_win)
    end
  end, vim.tbl_extend('force', opts, { desc = 'Select work item' }))

  vim.keymap.set('n', keymaps.next_item, function()
    M.move_cursor(1)
  end, vim.tbl_extend('force', opts, { desc = 'Next item' }))

  vim.keymap.set('n', keymaps.prev_item, function()
    M.move_cursor(-1)
  end, vim.tbl_extend('force', opts, { desc = 'Previous item' }))

  vim.keymap.set('n', 's', function()
    local cfg = config.get()
    local scopes = cfg.team_scopes or {}
    -- If no config scopes, ensure "my teams" are loaded (from cache or API) before opening picker
    if #scopes == 0 then
      require('ado.requests').load_teams({ mine = true }, function()
        require('ado.ui.scope_picker').open(function(selected)
          if selected then
            require('ado').refresh()
          end
        end)
      end)
    else
      require('ado.ui.scope_picker').open(function(selected)
        if selected then
          require('ado').refresh()
        end
      end)
    end
  end, vim.tbl_extend('force', opts, { desc = 'Change scope' }))
end

--- Move the cursor by delta lines
---@param delta number Lines to move (positive = down, negative = up)
function M.move_cursor(delta)
  local work_items = state.get('work_items') or {}
  if #work_items == 0 then return end

  cursor_line = cursor_line + delta
  local first_item = header_offset + 1
  local last_item = header_offset + #work_items
  cursor_line = math.max(first_item, math.min(cursor_line, last_item))

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
  if #work_items == 0 then
    log.debug('select_current: no work items in state')
    return
  end

  local item_index = cursor_line - header_offset
  local item = work_items[item_index]
  if not item then
    log.debug('select_current: no item at index %d (cursor_line %d, offset %d, have %d items)',
      item_index, cursor_line, header_offset, #work_items)
    return
  end

  local fields = item.fields or {}
  log.debug('select_current: #%d "%s" (type=%s, field_count=%d)',
    item.id or 0,
    fields['System.Title'] or '?',
    vim.inspect(fields['System.WorkItemType']),
    vim.tbl_count(fields))
  state.set('selected_work_item', item)
  require('ado.ui.detail').render()

  -- Fetch layout if not cached, re-render when available
  local wit_type = fields['System.WorkItemType']
  if not wit_type then
    log.debug('select_current: no System.WorkItemType field, skipping layout fetch')
    return
  end

  local layouts = state.get('layouts') or {}
  if layouts[wit_type] then
    log.debug('select_current: layout already cached for "%s"', wit_type)
    return
  end

  log.debug('select_current: triggering layout fetch for type "%s"', wit_type)
  require('ado.requests').ensure_layout(wit_type, function()
    -- Re-render only if this item is still selected
    if state.get('selected_work_item') == item then
      log.debug('select_current: re-rendering detail with layout for #%d', item.id or 0)
      require('ado.ui.detail').render()
    else
      log.debug('select_current: item #%d no longer selected, skipping re-render', item.id or 0)
    end
  end)
end

--- Get the current cursor line
---@return number
function M.get_cursor_line()
  return cursor_line
end

--- Reset cursor position
function M.reset_cursor()
  cursor_line = 1
  header_offset = 0
end

return M
