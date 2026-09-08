-- Tests for ado.ado_client module

describe('ado_client', function()
  local ado_client

  before_each(function()
    package.loaded['ado.ado_client'] = nil
    ado_client = require('ado.ado_client')
  end)

  describe('create_connection input validation', function()
    it('errors when org_url is nil', function()
      assert.has_error(function()
        ado_client.create_connection(nil, 'mytoken')
      end, "create_connection: 'org_url' must be a non-empty string")
    end)

    it('errors when org_url is empty string', function()
      assert.has_error(function()
        ado_client.create_connection('', 'mytoken')
      end, "create_connection: 'org_url' must be a non-empty string")
    end)

    it('errors when org_url is not a string', function()
      assert.has_error(function()
        ado_client.create_connection(123, 'mytoken')
      end, "create_connection: 'org_url' must be a non-empty string")
    end)

    it('errors when pat is nil', function()
      assert.has_error(function()
        ado_client.create_connection('https://dev.azure.com/myorg', nil)
      end, "create_connection: 'pat' must be a non-empty string")
    end)

    it('errors when pat is empty string', function()
      assert.has_error(function()
        ado_client.create_connection('https://dev.azure.com/myorg', '')
      end, "create_connection: 'pat' must be a non-empty string")
    end)

    it('errors when pat is not a string', function()
      assert.has_error(function()
        ado_client.create_connection('https://dev.azure.com/myorg', false)
      end, "create_connection: 'pat' must be a non-empty string")
    end)
  end)
end)
