-- Azure DevOps SDK authentication module
-- Re-exports auth handler constructors

local M = {}

--- Create a PAT auth handler
---@param pat string Personal Access Token
---@return ado.sdk.PatHandler
function M.pat(pat)
  return require('ado.sdk.auth.pat_handler').new(pat)
end

return M
