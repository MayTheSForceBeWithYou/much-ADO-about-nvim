-- Tests for ado.sdk.http.rest_client module

describe('RestClient', function()
  local RestClient

  ---@return ado.sdk.AuthHandler
  local function mock_auth()
    return {
      prepare_request = function(_, h)
        h['Authorization'] = 'Basic dGVzdA=='
        return h
      end,
      get_type = function() return 'test' end,
    }
  end

  before_each(function()
    package.loaded['ado.sdk.http.rest_client'] = nil
    package.loaded['ado.sdk.http.errors'] = nil
    RestClient = require('ado.sdk.http.rest_client')
  end)

  describe('new', function()
    it('creates client with valid args', function()
      local client = RestClient.new('https://dev.azure.com/myorg', mock_auth())
      assert.is_not_nil(client)
    end)

    it('strips trailing slash from org_url', function()
      local client = RestClient.new('https://dev.azure.com/myorg/', mock_auth())
      assert.equals('https://dev.azure.com/myorg/_apis/test', client:build_url('test', nil))
    end)

    it('rejects empty org_url', function()
      assert.has_error(function()
        RestClient.new('', mock_auth())
      end)
    end)

    it('rejects nil auth_handler', function()
      assert.has_error(function()
        RestClient.new('https://example.com', nil)
      end)
    end)

    it('uses default api_version 7.0', function()
      local client = RestClient.new('https://example.com', mock_auth())
      assert.equals('7.0', client:get_api_version())
    end)

    it('accepts custom api_version', function()
      local client = RestClient.new('https://example.com', mock_auth(), { api_version = '7.1' })
      assert.equals('7.1', client:get_api_version())
    end)
  end)

  describe('build_url', function()
    it('builds org-level URL without project', function()
      local client = RestClient.new('https://dev.azure.com/myorg', mock_auth())
      assert.equals(
        'https://dev.azure.com/myorg/_apis/projects',
        client:build_url('projects', nil)
      )
    end)

    it('builds project-scoped URL', function()
      local client = RestClient.new('https://dev.azure.com/myorg', mock_auth())
      assert.equals(
        'https://dev.azure.com/myorg/MyProject/_apis/wit/wiql',
        client:build_url('wit/wiql', 'MyProject')
      )
    end)
  end)

  describe('encode_query', function()
    it('always includes api-version', function()
      local client = RestClient.new('https://example.com', mock_auth())
      local qs = client:encode_query(nil)
      assert.truthy(qs:match('api%-version=7%.0'))
    end)

    it('starts with ?', function()
      local client = RestClient.new('https://example.com', mock_auth())
      local qs = client:encode_query(nil)
      assert.equals('?', qs:sub(1, 1))
    end)

    it('includes additional params', function()
      local client = RestClient.new('https://example.com', mock_auth())
      local qs = client:encode_query({ ids = '1,2,3' })
      assert.truthy(qs:match('ids='))
      assert.truthy(qs:match('api%-version='))
    end)

    it('uri-encodes values', function()
      local client = RestClient.new('https://example.com', mock_auth())
      local qs = client:encode_query({ foo = 'hello world' })
      assert.truthy(qs:match('hello%%20world') or qs:match('hello%+world'))
    end)

    it('uses custom api-version from opts', function()
      local client = RestClient.new('https://example.com', mock_auth(), { api_version = '7.1' })
      local qs = client:encode_query(nil)
      assert.truthy(qs:match('api%-version=7%.1'))
    end)
  end)
end)
