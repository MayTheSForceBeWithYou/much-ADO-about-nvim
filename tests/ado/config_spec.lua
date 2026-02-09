-- Tests for ado.config module

describe('config', function()
  local config

  before_each(function()
    -- Clear module cache to get fresh config
    package.loaded['ado.config'] = nil
    config = require('ado.config')
  end)

  describe('defaults', function()
    it('has default keymaps', function()
      local cfg = config.get()
      assert.equals('q', cfg.keymaps.close)
      assert.equals('<CR>', cfg.keymaps.select)
      assert.equals('R', cfg.keymaps.refresh)
      assert.equals('j', cfg.keymaps.next_item)
      assert.equals('k', cfg.keymaps.prev_item)
    end)

    it('has default ui settings', function()
      local cfg = config.get()
      assert.equals(40, cfg.ui.list_width)
      assert.equals('rounded', cfg.ui.border)
    end)
  end)

  describe('setup', function()
    it('merges user options with defaults', function()
      config.setup({
        keymaps = {
          close = '<Esc>',
        },
      })

      local cfg = config.get()
      assert.equals('<Esc>', cfg.keymaps.close)
      assert.equals('<CR>', cfg.keymaps.select) -- unchanged default
    end)

    it('handles nil options', function()
      config.setup(nil)
      local cfg = config.get()
      assert.equals('q', cfg.keymaps.close)
    end)

    it('deep merges nested options', function()
      config.setup({
        ui = {
          list_width = 60,
        },
      })

      local cfg = config.get()
      assert.equals(60, cfg.ui.list_width)
      assert.equals('rounded', cfg.ui.border) -- unchanged default
    end)
  end)

  describe('get_value', function()
    it('retrieves nested values by path', function()
      assert.equals('q', config.get_value('keymaps.close'))
      assert.equals(40, config.get_value('ui.list_width'))
    end)

    it('returns nil for invalid paths', function()
      assert.is_nil(config.get_value('nonexistent'))
      assert.is_nil(config.get_value('keymaps.nonexistent'))
    end)

    it('returns nil when path goes through non-table', function()
      assert.is_nil(config.get_value('keymaps.close.foo'))
    end)
  end)
end)
