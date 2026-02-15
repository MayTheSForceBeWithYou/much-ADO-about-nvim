-- Tests for ado.sdk.auth module

describe('PatHandler', function()
  local PatHandler

  before_each(function()
    package.loaded['ado.sdk.auth.pat_handler'] = nil
    PatHandler = require('ado.sdk.auth.pat_handler')
  end)

  describe('new', function()
    it('creates handler with valid PAT', function()
      local handler = PatHandler.new('my-token')
      assert.is_not_nil(handler)
    end)

    it('rejects nil PAT', function()
      assert.has_error(function()
        PatHandler.new(nil)
      end)
    end)

    it('rejects empty string PAT', function()
      assert.has_error(function()
        PatHandler.new('')
      end)
    end)

    it('rejects non-string PAT', function()
      assert.has_error(function()
        PatHandler.new(12345)
      end)
    end)
  end)

  describe('prepare_request', function()
    it('adds Basic auth header', function()
      local handler = PatHandler.new('my-token')
      local headers = {}
      handler:prepare_request(headers)
      assert.equals('Basic ' .. vim.base64.encode(':my-token'), headers['Authorization'])
    end)

    it('preserves existing headers', function()
      local handler = PatHandler.new('my-token')
      local headers = { ['Content-Type'] = 'application/json' }
      handler:prepare_request(headers)
      assert.equals('application/json', headers['Content-Type'])
      assert.is_not_nil(headers['Authorization'])
    end)

    it('returns the headers table', function()
      local handler = PatHandler.new('my-token')
      local headers = {}
      local result = handler:prepare_request(headers)
      assert.equals(headers, result)
    end)
  end)

  describe('get_type', function()
    it('returns pat', function()
      local handler = PatHandler.new('my-token')
      assert.equals('pat', handler:get_type())
    end)
  end)
end)

describe('auth module', function()
  local auth

  before_each(function()
    package.loaded['ado.sdk.auth'] = nil
    package.loaded['ado.sdk.auth.pat_handler'] = nil
    auth = require('ado.sdk.auth')
  end)

  it('exposes pat factory', function()
    assert.is_function(auth.pat)
  end)

  it('creates PatHandler via pat()', function()
    local handler = auth.pat('test-token')
    assert.equals('pat', handler:get_type())
  end)
end)
