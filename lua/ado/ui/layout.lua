-- much-ADO-about-nvim UI layout module
-- Window and split creation for the main interface
-- This module MUST NOT call HTTP directly

local M = {}

local config = require('ado.config')
local state = require('ado.state')

---@class AdoLayout
---@field list_win number|nil List pane window ID
---@field list_buf number|nil List pane buffer ID
---@field detail_win number|nil Detail pane window ID
---@field detail_buf number|nil Detail pane buffer ID

---@type AdoLayout
local layout = {
  list_win = nil,
  list_buf = nil,
  detail_win = nil,
  detail_buf = nil,
}

--- Check if the layout is currently open
---@return boolean
function M.is_open()
  return layout.list_win ~= nil and vim.api.nvim_win_is_valid(layout.list_win)
end

--- Delete any existing buffer with the given name
---@param name string Buffer name to find and delete
local function delete_existing_buffer(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ok, buf_name = pcall(vim.api.nvim_buf_get_name, buf)
      if ok and (buf_name == name or buf_name:match(vim.pesc(name) .. '$')) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
end

--- Create a scratch buffer (minimal setup - options set later)
---@return number bufnr
local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  if not buf or buf == 0 then
    return 0
  end
  -- Only set buftype initially - this prevents the buffer from being
  -- associated with a file and needing to be saved
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  return buf
end

--- Configure a buffer after it's attached to a window
--- This must be called AFTER the buffer is displayed in a window
---@param buf number Buffer ID
---@param name string Buffer name for identification
local function configure_buffer(buf, name)
  if not buf or buf == 0 or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Set name (for buffer list identification)
  pcall(vim.api.nvim_buf_set_name, buf, name)

  -- Now safe to set bufhidden=wipe since buffer is in a window
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'ado'
end

--- Set up common keymaps for a buffer
---@param buf number Buffer ID
local function setup_common_keymaps(buf)
  -- Guard: validate buffer before setting keymaps
  if not buf or buf == 0 or not vim.api.nvim_buf_is_valid(buf) then
    vim.notify('Cannot set keymaps: invalid buffer', vim.log.levels.ERROR)
    return
  end

  local keymaps = config.get().keymaps

  vim.keymap.set('n', keymaps.close, function()
    M.close()
  end, { buffer = buf, silent = true, nowait = true, desc = 'Close ADO browser' })

  vim.keymap.set('n', keymaps.refresh, function()
    require('ado').refresh()
  end, { buffer = buf, silent = true, nowait = true, desc = 'Refresh' })
end

--- Set up detail-specific keymaps (scrolling)
---@param buf number Buffer ID
local function setup_detail_keymaps(buf)
  -- Guard: validate buffer before setting keymaps
  if not buf or buf == 0 or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set('n', 'j', 'j', vim.tbl_extend('force', opts, { desc = 'Scroll down' }))
  vim.keymap.set('n', 'k', 'k', vim.tbl_extend('force', opts, { desc = 'Scroll up' }))
  vim.keymap.set('n', '<C-d>', '<C-d>', vim.tbl_extend('force', opts, { desc = 'Half page down' }))
  vim.keymap.set('n', '<C-u>', '<C-u>', vim.tbl_extend('force', opts, { desc = 'Half page up' }))
  vim.keymap.set('n', 'gg', 'gg', vim.tbl_extend('force', opts, { desc = 'Go to top' }))
  vim.keymap.set('n', 'G', 'G', vim.tbl_extend('force', opts, { desc = 'Go to bottom' }))

  -- Return to list pane
  vim.keymap.set('n', '<CR>', function()
    if layout.list_win and vim.api.nvim_win_is_valid(layout.list_win) then
      vim.api.nvim_set_current_win(layout.list_win)
    end
  end, vim.tbl_extend('force', opts, { desc = 'Back to list' }))
  vim.keymap.set('n', '<BS>', function()
    if layout.list_win and vim.api.nvim_win_is_valid(layout.list_win) then
      vim.api.nvim_set_current_win(layout.list_win)
    end
  end, vim.tbl_extend('force', opts, { desc = 'Back to list' }))
end

--- Open the work items layout (list + detail split)
function M.open_workitems()
  -- Always clean up first to handle stale state
  M.close()

  -- Clean up any leftover buffers with these names
  delete_existing_buffer('ado://workitems')
  delete_existing_buffer('ado://workitem-detail')

  -- Reset cursor state for fresh start
  require('ado.ui.list').reset_cursor()

  local ui_config = config.get().ui

  -- Step 1: Create buffers (minimal setup, NO bufhidden=wipe yet)
  layout.list_buf = create_buffer()
  layout.detail_buf = create_buffer()

  if layout.list_buf == 0 or layout.detail_buf == 0 then
    vim.notify('Failed to create buffers', vim.log.levels.ERROR)
    return
  end

  -- Step 2: Create windows and attach buffers BEFORE setting bufhidden=wipe
  -- This ensures buffers are "owned" by windows and won't be wiped
  -- Use the current window for the list (left), create a new split for detail (right)
  layout.list_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(layout.list_win, layout.list_buf)

  vim.cmd('rightbelow vsplit')
  layout.detail_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(layout.detail_win, layout.detail_buf)

  -- Set list width (focus list first since set_width applies to target window)
  vim.api.nvim_set_current_win(layout.list_win)
  vim.api.nvim_win_set_width(layout.list_win, ui_config.list_width)

  -- Step 3: Now configure buffers (including bufhidden=wipe) - safe because they're in windows
  configure_buffer(layout.list_buf, 'ado://workitems')
  configure_buffer(layout.detail_buf, 'ado://workitem-detail')

  -- Step 4: Set up keymaps (buffers are now fully configured and valid)
  setup_common_keymaps(layout.list_buf)
  setup_common_keymaps(layout.detail_buf)

  -- Set up list-specific keymaps
  require('ado.ui.list').setup_keymaps(layout.list_buf)

  -- Set up detail-specific keymaps
  setup_detail_keymaps(layout.detail_buf)

  -- Step 5: Load and render work items
  require('ado.requests').load_work_items(function()
    require('ado.ui.list').render()
  end)

  -- Focus list pane
  vim.api.nvim_set_current_win(layout.list_win)
end

--- Close the ADO layout
function M.close()
  -- Close windows (this will wipe buffers due to bufhidden=wipe)
  if layout.list_win and vim.api.nvim_win_is_valid(layout.list_win) then
    pcall(vim.api.nvim_win_close, layout.list_win, true)
  end
  if layout.detail_win and vim.api.nvim_win_is_valid(layout.detail_win) then
    pcall(vim.api.nvim_win_close, layout.detail_win, true)
  end

  -- Force delete buffers if they still exist (cleanup stale state)
  if layout.list_buf and vim.api.nvim_buf_is_valid(layout.list_buf) then
    pcall(vim.api.nvim_buf_delete, layout.list_buf, { force = true })
  end
  if layout.detail_buf and vim.api.nvim_buf_is_valid(layout.detail_buf) then
    pcall(vim.api.nvim_buf_delete, layout.detail_buf, { force = true })
  end

  -- Clear all references
  layout.list_win = nil
  layout.list_buf = nil
  layout.detail_win = nil
  layout.detail_buf = nil
end

--- Get the list buffer
---@return number|nil
function M.get_list_buf()
  return layout.list_buf
end

--- Get the detail buffer
---@return number|nil
function M.get_detail_buf()
  return layout.detail_buf
end

--- Get the list window
---@return number|nil
function M.get_list_win()
  return layout.list_win
end

--- Get the detail window
---@return number|nil
function M.get_detail_win()
  return layout.detail_win
end

return M
