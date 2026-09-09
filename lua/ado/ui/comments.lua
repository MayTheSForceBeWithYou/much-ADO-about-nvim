-- much-ADO-about-nvim UI comments module
-- Renders the Comments tab in the work item detail pane.
-- This module MUST NOT call HTTP directly.

local M = {}

local log = require('ado.log')
local state = require('ado.state')
local layout = require('ado.ui.layout')

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

local function wrap_text(text, width)
  local lines = {}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    if line == '' then
      table.insert(lines, '')
    else
      while #line > width do
        local break_pos = line:sub(1, width):match('.*()%s') or width
        table.insert(lines, line:sub(1, break_pos))
        line = line:sub(break_pos + 1)
      end
      if #line > 0 then
        table.insert(lines, line)
      end
    end
  end
  return lines
end

local function format_date(iso)
  if not iso or iso == '' then return '?' end
  local date, time = iso:match('^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)')
  if date and time then return date .. ' ' .. time .. ' UTC' end
  return iso
end

local function identity_name(val)
  if type(val) == 'table' then
    return val.displayName or val.uniqueName or '?'
  end
  if type(val) == 'string' and val ~= '' then
    return val
  end
  return '?'
end

--- Render the Comments tab into buf.
---@param buf number
---@param comments table[]|nil
---@param err string|nil
function M.render(buf, comments, err)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    log.debug('comments.render: invalid buffer')
    return
  end

  local history = require('ado.ui.history')
  local lines = {}
  for _, l in ipairs(history.tab_bar('comments')) do
    table.insert(lines, l)
  end

  table.insert(lines, '  c  add comment')
  table.insert(lines, '')

  if err then
    table.insert(lines, '  Error loading comments:')
    table.insert(lines, '  ' .. tostring(err))
    table.insert(lines, '')
  elseif not comments then
    table.insert(lines, '  Loading comments…')
    table.insert(lines, '')
  elseif #comments == 0 then
    table.insert(lines, '  No comments yet. Press c to add one.')
    table.insert(lines, '')
  else
    for _, comment in ipairs(comments) do
      local by = identity_name(comment.createdBy)
      local date = format_date(comment.createdDate)
      local raw = comment.text or comment.renderedText or ''
      if type(raw) ~= 'string' then
        raw = ''
      end
      local body = strip_html(raw)
      table.insert(lines, string.format('  ┌─ %s  %s', date, by))
      if body == '' then
        table.insert(lines, '  │  (empty)')
      else
        for _, text_line in ipairs(wrap_text(body, 56)) do
          table.insert(lines, '  │  ' .. text_line)
        end
      end
      table.insert(lines, '  └' .. string.rep('─', 48))
      table.insert(lines, '')
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  log.debug('comments.render: wrote %d lines to buf %d', #lines, buf)
end

--- Show the comments tab: loading placeholder then fetch.
---@param buf number|nil
function M.show(buf)
  buf = buf or layout.get_detail_buf()
  local item = state.get('selected_work_item')
  if not buf or not item then
    return
  end
  M.render(buf, nil, nil)
  require('ado.requests').load_comments(item.id, function(err, comments)
    local still = state.get('selected_work_item')
    if state.get('detail_tab') == 'comments'
        and still and still.id == item.id then
      M.render(buf, comments, err)
    end
  end)
end

return M
