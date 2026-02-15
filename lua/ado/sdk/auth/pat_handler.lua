-- Azure DevOps SDK PAT authentication handler
-- Implements ado.sdk.AuthHandler interface

---@class ado.sdk.PatHandler : ado.sdk.AuthHandler
---@field private _pat string The Personal Access Token
local PatHandler = {}
PatHandler.__index = PatHandler

--- Create a new PAT auth handler
---@param pat string Personal Access Token
---@return ado.sdk.PatHandler
function PatHandler.new(pat)
  assert(type(pat) == 'string' and pat ~= '', 'PAT must be a non-empty string')
  local self = setmetatable({}, PatHandler)
  self._pat = pat
  return self
end

--- Add authorization header to request headers
--- SECURITY: The PAT is encoded into the header here. Never log or expose
--- the returned headers in error messages or debug output.
---@param headers table<string,string> Existing headers table (mutated in place)
---@return table<string,string> The same headers table with Authorization added
function PatHandler:prepare_request(headers)
  headers['Authorization'] = 'Basic ' .. vim.base64.encode(':' .. self._pat)
  return headers
end

--- Get the auth type identifier
---@return string
function PatHandler:get_type()
  return 'pat'
end

return PatHandler
