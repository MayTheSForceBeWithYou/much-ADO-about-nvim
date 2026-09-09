-- much-ADO-about-nvim plugin entrypoint
-- Defines the :Ado command and initializes the plugin

if vim.g.loaded_ado then
  return
end
vim.g.loaded_ado = true

-- Add ADO_Lua_SDK to runtimepath for local development.
-- SDK path: ADO_SDK_PATH env var, or ../ADO_Lua_SDK relative to plugin root.
-- APPEND (do not prepend): the SDK also ships lua/ado/init.lua, so prepending
-- shadows this plugin's require('ado') and makes .setup / .open nil.
local function ensure_sdk_on_rtp()
  local plugin_root = vim.fn.fnamemodify(vim.fn.expand('<sfile>:p:h'), ':h')
  local sibling = vim.fn.fnamemodify(plugin_root .. '/../ADO_Lua_SDK', ':p')
  local sdk_path = vim.env.ADO_SDK_PATH
  if not sdk_path or sdk_path == '' or vim.fn.isdirectory(sdk_path) == 0 then
    sdk_path = sibling
  end
  if vim.fn.isdirectory(sdk_path) == 1 then
    local sdk_path_norm = vim.fn.fnamemodify(sdk_path, ':p')
    local already_present = false
    for _, entry in ipairs(vim.opt.rtp:get()) do
      if vim.fn.fnamemodify(entry, ':p') == sdk_path_norm then
        already_present = true
        break
      end
    end
    if not already_present then
      vim.opt.rtp:append(sdk_path)
    end
  end
end
ensure_sdk_on_rtp()

-- Require Neovim 0.10+
if vim.fn.has('nvim-0.10') ~= 1 then
  vim.notify('much-ADO-about-nvim requires Neovim 0.10 or later', vim.log.levels.ERROR)
  return
end

-- Dev-only: load ADO Lua SDK from a local checkout.
-- Set ADO_LUA_SDK_DEV_PATH=/path/to/ADO_Lua_SDK before starting Neovim.
-- Appended (not prepended) so the plugin's own ado.* modules take priority
-- for shared module names; SDK-only modules (ado.client, ado.core.*, etc.)
-- are found here.  The ado.config name collision is resolved in ado_client.lua.
local _dev_sdk = os.getenv("ADO_LUA_SDK_DEV_PATH")
if _dev_sdk and _dev_sdk ~= "" then
  package.path = package.path
    .. ";" .. _dev_sdk .. "/lua/?.lua"
    .. ";" .. _dev_sdk .. "/lua/?/init.lua"
end

vim.api.nvim_create_user_command('Ado', function(opts)
  require('ado').open(opts.args)
end, {
  nargs = '?',
  desc = 'Open Azure DevOps browser',
  complete = function()
    return { 'help', 'workitems', 'pipelines', 'controls' }
  end,
})
