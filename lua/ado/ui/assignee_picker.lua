-- much-ADO-about-nvim UI assignee picker module
-- Floating window with typeahead search for assigning work items
-- This module MUST NOT call HTTP directly — uses requests.lua for API calls

local M = {}

local config = require('ado.config')
local state = require('ado.state')
local log = require('ado.log')

---@type number|nil Picker window ID
local picker_win = nil
---@type number|nil Picker buffer ID
local picker_buf = nil
---@type function|nil Callback when selection is made
local on_select_callback = nil
---@type string Current search query
local search_query = ''
---@type ado.sdk.Identity[] Search results from API
local search_results = {}
---@type number|nil Debounce timer ID
local debounce_timer = nil
---@type number Current cursor index in the items list (1-indexed)
local cursor_index = 1
---@type boolean Whether search is in progress
local searching = false

--- Debounce delay in milliseconds
local DEBOUNCE_MS = 300

--- Get team members filtered by current search query
---@return ado.sdk.TeamMember[]
local function get_filtered_team_members()
  local members = state.get('team_members') or {}
  if search_query == '' then
    return members
  end
  local lower_query = search_query:lower()
  local filtered = {}
  for _, m in ipairs(members) do
    local name = (m.displayName or ''):lower()
    local email = (m.uniqueName or ''):lower()
    if name:find(lower_query, 1, true) or email:find(lower_query, 1, true) then
      table.insert(filtered, m)
    end
  end
  return filtered
end

--- Get deduplicated search results (excluding team members already shown)
---@param team ado.sdk.TeamMember[] Filtered team members
---@return ado.sdk.Identity[]
local function get_deduped_search_results(team)
  local team_emails = {}
  for _, m in ipairs(team) do
    if m.uniqueName then
      team_emails[m.uniqueName:lower()] = true
    end
  end
  local results = {}
  for _, identity in ipairs(search_results) do
    local email_key = (identity.email or ''):lower()
    if email_key == '' or not team_emails[email_key] then
      table.insert(results, identity)
    end
  end
  return results
end

--- Build the combined items list (team members + search results + clear option)
---@return table[] items Each item has { displayName, email, type }
local function build_items()
  local items = {}
  local team = get_filtered_team_members()

  for _, m in ipairs(team) do
    table.insert(items, {
      displayName = m.displayName,
      email = m.uniqueName,
      type = 'team',
    })
  end

  for _, identity in ipairs(get_deduped_search_results(team)) do
    table.insert(items, {
      displayName = identity.displayName,
      email = identity.email,
      type = 'search',
    })
  end

  table.insert(items, {
    displayName = 'Clear assignee',
    email = '',
    type = 'clear',
  })

  return items
end

--- Calculate the buffer line number for a given item index
---@param index number 1-indexed item position in build_items()
---@return number line 1-indexed buffer line
local function item_line_for_index(index)
  local team = get_filtered_team_members()
  local deduped_search = get_deduped_search_results(team)

  -- Line layout:
  -- 1: Search line
  -- 2: separator
  -- 3: "Team Members"
  -- 4..4+#team-1: team member lines (or 4: "(none)" if empty)
  -- next: separator
  -- next: "Search Results"
  -- next..next+search-1: search result lines (or 1 placeholder)
  -- next: separator
  -- last: "> Clear assignee"

  local team_display_count = math.max(1, #team)
  local search_display_count = math.max(1, #deduped_search)

  local current_item = 0

  -- Team members start at line 4
  local team_start_line = 4
  for i = 1, #team do
    current_item = current_item + 1
    if current_item == index then
      return team_start_line + i - 1
    end
  end

  -- Search results: after team lines + separator + "Search Results" header
  local search_start_line = team_start_line + team_display_count + 2
  for i = 1, #deduped_search do
    current_item = current_item + 1
    if current_item == index then
      return search_start_line + i - 1
    end
  end

  -- Clear option: after search lines + separator
  current_item = current_item + 1
  if current_item == index then
    return search_start_line + search_display_count + 1
  end

  return team_start_line
end

--- Update cursor display position to match cursor_index
local function update_cursor_display()
  if not picker_win or not vim.api.nvim_win_is_valid(picker_win) then return end
  local items = build_items()
  if #items == 0 then return end
  cursor_index = math.max(1, math.min(cursor_index, #items))
  local line = item_line_for_index(cursor_index)
  pcall(vim.api.nvim_win_set_cursor, picker_win, { line, 0 })
end

--- Render the picker contents
local function render()
  if not picker_buf or not vim.api.nvim_buf_is_valid(picker_buf) then return end

  local team = get_filtered_team_members()
  local deduped_search = get_deduped_search_results(team)
  local lines = {}

  -- Search line
  table.insert(lines, 'Search: ' .. search_query .. (searching and ' ...' or ''))

  -- Separator
  table.insert(lines, string.rep('\u{2500}', 40))

  -- Team members section
  table.insert(lines, 'Team Members')
  if #team > 0 then
    for _, m in ipairs(team) do
      local email_display = m.uniqueName and (' (' .. m.uniqueName .. ')') or ''
      table.insert(lines, '  ' .. (m.displayName or '?') .. email_display)
    end
  else
    table.insert(lines, '  (none)')
  end

  -- Separator
  table.insert(lines, string.rep('\u{2500}', 40))

  -- Search results section
  table.insert(lines, 'Search Results')
  if #deduped_search > 0 then
    for _, identity in ipairs(deduped_search) do
      local email_display = identity.email and (' (' .. identity.email .. ')') or ''
      table.insert(lines, '  ' .. (identity.displayName or '?') .. email_display)
    end
  elseif search_query == '' then
    table.insert(lines, '  (type to search)')
  elseif searching then
    table.insert(lines, '  (searching...)')
  else
    table.insert(lines, '  (no results)')
  end

  -- Separator
  table.insert(lines, string.rep('\u{2500}', 40))

  -- Clear option
  table.insert(lines, '> Clear assignee')

  vim.bo[picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].modifiable = false

  update_cursor_display()
end

--- Trigger debounced identity search
local function trigger_search()
  if debounce_timer then
    vim.fn.timer_stop(debounce_timer)
    debounce_timer = nil
  end
  if search_query == '' then
    search_results = {}
    render()
    return
  end
  searching = true
  render()
  debounce_timer = vim.fn.timer_start(DEBOUNCE_MS, function()
    vim.schedule(function()
      debounce_timer = nil
      local query = search_query
      require('ado.requests').search_identities(query, function(err, results)
        if search_query ~= query then return end
        searching = false
        if err then
          log.debug('assignee_picker: search error: %s', tostring(err))
          search_results = {}
        else
          search_results = results or {}
        end
        cursor_index = 1
        render()
      end)
    end)
  end)
end

--- Handle character input for the search field
---@param char string
local function handle_input(char)
  search_query = search_query .. char
  cursor_index = 1
  trigger_search()
end

--- Handle backspace in the search field
local function handle_backspace()
  if #search_query > 0 then
    search_query = search_query:sub(1, -2)
    cursor_index = 1
    trigger_search()
  end
end

--- Set up keymaps for the picker
local function setup_keymaps()
  if not picker_buf then return end

  local opts = { buffer = picker_buf, silent = true, nowait = true }

  -- Navigation
  vim.keymap.set('n', 'j', function()
    local items = build_items()
    if cursor_index < #items then
      cursor_index = cursor_index + 1
      update_cursor_display()
    end
  end, vim.tbl_extend('force', opts, { desc = 'Next item' }))

  vim.keymap.set('n', 'k', function()
    if cursor_index > 1 then
      cursor_index = cursor_index - 1
      update_cursor_display()
    end
  end, vim.tbl_extend('force', opts, { desc = 'Previous item' }))

  -- Select
  vim.keymap.set('n', '<CR>', function()
    local items = build_items()
    if #items == 0 then return end
    local selected = items[cursor_index]
    if not selected then return end
    local cb = on_select_callback
    M.close()
    if cb then
      if selected.type == 'clear' then
        cb('')
      else
        cb({ displayName = selected.displayName, email = selected.email })
      end
    end
  end, vim.tbl_extend('force', opts, { desc = 'Select assignee' }))

  -- Cancel
  vim.keymap.set('n', 'q', function()
    local cb = on_select_callback
    M.close()
    if cb then cb(nil) end
  end, vim.tbl_extend('force', opts, { desc = 'Cancel' }))

  vim.keymap.set('n', '<Esc>', function()
    local cb = on_select_callback
    M.close()
    if cb then cb(nil) end
  end, vim.tbl_extend('force', opts, { desc = 'Cancel' }))

  -- Direct character input: map letters for immediate typeahead
  for byte = 65, 90 do  -- A-Z
    local char = string.char(byte)
    vim.keymap.set('n', char, function()
      handle_input(char)
    end, opts)
  end
  for byte = 97, 122 do  -- a-z (skip j,k,q which are navigation/cancel)
    local char = string.char(byte)
    if char ~= 'j' and char ~= 'k' and char ~= 'q' then
      vim.keymap.set('n', char, function()
        handle_input(char)
      end, opts)
    end
  end
  for byte = 48, 57 do  -- 0-9
    local char = string.char(byte)
    vim.keymap.set('n', char, function()
      handle_input(char)
    end, opts)
  end
  -- Space, dot, hyphen, underscore, @
  for _, char in ipairs({ ' ', '.', '-', '_', '@' }) do
    vim.keymap.set('n', char, function()
      handle_input(char)
    end, opts)
  end

  vim.keymap.set('n', '<BS>', function()
    handle_backspace()
  end, vim.tbl_extend('force', opts, { desc = 'Backspace' }))
end

--- Open the assignee picker
---@param item table Work item being edited
---@param callback function Called with result: { displayName, email } | "" (clear) | nil (cancel)
function M.open(item, callback)
  on_select_callback = callback
  search_query = ''
  search_results = {}
  cursor_index = 1
  searching = false

  if debounce_timer then
    vim.fn.timer_stop(debounce_timer)
    debounce_timer = nil
  end

  local ui_config = config.get().ui
  local team_count = #(state.get('team_members') or {})
  local width = 50
  local height = math.max(12, 8 + math.min(team_count, 10))
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype = 'nofile'
  vim.bo[picker_buf].bufhidden = 'wipe'
  vim.bo[picker_buf].swapfile = false

  local title = string.format(' Assign Work Item #%d ', item.id or 0)
  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = ui_config.border,
    title = title,
    title_pos = 'center',
  })

  setup_keymaps()
  render()
end

--- Close the assignee picker
function M.close()
  if debounce_timer then
    vim.fn.timer_stop(debounce_timer)
    debounce_timer = nil
  end

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_close(picker_win, true)
  end

  picker_win = nil
  picker_buf = nil
  on_select_callback = nil
  search_query = ''
  search_results = {}
  cursor_index = 1
  searching = false
end

--- Check if the picker is open
---@return boolean
function M.is_open()
  return picker_win ~= nil and vim.api.nvim_win_is_valid(picker_win)
end

return M
