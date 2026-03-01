-- much-ADO-about-nvim plugin entrypoint
-- Defines the :Ado command and initializes the plugin

if vim.g.loaded_ado then
  return
end
vim.g.loaded_ado = true

-- Add ADO_Lua_SDK to runtimepath for local development
-- SDK path: ADO_SDK_PATH env var, or ../ADO_Lua_SDK relative to plugin root
local function ensure_sdk_on_rtp()
  local sdk_path = vim.env.ADO_SDK_PATH
  if not sdk_path or sdk_path == '' then
    local plugin_root = vim.fn.fnamemodify(vim.fn.expand('<sfile>:p:h'), ':h')
    sdk_path = vim.fn.fnamemodify(plugin_root .. '/../ADO_Lua_SDK', ':p')
  end
  if vim.fn.isdirectory(sdk_path) == 1 then
    local rtp_entries = vim.opt.rtp:get()
    local already_present = false
    for _, entry in ipairs(rtp_entries) do
      if vim.fn.fnamemodify(entry, ':p') == sdk_path then
        already_present = true
        break
      end
    end
    if not already_present then
      vim.opt.rtp:prepend(sdk_path)
    end
  end
end
ensure_sdk_on_rtp()

-- Require Neovim 0.10+
if vim.fn.has('nvim-0.10') ~= 1 then
  vim.notify('much-ADO-about-nvim requires Neovim 0.10 or later', vim.log.levels.ERROR)
  return
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
