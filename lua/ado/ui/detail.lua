-- much-ADO-about-nvim UI detail module
-- Detail pane rendering for selected work items
-- This module MUST NOT call HTTP directly

local M = {}

local state = require('ado.state')
local layout = require('ado.ui.layout')

--- Format a field label and value for display
---@param label string Field label
---@param value any Field value
---@return string
local function format_field(label, value)
  if value == nil then
    value = '-'
  elseif type(value) == 'table' then
    -- Handle complex field values (e.g., identity fields)
    value = value.displayName or value.name or vim.json.encode(value)
  end
  return string.format('%-15s %s', label .. ':', tostring(value))
end

--- Wrap text to fit within a given width
---@param text string Text to wrap
---@param width number Maximum line width
---@return string[] lines
local function wrap_text(text, width)
  -- TODO: Implement proper text wrapping
  local lines = {}
  for line in text:gmatch('[^\n]+') do
    while #line > width do
      local break_pos = line:sub(1, width):match('.*()%s') or width
      table.insert(lines, line:sub(1, break_pos))
      line = line:sub(break_pos + 1)
    end
    if #line > 0 then
      table.insert(lines, line)
    end
  end
  return lines
end

--- Render the detail view for the selected work item
function M.render()
  local buf = layout.get_detail_buf()
  if not buf then return end

  local item = state.get('selected_work_item')
  local lines = {}

  if not item then
    lines = { 'No work item selected', '', 'Select an item from the list' }
  else
    local fields = item.fields or {}

    -- Header
    table.insert(lines, string.format('Work Item #%d', item.id or 0))
    table.insert(lines, string.rep('=', 40))
    table.insert(lines, '')

    -- Title
    local title = fields['System.Title'] or 'Untitled'
    table.insert(lines, title)
    table.insert(lines, '')

    -- Metadata
    table.insert(lines, format_field('Type', fields['System.WorkItemType']))
    table.insert(lines, format_field('State', fields['System.State']))
    table.insert(lines, format_field('Assigned To', fields['System.AssignedTo']))
    table.insert(lines, format_field('Area Path', fields['System.AreaPath']))
    table.insert(lines, format_field('Iteration', fields['System.IterationPath']))
    table.insert(lines, format_field('Created', fields['System.CreatedDate']))
    table.insert(lines, format_field('Changed', fields['System.ChangedDate']))
    table.insert(lines, '')

    -- Description
    table.insert(lines, 'Description:')
    table.insert(lines, string.rep('-', 40))
    local description = fields['System.Description'] or 'No description'
    -- TODO: Strip HTML from description
    -- For now, just display raw (may contain HTML)
    for _, line in ipairs(wrap_text(description, 60)) do
      table.insert(lines, line)
    end
    table.insert(lines, '')

    -- URL
    if item.url then
      table.insert(lines, '')
      table.insert(lines, 'URL: ' .. item.url)
    end
  end

  -- Update buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Clear the detail view
function M.clear()
  local buf = layout.get_detail_buf()
  if not buf then return end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].modifiable = false
end

return M
