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

-- Add ADO_Lua_SDK to runtimepath (local dependency for tests)
local sdk_path = vim.env.ADO_SDK_PATH
if not sdk_path or sdk_path == '' then
  sdk_path = vim.fn.fnamemodify(vim.fn.getcwd() .. '/../ADO_Lua_SDK', ':p')
end
-- Append so the plugin's lua/ado wins over the SDK's lua/ado package name.
if vim.fn.isdirectory(sdk_path) == 1 then
  vim.opt.runtimepath:append(sdk_path)
end

-- Load plenary
vim.cmd('runtime plugin/plenary.vim')
