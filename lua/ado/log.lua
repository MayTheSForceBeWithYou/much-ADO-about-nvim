-- much-ADO-about-nvim logging module
-- Debug logging toggled via config.debug

local M = {}

--- Get the current debug flag from config
---@return boolean
local function is_debug()
  -- Lazy require to avoid circular dependency at load time
  return require('ado.config').get().debug == true
end

--- Log a debug message (only when config.debug is true)
--- Shows in :messages with [ADO] prefix
---@param fmt string Format string
---@param ... any Format arguments
function M.debug(fmt, ...)
  if not is_debug() then return end
  local msg = string.format(fmt, ...)
  vim.notify('[ADO] ' .. msg, vim.log.levels.DEBUG)
end

--- Log an info message (always shown)
---@param fmt string Format string
---@param ... any Format arguments
function M.info(fmt, ...)
  local msg = string.format(fmt, ...)
  vim.notify('[ADO] ' .. msg, vim.log.levels.INFO)
end

--- Log a warning message (always shown)
---@param fmt string Format string
---@param ... any Format arguments
function M.warn(fmt, ...)
  local msg = string.format(fmt, ...)
  vim.notify('[ADO] ' .. msg, vim.log.levels.WARN)
end

--- Log an error message (always shown)
---@param fmt string Format string
---@param ... any Format arguments
function M.error(fmt, ...)
  local msg = string.format(fmt, ...)
  vim.notify('[ADO] ' .. msg, vim.log.levels.ERROR)
end

return M
