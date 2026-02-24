-- much-ADO-about-nvim UI detail module
-- Detail pane rendering for selected work items
-- This module MUST NOT call HTTP directly

local M = {}

local log = require('ado.log')
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

--- Strip HTML tags and decode common entities
---@param text string HTML text
---@return string
local function strip_html(text)
  text = text:gsub('<br%s*/?>', '\n')
  text = text:gsub('<p.->', '\n')
  text = text:gsub('</p>', '')
  text = text:gsub('<div.->', '\n')
  text = text:gsub('</div>', '')
  text = text:gsub('<[^>]+>', '')
  text = text:gsub('&nbsp;', ' ')
  text = text:gsub('&amp;', '&')
  text = text:gsub('&lt;', '<')
  text = text:gsub('&gt;', '>')
  text = text:gsub('&quot;', '"')
  text = text:gsub('\n\n\n+', '\n\n')
  return vim.trim(text)
end

--- Wrap text to fit within a given width
---@param text string Text to wrap
---@param width number Maximum line width
---@return string[] lines
local function wrap_text(text, width)
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

--- Format a field value, stripping HTML for HtmlFieldControl types
---@param value any Field value
---@param control_type string|nil Control type identifier
---@return string
local function format_value(value, control_type)
  if value == nil then return '-' end
  if type(value) == 'table' then
    return value.displayName or value.name or vim.json.encode(value)
  end
  local s = tostring(value)
  if control_type == 'HtmlFieldControl' then
    s = strip_html(s)
  end
  return s
end

--- Render fallback (hardcoded fields) when no layout is available
---@param item table Work item
---@return string[]
local function render_fallback(item)
  local lines = {}
  local fields = item.fields or {}

  -- Header
  table.insert(lines, string.format('Work Item #%d', item.id or 0))
  table.insert(lines, string.rep('=', 40))
  table.insert(lines, '')

  -- Title
  table.insert(lines, fields['System.Title'] or 'Untitled')
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
  description = strip_html(description)
  for _, line in ipairs(wrap_text(description, 60)) do
    table.insert(lines, line)
  end
  table.insert(lines, '')

  -- URL
  if item.url then
    table.insert(lines, '')
    table.insert(lines, 'URL: ' .. item.url)
  end

  return lines
end

--- Render layout-driven detail view
---@param item table Work item
---@param form_layout ado.sdk.FormLayout Form layout
---@return string[]
local function render_with_layout(item, form_layout)
  local lines = {}
  local fields = item.fields or {}
  local wit_type = fields['System.WorkItemType'] or ''

  -- Header
  table.insert(lines, string.format('Work Item #%d', item.id or 0))
  table.insert(lines, string.rep('\u{2550}', 40))
  table.insert(lines, '')

  -- Title line: "Type: Title"
  local title = fields['System.Title'] or 'Untitled'
  if wit_type ~= '' then
    table.insert(lines, wit_type .. ': ' .. title)
  else
    table.insert(lines, title)
  end
  table.insert(lines, '')

  -- System controls (State, Assigned To, Area, Iteration)
  local system_fields = {
    'System.State',
    'System.AssignedTo',
    'System.AreaPath',
    'System.IterationPath',
  }
  for _, sys_id in ipairs(system_fields) do
    -- Find the matching system control for its label
    local label = sys_id:match('%.([^.]+)$') or sys_id
    if form_layout.systemControls then
      for _, ctrl in ipairs(form_layout.systemControls) do
        if ctrl.id == sys_id then
          label = ctrl.label or label
          break
        end
      end
    end
    -- Convert camelCase/PascalCase to spaced: "AreaPath" → "Area Path"
    label = label:gsub('(%l)(%u)', '%1 %2')
    table.insert(lines, format_field(label, fields[sys_id]))
  end
  table.insert(lines, '')

  -- Pages (skip non-field pages)
  local skip_page_types = { history = true, links = true, attachments = true }
  for _, page in ipairs(form_layout.pages or {}) do
    if page.visible ~= false and not skip_page_types[page.pageType] then
      -- Page header
      local page_label = page.label or ''
      if page_label ~= '' then
        table.insert(lines, string.format('\u{2500}\u{2500} %s %s', page_label, string.rep('\u{2500}', math.max(1, 37 - #page_label))))
      end

      for _, section in ipairs(page.sections or {}) do
        for _, group in ipairs(section.groups or {}) do
          if group.visible ~= false and group.controls and #group.controls > 0 then
            -- Group heading
            local group_label = group.label or ''
            if group_label ~= '' then
              table.insert(lines, string.format('  \u{2500}\u{2500} %s \u{2500}\u{2500}', group_label))
            end

            for _, control in ipairs(group.controls) do
              if control.visible ~= false and control.id and control.id ~= '' then
                local val = fields[control.id]
                local formatted = format_value(val, control.controlType)

                -- Multi-line HTML fields get special treatment
                if control.controlType == 'HtmlFieldControl' and val and tostring(val) ~= '' then
                  local cleaned = strip_html(tostring(val))
                  if cleaned ~= '' then
                    table.insert(lines, '')
                    local ctrl_label = control.label or control.id:match('%.([^.]+)$') or control.id
                    table.insert(lines, string.format('\u{2500}\u{2500} %s %s', ctrl_label, string.rep('\u{2500}', math.max(1, 37 - #ctrl_label))))
                    for _, text_line in ipairs(wrap_text(cleaned, 60)) do
                      table.insert(lines, '  ' .. text_line)
                    end
                  end
                else
                  local ctrl_label = control.label or control.id:match('%.([^.]+)$') or control.id
                  table.insert(lines, '  ' .. format_field(ctrl_label, formatted))
                end
              end
            end
          end
        end
      end
      table.insert(lines, '')
    end
  end

  return lines
end

--- Render the detail view for the selected work item
function M.render()
  local buf = layout.get_detail_buf()
  if not buf then
    log.debug('detail.render: no detail buffer, skipping')
    return
  end

  local item = state.get('selected_work_item')
  local lines

  if not item then
    log.debug('detail.render: no selected work item')
    lines = { 'No work item selected', '', 'Select an item from the list' }
  else
    -- Check for cached layout
    local wit_type = (item.fields or {})['System.WorkItemType']
    local layouts = state.get('layouts') or {}
    local form_layout = wit_type and layouts[wit_type]

    if form_layout then
      log.debug('detail.render: using layout for #%d (type "%s")', item.id or 0, wit_type or '?')
      lines = render_with_layout(item, form_layout)
    else
      log.debug('detail.render: fallback for #%d (type=%s, loading=%s)',
        item.id or 0, vim.inspect(wit_type), tostring(state.is_loading()))
      lines = render_fallback(item)
      -- Show loading hint if layout is being fetched
      if wit_type and not form_layout and state.is_loading() then
        table.insert(lines, '')
        table.insert(lines, 'Loading layout...')
      end
    end
  end

  -- Update buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  log.debug('detail.render: wrote %d lines to buf %d', #lines, buf)

  -- Ensure the detail window is actually displaying this buffer
  local win = layout.get_detail_win()
  if win and vim.api.nvim_win_is_valid(win) then
    if vim.api.nvim_win_get_buf(win) ~= buf then
      log.debug('detail.render: detail_win %d was showing buf %d, reattaching buf %d',
        win, vim.api.nvim_win_get_buf(win), buf)
      vim.api.nvim_win_set_buf(win, buf)
    end
  else
    log.debug('detail.render: detail_win is invalid or nil (%s)', vim.inspect(win))
  end

  log.debug('detail.render: wrote %d lines to buf %d', #lines, buf)
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
