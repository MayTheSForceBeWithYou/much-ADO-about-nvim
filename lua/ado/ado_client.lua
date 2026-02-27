-- lua/ado/ado_client.lua
-- Singleton ADO Lua SDK client for much-ADO-about-nvim.
--
-- NAMESPACE NOTE
-- Both this plugin and the ADO Lua SDK define a module at "ado.config" with
-- incompatible APIs (plugin: ui/keymap config; SDK: request pipeline config).
-- _bootstrap() resolves this by temporarily prepending the SDK's lua/ dir to
-- package.path so that SDK modules load their own ado.config.  Once those
-- modules are loaded their upvalues hold the SDK config object permanently,
-- so we can safely restore package.path and package.loaded["ado.config"].

local M = {}
local _client  -- singleton SDK client

--- Bootstrap: load SDK's ado.client + ado.auth.pat while routing require()
--- for "ado.config" to the SDK's version instead of the plugin's.
--- Returns sdk_client_mod, sdk_auth_mod, errmsg.
local function _bootstrap()
  local sdk_path = os.getenv("ADO_LUA_SDK_DEV_PATH")

  if not sdk_path or sdk_path == "" then
    -- SDK might already be on package.path (future: installed as Neovim plugin)
    if not package.searchpath("ado.client", package.path) then
      return nil, nil,
        "ADO SDK not available. "
        .. "Set ADO_LUA_SDK_DEV_PATH=/path/to/ADO_Lua_SDK before starting Neovim "
        .. "(see docs/dev/SDK_DEV_SETUP.md)."
    end
    sdk_path = nil  -- already findable; skip path manipulation
  end

  -- Save current state so we can restore it unconditionally
  local saved_config = package.loaded["ado.config"]
  local saved_path   = package.path

  if sdk_path then
    -- PREPEND SDK path so SDK's ado/config.lua is found before the plugin's.
    -- The permanent SDK append (from plugin/ado.lua) remains at the end.
    package.path = sdk_path .. "/lua/?.lua;"
                .. sdk_path .. "/lua/?/init.lua;"
                .. package.path
  end

  -- Evict plugin's ado.config so require() hits the filesystem instead of cache
  package.loaded["ado.config"] = nil

  local ok1, sdk_client = pcall(require, "ado.client")
  local ok2, sdk_auth   = pcall(require, "ado.auth.pat")

  -- Restore package.path (removes the temporary prepend; the permanent append
  -- added by plugin/ado.lua is already embedded in saved_path)
  package.path = saved_path

  -- Restore plugin's ado.config (SDK modules already captured SDK's version
  -- in their module-level upvalues; package.loaded no longer matters to them)
  package.loaded["ado.config"] = saved_config

  if not ok1 then
    return nil, nil, "ado.client load error: " .. tostring(sdk_client)
  end
  if not ok2 then
    return nil, nil, "ado.auth.pat load error: " .. tostring(sdk_auth)
  end

  return sdk_client, sdk_auth, nil
end

--- Return the singleton SDK client, creating it on first call.
--- @return table|nil  client
--- @return string|nil errmsg
function M.get()
  if _client then return _client, nil end

  local sdk_client, sdk_auth, err = _bootstrap()
  if err then return nil, err end

  local org_url = vim.env.ADO_ORG_URL
  local pat     = vim.env.ADO_PAT

  if not org_url or org_url == "" then
    return nil, "ADO_ORG_URL not set"
  end
  if not pat or pat == "" then
    return nil, "ADO_PAT not set"
  end

  local auth, auth_err = sdk_auth.new(pat)
  if not auth then
    return nil, "Auth error: " .. (auth_err and auth_err.message or "unknown")
  end

  local client, client_err = sdk_client.new({
    base_url  = org_url,
    auth      = auth,
    transport = "vim",                   -- async via vim.system; never blocks UI
    cache     = { enabled = true, ttl = 60 },
  })
  if not client then
    return nil, "SDK client error: " .. (client_err and client_err.message or "unknown")
  end

  _client = client
  return _client, nil
end

--- Invalidate the singleton (call if ADO_ORG_URL or ADO_PAT changes at runtime).
function M.reset()
  _client = nil
end

return M
