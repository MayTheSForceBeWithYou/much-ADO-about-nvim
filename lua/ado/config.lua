-- much-ADO-about-nvim configuration module
-- Manages plugin defaults and user overrides

local M = {}

---@class AdoConfig
---@field keymaps AdoKeymaps
---@field ui AdoUiConfig

---@class AdoKeymaps
---@field close string Key to close the UI
---@field select string Key to select an item
---@field refresh string Key to refresh the current view
---@field next_item string Key to move to next item
---@field prev_item string Key to move to previous item

---@class AdoUiConfig
---@field list_width number Width of the list pane (percentage or absolute)
---@field border string Border style for floating windows

---@type AdoConfig
local defaults = {
  keymaps = {
    close = 'q',
    select = '<CR>',
    refresh = 'R',
    next_item = 'j',
    prev_item = 'k',
  },
  ui = {
    list_width = 40,
    border = 'rounded',
  },
}

---@type AdoConfig
local current = vim.deepcopy(defaults)

--- Merge user options with defaults
---@param opts table|nil
function M.setup(opts)
  if opts then
    current = vim.tbl_deep_extend('force', defaults, opts)
  end
end

--- Get the current configuration
---@return AdoConfig
function M.get()
  return current
end

--- Get a specific configuration value by path
---@param path string Dot-separated path (e.g., 'keymaps.close')
---@return any
function M.get_value(path)
  local parts = vim.split(path, '.', { plain = true })
  local value = current

  for _, part in ipairs(parts) do
    if type(value) ~= 'table' then
      return nil
    end
    value = value[part]
  end

  return value
end

return M
