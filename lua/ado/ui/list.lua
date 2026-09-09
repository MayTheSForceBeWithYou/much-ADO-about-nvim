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
  local fields = item.fields or {}
  local id = item.id or '?'
  local title = fields['System.Title'] or 'Untitled'
  local item_state = fields['System.State'] or ''
  local assigned = fields['System.AssignedTo']
  local assignee = ''
  if type(assigned) == 'table' then
    assignee = assigned.displayName or assigned.uniqueName or ''
  elseif type(assigned) == 'string' then
    assignee = assigned
  end

  local max_title_len = 28
  if #title > max_title_len then
    title = title:sub(1, max_title_len - 3) .. '...'
  end

  if state.get('list_assignee_filter') ~= 'me' and assignee ~= '' then
    if #assignee > 12 then
      assignee = assignee:sub(1, 9) .. '...'
    end
    return string.format('#%-5d [%-14s] %-12s %s', id, item_state, assignee, title)
  end
  return string.format('#%-5d [%-14s] %s', id, item_state, title)
end

local function state_filter_label()
  local f = state.get('list_state_filter') or 'active'
  if f == 'active' then
    return 'hide Closed/Removed'
  end
  if f == 'all' then
    return 'all states'
  end
  return f
end

local function assignee_filter_label()
  local f = state.get('list_assignee_filter') or 'me'
  if f == 'me' then
    return '@Me'
  end
  if f == 'all' then
    return 'anyone'
  end
  if f == 'unassigned' then
    return 'unassigned'
  end
  return f
end

local function sort_label()
  local field = state.get('list_sort_field') or 'id'
  local dir = state.get('list_sort_dir') or 'desc'
  local name = field == 'state' and 'State' or 'ID'
  return name .. ' ' .. string.upper(dir)
end

--- Apply current sort to in-memory work items and re-render (no refetch)
local function apply_sort_and_render()
  local items = state.get('work_items') or {}
  require('ado.requests').sort_work_items(items)
  state.set('work_items', items)
  M.render()
end

--- Render the work items list
function M.render()
  local buf = layout.get_list_buf()
  if not buf then return end

  local work_items = state.get('work_items') or {}
  local lines = {}

  local area_path = state.get('area_path')
  local scope = area_path and (area_path .. ' (UNDER)') or 'all'
  table.insert(lines, string.format('Scope: %s | Limit: 200', scope))
  table.insert(lines, string.format('%s | %s | %s', assignee_filter_label(), state_filter_label(), sort_label()))
  table.insert(lines, 'f state  a assignee  o sort  O dir')
  table.insert(lines, string.rep('-', 40))
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

  vim.keymap.set('n', 'f', function()
    local labels = { 'Hide Closed/Removed', 'All states', 'Closed', 'Removed' }
    local values = { 'active', 'all', 'Closed', 'Removed' }
    local seen = { active = true, all = true, Closed = true, Removed = true }
    for _, item in ipairs(state.get('work_items') or {}) do
      local st = (item.fields or {})['System.State']
      if type(st) == 'string' and st ~= '' and not seen[st] then
        seen[st] = true
        labels[#labels + 1] = st
        values[#values + 1] = st
      end
    end
    vim.ui.select(labels, { prompt = 'Filter by State' }, function(choice)
      if not choice then return end
      for i, label in ipairs(labels) do
        if label == choice then
          state.set('list_state_filter', values[i])
          require('ado').refresh()
          return
        end
      end
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Filter by State' }))

  vim.keymap.set('n', 'a', function()
    local labels = { 'Assigned to me', 'Anyone', 'Unassigned' }
    local values = { 'me', 'all', 'unassigned' }
    local seen = { me = true, all = true, unassigned = true }
    for _, m in ipairs(state.get('team_members') or {}) do
      local email = m.uniqueName or m.displayName
      if email and not seen[email] then
        seen[email] = true
        labels[#labels + 1] = m.displayName or email
        values[#values + 1] = m.uniqueName or email
      end
    end
    vim.ui.select(labels, { prompt = 'Filter by Assignee' }, function(choice)
      if not choice then return end
      for i, label in ipairs(labels) do
        if label == choice then
          state.set('list_assignee_filter', values[i])
          require('ado').refresh()
          return
        end
      end
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Filter by Assignee' }))

  vim.keymap.set('n', 'o', function()
    local field = state.get('list_sort_field') or 'id'
    state.set('list_sort_field', field == 'id' and 'state' or 'id')
    apply_sort_and_render()
  end, vim.tbl_extend('force', opts, { desc = 'Cycle sort field (ID/State)' }))

  vim.keymap.set('n', 'O', function()
    local dir = state.get('list_sort_dir') or 'desc'
    state.set('list_sort_dir', dir == 'desc' and 'asc' or 'desc')
    apply_sort_and_render()
  end, vim.tbl_extend('force', opts, { desc = 'Toggle sort direction' }))
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
  -- Reset to Details tab whenever the user navigates to a new item
  state.set('detail_tab', 'details')
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
