-- much-ADO-about-nvim SDK client initialization
-- Centralized module for creating Azure DevOps clients via ADO_Lua_SDK
-- Uses require('ado.sdk') so this plugin's own lua/ado/init.lua is not shadowed.

local M = {}

--- Adapt the plugin log module to the SDK logger interface (msg, ctx).
---@param log table|nil
---@return table|nil
local function wrap_logger(log)
  if not log then
    return nil
  end
  local function fmt(msg, ctx)
    local s = tostring(msg)
    if ctx ~= nil then
      s = s .. ' ' .. vim.inspect(ctx)
    end
    return s
  end
  return {
    debug = function(msg, ctx)
      log.debug('%s', fmt(msg, ctx))
    end,
    info = function(msg, ctx)
      log.info('%s', fmt(msg, ctx))
    end,
    warn = function(msg, ctx)
      log.warn('%s', fmt(msg, ctx))
    end,
    error = function(msg, ctx)
      log.error('%s', fmt(msg, ctx))
    end,
  }
end

--- Create a new Azure DevOps client using the external SDK
---@param org_url string Organization URL (e.g. https://dev.azure.com/myorg)
---@param pat string Personal Access Token
---@param opts table|nil Optional: { log = log_module } for debug output
---@return table client
function M.create_connection(org_url, pat, opts)
  if type(org_url) == 'string' then
    org_url = org_url:gsub('[\r\n]', ''):gsub('^%s+', ''):gsub('%s+$', '')
  end
  if type(pat) == 'string' then
    pat = pat:gsub('[\r\n]', ''):gsub('^%s+', ''):gsub('%s+$', '')
  end
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
  local auth, auth_err = sdk.auth.pat(pat)
  if not auth then
    error(auth_err and auth_err.message or 'Failed to create PAT auth', 0)
  end
  local transport = (vim.system and 'vim') or 'curl'
  local client, err = sdk.new({
    base_url = org_url,
    auth = auth,
    transport = transport,
    logger = wrap_logger(opts.log),
  })
  if not client then
    error(err and err.message or 'Failed to create ADO client', 0)
  end
  return client
end

--- Return the current SDK client, creating it from env if needed.
---@return table|nil client
---@return string|nil error_message
function M.get()
  local state = require('ado.state')
  local client = state.get('connection')
  if client then
    return client, nil
  end
  local org_url = vim.env.ADO_ORG_URL
  local pat = vim.env.ADO_PAT
  if type(org_url) ~= 'string' or org_url == '' or type(pat) ~= 'string' or pat == '' then
    return nil, 'ADO_ORG_URL and ADO_PAT are required'
  end
  local ok, result = pcall(M.create_connection, org_url, pat, {
    log = require('ado.log'),
  })
  if not ok then
    return nil, tostring(result)
  end
  state.set('connection', result)
  return result, nil
end

return M
