-- Minimal init for running tests with plenary.nvim
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

-- Add plenary to runtimepath (adjust path as needed)
local plenary_path = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'
if vim.fn.isdirectory(plenary_path) == 0 then
  plenary_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/plenary.nvim'
end

if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:append(plenary_path)
end

-- Add the plugin itself to runtimepath
vim.opt.runtimepath:append('.')

-- Load plenary
vim.cmd('runtime plugin/plenary.vim')
