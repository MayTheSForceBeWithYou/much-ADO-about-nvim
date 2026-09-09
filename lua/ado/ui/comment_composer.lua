-- much-ADO-about-nvim UI comment composer
-- Floating buffer to write a new work item comment.
-- This module MUST NOT call HTTP directly.

local M = {}

local config = require('ado.config')
local state = require('ado.state')

---@type number|nil
local composer_win = nil
---@type number|nil
local composer_buf = nil
---@type boolean
local submitting = false

local function close()
  if composer_win and vim.api.nvim_win_is_valid(composer_win) then
    pcall(vim.api.nvim_win_close, composer_win, true)
  end
  composer_win = nil
  composer_buf = nil
  submitting = false
end

local function to_html(text)
  text = vim.trim(text)
  text = text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
  text = text:gsub('\n', '<br>')
  return text
end

local function submit()
  if submitting then
    return
  end
  if not composer_buf or not vim.api.nvim_buf_is_valid(composer_buf) then
    return
  end
  local item = state.get('selected_work_item')
  if not item or not item.id then
    vim.notify('No work item selected', vim.log.levels.ERROR)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(composer_buf, 0, -1, false)
  local text = table.concat(lines, '\n')
  if not text:match('%S') then
    vim.notify('Comment is empty', vim.log.levels.WARN)
    return
  end
  submitting = true
  require('ado.requests').add_comment(item.id, to_html(text), function(err)
    submitting = false
    if err then
      vim.notify('Failed to add comment: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
    close()
    vim.notify('Comment added', vim.log.levels.INFO)
    require('ado.ui.layout').show_detail_tab('comments')
  end)
end

--- Open the comment composer for the selected work item
function M.open()
  local item = state.get('selected_work_item')
  if not item or not item.id then
    vim.notify('No work item selected', vim.log.levels.ERROR)
    return
  end

  if composer_win and vim.api.nvim_win_is_valid(composer_win) then
    vim.api.nvim_set_current_win(composer_win)
    vim.cmd('startinsert')
    return
  end

  local ui_config = config.get().ui
  local width = math.min(72, math.max(40, vim.o.columns - 8))
  local height = math.min(12, math.max(6, vim.o.lines - 8))
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  composer_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[composer_buf].buftype = 'nofile'
  vim.bo[composer_buf].bufhidden = 'wipe'
  vim.bo[composer_buf].swapfile = false
  vim.bo[composer_buf].filetype = 'markdown'

  composer_win = vim.api.nvim_open_win(composer_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = ui_config.border,
    title = ' New comment  <C-s> post  q cancel ',
    title_pos = 'center',
  })
  vim.wo[composer_win].wrap = true

  local opts = { buffer = composer_buf, silent = true, nowait = true }
  vim.keymap.set('n', 'q', close, vim.tbl_extend('force', opts, { desc = 'Cancel comment' }))
  vim.keymap.set('n', '<Esc>', close, vim.tbl_extend('force', opts, { desc = 'Cancel comment' }))
  vim.keymap.set('n', '<C-s>', submit, vim.tbl_extend('force', opts, { desc = 'Post comment' }))
  vim.keymap.set('i', '<C-s>', function()
    vim.cmd('stopinsert')
    submit()
  end, vim.tbl_extend('force', opts, { desc = 'Post comment' }))

  submitting = false
  vim.cmd('startinsert')
end

function M.close()
  close()
end

return M
