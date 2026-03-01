-- much-ADO-about-nvim UI pipeline runs list module
-- Floating picker listing runs for a selected pipeline
-- This module MUST NOT call HTTP directly

local M = {}

local config = require('ado.config')
local log = require('ado.log')
local state = require('ado.state')

---@type number|nil Picker window ID
local picker_win = nil
---@type number|nil Picker buffer ID
local picker_buf = nil
---@type table|nil Currently viewed pipeline
local current_pipeline = nil
---@type table[]|nil Cached runs list
local runs_cache = nil
---@type number Current cursor line (1-indexed)
local cursor_line = 1

--- Number of header lines before run entries
local HEADER_LINES = 3

--- Format a run state/result into a short status string
---@param run table Run data
---@return string
local function format_run_status(run)
  local run_state = run.state or ''
  local result = run.result or ''
  if run_state == 'completed' then
    if result == 'succeeded' then return 'succeeded'
    elseif result == 'failed' then return 'failed'
    elseif result == 'canceled' then return 'canceled'
    else return result ~= '' and result or 'completed'
    end
  elseif run_state == 'inProgress' then
    return 'in progress'
  elseif run_state == 'canceling' then
    return 'canceling'
  else
    return run_state ~= '' and run_state or 'unknown'
  end
end

--- Format a run for display
---@param run table Run data
---@return string
local function format_run(run)
  local id = run.id or '?'
  local status = format_run_status(run)
  -- Extract branch from resources.repositories.self.refName or pipeline.name
  local branch = ''
  if run.resources and run.resources.repositories and run.resources.repositories.self then
    local ref = run.resources.repositories.self.refName or ''
    branch = ref:gsub('^refs/heads/', '')
  end

  -- Created date (ISO 8601 → short form)
  local created = run.createdDate or ''
  if created ~= '' then
    created = created:match('^(%d%d%d%d%-%d%d%-%d%d)') or created
  end

  local branch_part = branch ~= '' and (' [' .. branch .. ']') or ''
  local date_part = created ~= '' and (' ' .. created) or ''
  return string.format('#%-6d %-12s%s%s', id, status, branch_part, date_part)
end

--- Render the runs list
local function render()
  if not picker_buf or not vim.api.nvim_buf_is_valid(picker_buf) then return end

  local lines = {}
  local pipeline_name = (current_pipeline and current_pipeline.name) or 'Pipeline'

  -- Header
  table.insert(lines, 'Runs: ' .. pipeline_name)
  table.insert(lines, string.rep('=', 40))
  table.insert(lines, '')

  local runs = runs_cache or {}

  if state.is_loading() then
    table.insert(lines, 'Loading runs...')
  elseif #runs == 0 then
    table.insert(lines, 'No runs found')
    table.insert(lines, '')
    table.insert(lines, 'This pipeline has not been run yet.')
  else
    for _, run in ipairs(runs) do
      table.insert(lines, format_run(run))
    end
  end

  vim.bo[picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].modifiable = false

  if picker_win and vim.api.nvim_win_is_valid(picker_win) and #runs > 0 then
    local first_line = HEADER_LINES + 1
    vim.api.nvim_win_set_cursor(picker_win, { first_line, 0 })
    cursor_line = first_line
  end
end

--- Select the current run and open its detail view
local function select_current()
  local runs = runs_cache or {}
  if #runs == 0 then return end

  local run_index = cursor_line - HEADER_LINES
  if run_index < 1 or run_index > #runs then return end

  local run = runs[run_index]
  if not run then return end

  log.debug('pipeline_runs_list: selected run #%d', run.id or 0)
  M.close()
  require('ado.ui.pipeline_run_detail').open(current_pipeline, run)
end

--- Move cursor by delta
---@param delta number
local function move_cursor(delta)
  local runs = runs_cache or {}
  if #runs == 0 then return end

  local first_line = HEADER_LINES + 1
  local last_line = HEADER_LINES + #runs

  cursor_line = cursor_line + delta
  cursor_line = math.max(first_line, math.min(cursor_line, last_line))

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_set_cursor(picker_win, { cursor_line, 0 })
  end
end

--- Set up keymaps
local function setup_keymaps()
  if not picker_buf then return end

  local keymaps = config.get().keymaps

  vim.keymap.set('n', keymaps.close, function()
    M.close()
  end, { buffer = picker_buf, silent = true, desc = 'Close runs list' })

  vim.keymap.set('n', keymaps.select, function()
    select_current()
  end, { buffer = picker_buf, silent = true, desc = 'Select run' })

  vim.keymap.set('n', keymaps.next_item, function()
    move_cursor(1)
  end, { buffer = picker_buf, silent = true, desc = 'Next run' })

  vim.keymap.set('n', keymaps.prev_item, function()
    move_cursor(-1)
  end, { buffer = picker_buf, silent = true, desc = 'Previous run' })

  vim.keymap.set('n', 'j', function()
    move_cursor(1)
  end, { buffer = picker_buf, silent = true })

  vim.keymap.set('n', 'k', function()
    move_cursor(-1)
  end, { buffer = picker_buf, silent = true })

  vim.keymap.set('n', keymaps.refresh, function()
    runs_cache = nil
    local pipeline = current_pipeline
    M.close()
    M.open(pipeline)
  end, { buffer = picker_buf, silent = true, desc = 'Refresh runs' })
end

--- Open the pipeline runs list for a given pipeline
---@param pipeline table Pipeline data (must have .id and .name)
function M.open(pipeline)
  current_pipeline = pipeline
  runs_cache = nil
  cursor_line = HEADER_LINES + 1

  local ui_config = config.get().ui
  local width = 70
  local height = 20
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype = 'nofile'
  vim.bo[picker_buf].bufhidden = 'wipe'
  vim.bo[picker_buf].swapfile = false

  local title = ' Runs: ' .. (pipeline.name or 'Pipeline') .. ' '
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

  -- Fetch runs
  local conn = state.get('connection')
  local project = state.get('project')
  if not conn or not project then
    vim.notify('No project configured.', vim.log.levels.ERROR)
    M.close()
    return
  end

  log.debug('pipeline_runs_list: fetching runs for pipeline #%d', pipeline.id or 0)
  conn:get_pipelines_api():list_runs(project, pipeline.id, { top = 50 }, function(err, runs)
    if err then
      log.debug('pipeline_runs_list: error: %s', err.message or tostring(err))
      if picker_buf and vim.api.nvim_buf_is_valid(picker_buf) then
        vim.bo[picker_buf].modifiable = true
        vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, {
          'Runs: ' .. (pipeline.name or 'Pipeline'),
          string.rep('=', 40),
          '',
          'Error: ' .. (err.message or tostring(err)),
        })
        vim.bo[picker_buf].modifiable = false
      end
      return
    end
    runs_cache = runs or {}
    log.debug('pipeline_runs_list: received %d runs', #runs_cache)
    render()
  end)
end

--- Close the runs list picker
function M.close()
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_close(picker_win, true)
  end
  picker_win = nil
  picker_buf = nil
  cursor_line = 1
end

--- Check if the picker is open
---@return boolean
function M.is_open()
  return picker_win ~= nil and vim.api.nvim_win_is_valid(picker_win)
end

-- Expose helpers for testing
M._format_run_status = format_run_status
M._format_run = format_run

return M
