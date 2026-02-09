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

vim.api.nvim_create_user_command('Ado', function(opts)
  require('ado').open(opts.args)
end, {
  nargs = '?',
  desc = 'Open Azure DevOps browser',
  complete = function()
    return { 'help', 'workitems' }
  end,
})
