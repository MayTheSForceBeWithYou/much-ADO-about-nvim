-- much-ADO-about-nvim SDK client initialization
-- Centralized module for creating Azure DevOps connections via ADO_Lua_SDK
-- All org URL, PAT, and SDK options flow through here

local M = {}

--- Create a new Azure DevOps connection using the external SDK
---@param org_url string Organization URL (e.g. https://dev.azure.com/myorg)
---@param pat string Personal Access Token
---@param opts table|nil Optional: { log = log_module } for debug output
---@return ado.sdk.Connection
function M.create_connection(org_url, pat, opts)
  if type(org_url) ~= 'string' or org_url == '' then
    error("create_connection: 'org_url' must be a non-empty string", 2)
  end
  if type(pat) ~= 'string' or pat == '' then
    error("create_connection: 'pat' must be a non-empty string", 2)
  end
  local ok, sdk = pcall(require, 'ado.sdk')
  if not ok then
    error(
      "Failed to load 'ado.sdk'. Make sure ADO_Lua_SDK is installed and on your runtimepath, " ..
      "or set ADO_SDK_PATH so that 'ado.sdk' can be required.",
      0
    )
  end
  opts = opts or {}
  local sdk_opts = {
    log = opts.log,
  }
  return sdk.new(org_url, sdk.auth.pat(pat), sdk_opts)
end

return M
