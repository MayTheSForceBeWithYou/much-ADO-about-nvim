-- much-ADO-about-nvim plugin entrypoint
-- Defines the :Ado command and initializes the plugin

if vim.g.loaded_ado then
  return
end
vim.g.loaded_ado = true

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
    return { 'help', 'workitems', 'controls' }
  end,
})
