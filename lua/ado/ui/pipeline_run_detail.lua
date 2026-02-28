-- much-ADO-about-nvim UI pipeline run detail module
-- Floating window showing details for a selected pipeline run
-- This module MUST NOT call HTTP directly

local M = {}

local config = require('ado.config')
local log = require('ado.log')
local state = require('ado.state')

---@type number|nil Detail window ID
local detail_win = nil
---@type number|nil Detail buffer ID
local detail_buf = nil

--- Format a field label + value as a display line
---@param label string
---@param value any
---@return string
local function format_field(label, value)
  if value == nil or value == '' then
    value = '-'
  end
  return string.format('%-18s %s', label .. ':', tostring(value))
end

--- Compute a human-readable status from state + result
---@param run table Run data
---@return string
local function compute_status(run)
  local run_state = run.state or ''
  local result = run.result or ''
  if run_state == 'completed' then
    if result ~= '' then return result end
    return 'completed'
  elseif run_state == 'inProgress' then
    return 'in progress'
  elseif run_state == 'canceling' then
    return 'canceling'
  else
    return run_state ~= '' and run_state or 'unknown'
  end
end

--- Build the list of display lines for a run detail
---@param pipeline table Pipeline data
---@param run table Run data (may be full detail or list summary)
---@return string[]
local function build_lines(pipeline, run)
  local lines = {}

  -- Header
  local pipeline_name = pipeline.name or 'Pipeline'
  table.insert(lines, 'Run Detail: ' .. pipeline_name)
  table.insert(lines, string.rep('=', 50))
  table.insert(lines, '')

  -- Core fields
  table.insert(lines, format_field('Pipeline', pipeline_name))
  table.insert(lines, format_field('Pipeline ID', pipeline.id))
  table.insert(lines, format_field('Run ID', run.id))

  -- Branch from resources.repositories.self.refName
  local branch = '-'
  if run.resources and run.resources.repositories and run.resources.repositories.self then
    local ref = run.resources.repositories.self.refName or ''
    branch = ref:gsub('^refs/heads/', '')
    if branch == '' then branch = '-' end
  end
  table.insert(lines, format_field('Branch', branch))

  -- Commit SHA
  local sha = '-'
  if run.resources and run.resources.repositories and run.resources.repositories.self then
    sha = run.resources.repositories.self.version or '-'
  end
  table.insert(lines, format_field('Commit SHA', sha))

  -- Triggered reason / requested by
  local reason = run.reason or '-'
  table.insert(lines, format_field('Triggered by', reason))

  local requested_by = '-'
  if run.requestedBy then
    requested_by = run.requestedBy.displayName or run.requestedBy.uniqueName or '-'
  end
  table.insert(lines, format_field('Requested by', requested_by))

  -- Dates
  local started = run.createdDate or '-'
  if started ~= '-' then
    started = started:match('^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d)') or started
  end
  table.insert(lines, format_field('Started', started))

  local finished = run.finishedDate or '-'
  if finished ~= '-' then
    finished = finished:match('^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d)') or finished
  end
  table.insert(lines, format_field('Finished', finished))

  table.insert(lines, '')

  -- Status (prominent)
  local status = compute_status(run)
  table.insert(lines, format_field('State', run.state or '-'))
  table.insert(lines, format_field('Result', run.result or '-'))
  table.insert(lines, format_field('Status', status))

  -- URL
  if run._links and run._links.web and run._links.web.href then
    table.insert(lines, '')
    table.insert(lines, 'URL: ' .. run._links.web.href)
  elseif pipeline._links and pipeline._links.web and pipeline._links.web.href then
    table.insert(lines, '')
    table.insert(lines, 'URL: ' .. pipeline._links.web.href)
  end

  return lines
end

--- Set up keymaps for the detail window
local function setup_keymaps()
  if not detail_buf then return end

  local keymaps = config.get().keymaps

  vim.keymap.set('n', keymaps.close, function()
    M.close()
  end, { buffer = detail_buf, silent = true, desc = 'Close run detail' })

  -- Scrolling
  local opts = { buffer = detail_buf, silent = true }
  vim.keymap.set('n', 'j', 'j', vim.tbl_extend('force', opts, { desc = 'Scroll down' }))
  vim.keymap.set('n', 'k', 'k', vim.tbl_extend('force', opts, { desc = 'Scroll up' }))
  vim.keymap.set('n', 'gg', 'gg', vim.tbl_extend('force', opts, { desc = 'Go to top' }))
  vim.keymap.set('n', 'G', 'G', vim.tbl_extend('force', opts, { desc = 'Go to bottom' }))
  vim.keymap.set('n', '<C-d>', '<C-d>', vim.tbl_extend('force', opts, { desc = 'Half-page down' }))
  vim.keymap.set('n', '<C-u>', '<C-u>', vim.tbl_extend('force', opts, { desc = 'Half-page up' }))
end

--- Open the run detail view
---@param pipeline table Pipeline data
---@param run table Run data (initial, may be list summary; fetches full detail if possible)
function M.open(pipeline, run)
  -- Close any existing detail window
  M.close()

  local ui_config = config.get().ui
  local width = 70
  local height = 24
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  detail_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[detail_buf].buftype = 'nofile'
  vim.bo[detail_buf].bufhidden = 'wipe'
  vim.bo[detail_buf].swapfile = false

  detail_win = vim.api.nvim_open_win(detail_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = ui_config.border,
    title = ' Run #' .. tostring(run.id or '?') .. ' ',
    title_pos = 'center',
  })

  setup_keymaps()

  -- Render with available data immediately (may be partial)
  local lines = build_lines(pipeline, run)
  vim.bo[detail_buf].modifiable = true
  vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, lines)
  vim.bo[detail_buf].modifiable = false

  -- Fetch full run details in the background
  local conn = state.get('connection')
  local project = state.get('project')
  if conn and project and pipeline.id and run.id then
    log.debug('pipeline_run_detail: fetching full details for run #%d', run.id)
    conn:get_pipelines_api():get_run(project, pipeline.id, run.id, function(err, full_run)
      if err then
        log.debug('pipeline_run_detail: error fetching run details: %s', err.message or tostring(err))
        return
      end
      -- Re-render with full data if window is still open
      if detail_buf and vim.api.nvim_buf_is_valid(detail_buf) then
        local updated_lines = build_lines(pipeline, full_run)
        vim.bo[detail_buf].modifiable = true
        vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, updated_lines)
        vim.bo[detail_buf].modifiable = false
        log.debug('pipeline_run_detail: updated with full run data')
      end
    end)
  end
end

--- Close the detail window
function M.close()
  if detail_win and vim.api.nvim_win_is_valid(detail_win) then
    vim.api.nvim_win_close(detail_win, true)
  end
  detail_win = nil
  detail_buf = nil
end

--- Check if the detail window is open
---@return boolean
function M.is_open()
  return detail_win ~= nil and vim.api.nvim_win_is_valid(detail_win)
end

-- Expose helpers for testing
M._compute_status = compute_status
M._build_lines = build_lines

return M
