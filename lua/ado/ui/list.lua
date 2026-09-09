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

local function identity_name(val)
  if type(val) == 'table' then
    return val.displayName or val.uniqueName or ''
  end
  if type(val) == 'string' then
    return val
  end
  return ''
end

--- Strip HTML tags and decode common entities (ADO descriptions are HTML)
---@param text string
---@return string
local function strip_html(text)
  text = text:gsub('<br%s*/?>', ' ')
  text = text:gsub('<p.->', ' ')
  text = text:gsub('</p>', ' ')
  text = text:gsub('<div.->', ' ')
  text = text:gsub('</div>', ' ')
  text = text:gsub('<[^>]+>', '')
  text = text:gsub('&nbsp;', ' ')
  text = text:gsub('&amp;', '&')
  text = text:gsub('&lt;', '<')
  text = text:gsub('&gt;', '>')
  text = text:gsub('&quot;', '"')
  text = text:gsub('%s+', ' ')
  return vim.trim(text)
end

---@param s string
---@param max number
---@return string
local function truncate(s, max)
  s = s or ''
  if max < 1 then
    return ''
  end
  if vim.fn.strdisplaywidth(s) <= max then
    return s
  end
  if max <= 3 then
    return vim.fn.strcharpart(s, 0, max)
  end
  local t = s
  while vim.fn.strdisplaywidth(t) > max - 3 and vim.fn.strchars(t) > 0 do
    t = vim.fn.strcharpart(t, 0, vim.fn.strchars(t) - 1)
  end
  return t .. '...'
end

---@param s string
---@param w number
---@return string
local function pad(s, w)
  s = truncate(s or '', w)
  return s .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(s)))
end

---@return number
local function list_width()
  local win = layout.get_list_win()
  if win and vim.api.nvim_win_is_valid(win) then
    return vim.api.nvim_win_get_width(win)
  end
  return config.get().ui.list_width or 60
end

-- Fixed-width columns in list-only mode (ID Type State Assignee)
local COL_ID, COL_TYPE, COL_STATE, COL_ASSIGNEE = 7, 12, 14, 16

---@param width number
---@return string
local function format_column_header(width)
  local prefix = pad('ID', COL_ID)
    .. ' ' .. pad('Type', COL_TYPE)
    .. ' ' .. pad('State', COL_STATE)
    .. ' ' .. pad('Assignee', COL_ASSIGNEE)
    .. ' '
  local rest = math.max(8, width - vim.fn.strdisplaywidth(prefix))
  local title_w = math.max(8, math.floor(rest * 0.55))
  local desc_w = math.max(0, rest - title_w - 1)
  if desc_w < 8 then
    return prefix .. pad('Title', rest)
  end
  return prefix .. pad('Title', title_w) .. ' ' .. pad('Description', desc_w)
end

--- Format a work item for display in the list
---@param item table Work item data
---@param width number Current list window width
---@return string
local function format_item(item, width)
  local fields = item.fields or {}
  local id = item.id or 0
  local title = fields['System.Title'] or 'Untitled'
  local item_state = fields['System.State'] or ''
  local assignee = identity_name(fields['System.AssignedTo'])
  local wit_type = fields['System.WorkItemType'] or ''

  if layout.is_list_only() then
    local desc = fields['System.Description']
    if type(desc) ~= 'string' then
      desc = ''
    else
      desc = strip_html(desc)
    end
    local prefix = pad(string.format('#%-5d', id), COL_ID)
      .. ' ' .. pad(wit_type, COL_TYPE)
      .. ' ' .. pad(item_state, COL_STATE)
      .. ' ' .. pad(assignee, COL_ASSIGNEE)
      .. ' '
    local rest = math.max(8, width - vim.fn.strdisplaywidth(prefix))
    local title_w = math.max(8, math.floor(rest * 0.55))
    local desc_w = math.max(0, rest - title_w - 1)
    if desc_w < 8 then
      return prefix .. truncate(title, rest)
    end
    return prefix .. pad(title, title_w) .. ' ' .. truncate(desc, desc_w)
  end

  local show_assignee = state.get('list_assignee_filter') ~= 'me' and assignee ~= ''
  local prefix
  if show_assignee then
    prefix = string.format('#%-5d [%-14s] %-12s ', id, item_state, truncate(assignee, 12))
  else
    prefix = string.format('#%-5d [%-14s] ', id, item_state)
  end
  local title_w = math.max(8, width - vim.fn.strdisplaywidth(prefix))
  return prefix .. truncate(title, title_w)
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
  local width = list_width()
  table.insert(lines, string.format('Scope: %s | Limit: 200', scope))
  table.insert(lines, string.format('%s | %s | %s', assignee_filter_label(), state_filter_label(), sort_label()))
  if layout.is_list_only() then
    table.insert(lines, 'f state  a assignee  o sort  O dir  d split')
  else
    table.insert(lines, 'f state  a assignee  o sort  O dir  d list')
  end
  table.insert(lines, string.rep('-', math.min(width, 80)))
  if layout.is_list_only() then
    table.insert(lines, format_column_header(width))
  end
  local prev_offset = header_offset
  header_offset = #lines
  local item_idx = cursor_line - prev_offset
  if item_idx < 1 then
    item_idx = 1
  end
  cursor_line = header_offset + item_idx

  if state.is_loading() then
    table.insert(lines, 'Loading...')
  elseif #work_items == 0 then
    table.insert(lines, 'No work items found')
    table.insert(lines, '')
    table.insert(lines, 'Press R to refresh')
  else
    for _, item in ipairs(work_items) do
      table.insert(lines, format_item(item, width))
    end
  end

  -- Update buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Restore cursor position (ensure it's on a work item line, not header)
  if #work_items > 0 then
    cursor_line = math.max(header_offset + 1, math.min(cursor_line, header_offset + #work_items))
  end
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
    if layout.is_list_only() then
      layout.toggle_list_only()
    end
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

  vim.keymap.set('n', 'd', function()
    layout.toggle_list_only()
  end, vim.tbl_extend('force', opts, { desc = 'Toggle list-only (hide/show detail)' }))
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
