-- much-ADO-about-nvim UI pipelines list module
-- Floating picker listing all pipelines in the current project
-- This module MUST NOT call HTTP directly

local M = {}

local config = require('ado.config')
local log = require('ado.log')
local state = require('ado.state')

---@type number|nil Picker window ID
local picker_win = nil
---@type number|nil Picker buffer ID
local picker_buf = nil
---@type table[]|nil Cached pipelines list
local pipelines_cache = nil
---@type number Current cursor line (1-indexed)
local cursor_line = 1

--- Number of header lines before pipeline entries
local HEADER_LINES = 3

--- Format a pipeline for display
---@param pipeline table Pipeline data
---@return string
local function format_pipeline(pipeline)
  local id = pipeline.id or '?'
  local name = pipeline.name or 'Unnamed'
  local folder = pipeline.folder or ''
  if folder == '\\' or folder == '' then
    folder = ''
  else
    folder = folder:gsub('^\\', '') .. '\\'
  end
  return string.format('#%-5d %s%s', id, folder, name)
end

--- Render the pipelines list
local function render()
  if not picker_buf or not vim.api.nvim_buf_is_valid(picker_buf) then return end

  local lines = {}

  -- Header
  table.insert(lines, 'Pipelines')
  table.insert(lines, string.rep('=', 40))
  table.insert(lines, '')

  local pipelines = pipelines_cache or {}

  if state.is_loading() then
    table.insert(lines, 'Loading pipelines...')
  elseif #pipelines == 0 then
    table.insert(lines, 'No pipelines found')
    table.insert(lines, '')
    table.insert(lines, 'Check your project configuration and PAT permissions.')
  else
    for _, pipeline in ipairs(pipelines) do
      table.insert(lines, format_pipeline(pipeline))
    end
  end

  vim.bo[picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].modifiable = false

  -- Position cursor on first pipeline
  if picker_win and vim.api.nvim_win_is_valid(picker_win) and #pipelines > 0 then
    local first_line = HEADER_LINES + 1
    vim.api.nvim_win_set_cursor(picker_win, { first_line, 0 })
    cursor_line = first_line
  end
end

--- Select the current pipeline and open its runs list
local function select_current()
  local pipelines = pipelines_cache or {}
  if #pipelines == 0 then return end

  local pipeline_index = cursor_line - HEADER_LINES
  if pipeline_index < 1 or pipeline_index > #pipelines then return end

  local pipeline = pipelines[pipeline_index]
  if not pipeline then return end

  log.debug('pipelines_list: selected pipeline #%d "%s"', pipeline.id or 0, pipeline.name or '')
  M.close()
  require('ado.ui.pipeline_runs_list').open(pipeline)
end

--- Move cursor by delta
---@param delta number
local function move_cursor(delta)
  local pipelines = pipelines_cache or {}
  if #pipelines == 0 then return end

  local first_line = HEADER_LINES + 1
  local last_line = HEADER_LINES + #pipelines

  cursor_line = cursor_line + delta
  cursor_line = math.max(first_line, math.min(cursor_line, last_line))

  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_set_cursor(picker_win, { cursor_line, 0 })
  end
end

--- Set up keymaps for the picker
local function setup_keymaps()
  if not picker_buf then return end

  local keymaps = config.get().keymaps

  vim.keymap.set('n', keymaps.close, function()
    M.close()
  end, { buffer = picker_buf, silent = true, desc = 'Close pipelines list' })

  vim.keymap.set('n', keymaps.select, function()
    select_current()
  end, { buffer = picker_buf, silent = true, desc = 'Select pipeline' })

  vim.keymap.set('n', keymaps.next_item, function()
    move_cursor(1)
  end, { buffer = picker_buf, silent = true, desc = 'Next pipeline' })

  vim.keymap.set('n', keymaps.prev_item, function()
    move_cursor(-1)
  end, { buffer = picker_buf, silent = true, desc = 'Previous pipeline' })

  vim.keymap.set('n', 'j', function()
    move_cursor(1)
  end, { buffer = picker_buf, silent = true })

  vim.keymap.set('n', 'k', function()
    move_cursor(-1)
  end, { buffer = picker_buf, silent = true })

  vim.keymap.set('n', keymaps.refresh, function()
    pipelines_cache = nil
    M.open()
  end, { buffer = picker_buf, silent = true, desc = 'Refresh pipelines' })
end

--- Open the pipelines list picker
function M.open()
  -- Reuse existing window if already open
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_set_current_win(picker_win)
    return
  end

  cursor_line = HEADER_LINES + 1

  local ui_config = config.get().ui
  local width = 60
  local height = 20
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype = 'nofile'
  vim.bo[picker_buf].bufhidden = 'wipe'
  vim.bo[picker_buf].swapfile = false

  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = ui_config.border,
    title = ' Azure DevOps Pipelines ',
    title_pos = 'center',
  })

  setup_keymaps()
  render()

  -- Fetch pipelines if not cached
  if not pipelines_cache then
    local conn = state.get('connection')
    local project = state.get('project')
    if not conn or not project then
      vim.notify('No project configured. Set ADO_PROJECT or select a project first.', vim.log.levels.ERROR)
      M.close()
      return
    end
    log.debug('pipelines_list: fetching pipelines for project=%s', project)
    conn:get_pipelines_api():list_pipelines(project, function(err, pipelines)
      if err then
        log.debug('pipelines_list: error: %s', err.message or tostring(err))
        if picker_buf and vim.api.nvim_buf_is_valid(picker_buf) then
          vim.bo[picker_buf].modifiable = true
          vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, {
            'Pipelines',
            string.rep('=', 40),
            '',
            'Error: ' .. (err.message or tostring(err)),
          })
          vim.bo[picker_buf].modifiable = false
        end
        return
      end
      pipelines_cache = pipelines or {}
      log.debug('pipelines_list: received %d pipelines', #pipelines_cache)
      render()
    end)
  end
end

--- Close the pipelines list picker
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

return M
