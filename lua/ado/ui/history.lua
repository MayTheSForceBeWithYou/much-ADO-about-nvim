-- much-ADO-about-nvim UI history module
-- Renders the History tab in the work item detail pane.
-- Shows: (1) state-transition timeline, (2) chronological field-diff log.
-- This module MUST NOT call HTTP directly.

local M = {}

local log = require('ado.log')

-- ---------------------------------------------------------------------------
-- Field label map — common ADO field refs → readable labels
-- Unknown refs fall back to the raw reference name.
-- ---------------------------------------------------------------------------
local FIELD_LABELS = {
  ['System.State']                              = 'State',
  ['System.Title']                              = 'Title',
  ['System.AssignedTo']                         = 'Assigned To',
  ['System.AreaPath']                           = 'Area Path',
  ['System.IterationPath']                      = 'Iteration',
  ['System.Description']                        = 'Description',
  ['System.Reason']                             = 'Reason',
  ['System.Tags']                               = 'Tags',
  ['Microsoft.VSTS.Scheduling.Effort']          = 'Effort',
  ['Microsoft.VSTS.Scheduling.StoryPoints']     = 'Story Points',
  ['Microsoft.VSTS.Scheduling.RemainingWork']   = 'Remaining Work',
  ['Microsoft.VSTS.Scheduling.CompletedWork']   = 'Completed Work',
  ['Microsoft.VSTS.Common.Priority']            = 'Priority',
  ['Microsoft.VSTS.Common.Severity']            = 'Severity',
  ['Microsoft.VSTS.Common.AcceptanceCriteria']  = 'Acceptance Criteria',
  ['System.WorkItemType']                       = 'Work Item Type',
  ['System.TeamProject']                        = 'Team Project',
}

-- Internal system fields that carry no useful history information
local SKIP_FIELDS = {
  ['System.Rev']                            = true,
  ['System.AuthorizedDate']                 = true,
  ['System.RevisedDate']                    = true,
  ['System.AuthorizedAs']                   = true,
  ['System.ChangedDate']                    = true,
  ['System.ChangedBy']                      = true,
  ['System.Watermark']                      = true,
  ['Microsoft.VSTS.Common.StateChangeDate'] = true,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function field_label(ref)
  return FIELD_LABELS[ref] or ref
end

--- Format a field value for single-line display.
local function format_value(v)
  if v == nil then return '(empty)' end
  if type(v) == 'table' then
    return v.displayName or v.name or vim.json.encode(v)
  end
  local s = tostring(v)
  -- Collapse whitespace runs and cap length for readability
  s = s:gsub('%s+', ' ')
  if #s > 100 then s = s:sub(1, 97) .. '...' end
  return s
end

--- Format an ISO 8601 timestamp into a compact readable form.
--- "2024-01-15T10:30:00.000Z" → "2024-01-15 10:30 UTC"
local function format_date(iso)
  if not iso or iso == '' then return '?' end
  local date, time = iso:match('^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)')
  if date and time then return date .. ' ' .. time .. ' UTC' end
  return iso
end

-- ---------------------------------------------------------------------------
-- Tab bar (shared with detail.lua via this module)
-- ---------------------------------------------------------------------------

--- Return the two-line tab bar header.
---@param active string 'details', 'history', or 'comments'
---@return string[]
function M.tab_bar(active)
  local sep = string.rep('━', 50)
  local function mark(name, key)
    if active == key then
      return '▸ ' .. name
    end
    return '  ' .. name
  end
  return {
    string.format('  %s  %s  %s  (<Tab>)',
      mark('Details', 'details'),
      mark('History', 'history'),
      mark('Comments', 'comments')),
    '  ' .. sep,
    '',
  }
end

-- ---------------------------------------------------------------------------
-- Section builders
-- ---------------------------------------------------------------------------

--- Build the state-transition timeline block.
---@param updates table[] Raw update objects from the API
---@return string[]
local function build_timeline(updates)
  -- Collect state changes in chronological order (API returns rev 1 first)
  local transitions = {}
  for _, update in ipairs(updates) do
    local fields = update.fields or {}
    local sc = fields['System.State']
    if sc and sc.newValue then
      table.insert(transitions, {
        rev  = update.rev or 0,
        old  = sc.oldValue,
        new  = sc.newValue,
        by   = (update.revisedBy or {}).displayName or '?',
        date = format_date(update.revisedDate),
      })
    end
  end

  local lines = {}
  table.insert(lines, '  State Timeline')
  table.insert(lines, '  ' .. string.rep('─', 48))
  table.insert(lines, '')

  if #transitions == 0 then
    table.insert(lines, '  (no state changes recorded)')
    table.insert(lines, '')
    return lines
  end

  for i, t in ipairs(transitions) do
    if i > 1 then
      table.insert(lines, '         │')
      table.insert(lines, '         ▼')
    end
    -- First transition has no "from" state
    if t.old then
      table.insert(lines, string.format('  %-22s  →  %s', t.old, t.new))
    else
      table.insert(lines, string.format('  %s', t.new))
    end
    table.insert(lines, string.format('    by %-28s  %s', t.by, t.date))
  end

  table.insert(lines, '')
  return lines
end

--- Build the full chronological change-log (newest revision first).
---@param updates table[]
---@return string[]
local function build_change_log(updates)
  local lines = {}
  table.insert(lines, '  Change History')
  table.insert(lines, '  ' .. string.rep('─', 48))
  table.insert(lines, '')

  if #updates == 0 then
    table.insert(lines, '  (no revisions)')
    table.insert(lines, '')
    return lines
  end

  -- Iterate newest-first to match ADO browser ordering
  for i = #updates, 1, -1 do
    local update = updates[i]
    local rev    = update.rev or i
    local by     = (update.revisedBy or {}).displayName or '?'
    local date   = format_date(update.revisedDate)
    local fields = update.fields or {}

    -- Collect visible field changes
    local changed = {}
    for ref, change in pairs(fields) do
      if not SKIP_FIELDS[ref] then
        table.insert(changed, { ref = ref, old = change.oldValue, new = change.newValue })
      end
    end

    -- Skip revisions with no displayable changes (e.g. pure system bookkeeping)
    if #changed == 0 then goto continue end

    -- Sort: State first, then alphabetical by label
    table.sort(changed, function(a, b)
      if a.ref == 'System.State' then return true end
      if b.ref == 'System.State' then return false end
      return field_label(a.ref) < field_label(b.ref)
    end)

    -- Revision header
    table.insert(lines, string.format('  ┌─ Rev %-4d  %s  by %s', rev, date, by))

    for _, c in ipairs(changed) do
      local label   = field_label(c.ref)
      local new_str = format_value(c.new)
      if c.old ~= nil then
        local old_str = format_value(c.old)
        table.insert(lines, string.format('  │  %-22s %s  →  %s', label .. ':', old_str, new_str))
      else
        table.insert(lines, string.format('  │  %-22s %s', label .. ':', new_str))
      end
    end

    table.insert(lines, '  └' .. string.rep('─', 48))
    table.insert(lines, '')

    ::continue::
  end

  return lines
end

-- ---------------------------------------------------------------------------
-- Public render
-- ---------------------------------------------------------------------------

--- Render the History tab into buf.
--- Call with updates=nil to show a "Loading…" placeholder.
---@param buf     number        Buffer ID (the shared detail buffer)
---@param updates table[]|nil  Update records from work_items:get_updates; nil = loading
---@param err     string|nil   Error message if the API call failed
function M.render(buf, updates, err)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    log.debug('history.render: invalid buffer')
    return
  end

  local lines = {}

  -- Tab bar
  for _, l in ipairs(M.tab_bar('history')) do
    table.insert(lines, l)
  end

  if err then
    table.insert(lines, '  Error loading history:')
    table.insert(lines, '  ' .. tostring(err))
    table.insert(lines, '')
  elseif not updates then
    table.insert(lines, '  Loading history…')
    table.insert(lines, '')
  elseif #updates == 0 then
    table.insert(lines, '  No history available.')
    table.insert(lines, '')
  else
    -- Section 1 — state timeline
    for _, l in ipairs(build_timeline(updates)) do
      table.insert(lines, l)
    end

    table.insert(lines, '  ' .. string.rep('━', 50))
    table.insert(lines, '')

    -- Section 2 — field-diff log
    for _, l in ipairs(build_change_log(updates)) do
      table.insert(lines, l)
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  log.debug('history.render: wrote %d lines to buf %d', #lines, buf)
end

return M
