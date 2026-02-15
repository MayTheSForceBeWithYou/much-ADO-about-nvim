-- Tests for ado.sdk.api.core_api module

describe('CoreApi', function()
  local CoreApi

  ---@return ado.sdk.RestClient
  local function mock_rest(response, mock_err)
    return {
      get = function(_, endpoint, project, query, callback)
        if mock_err then callback(mock_err, nil) return end
        callback(nil, response)
      end,
      post = function(_, endpoint, project, query, body, callback)
        if mock_err then callback(mock_err, nil) return end
        callback(nil, response)
      end,
    }
  end

  before_each(function()
    package.loaded['ado.sdk.api.core_api'] = nil
    package.loaded['ado.sdk.api.client_base'] = nil
    package.loaded['ado.sdk.http.errors'] = nil
    CoreApi = require('ado.sdk.api.core_api')
  end)

  describe('get_projects', function()
    it('returns projects from value field', function()
      local projects = { { name = 'P1' }, { name = 'P2' } }
      local api = CoreApi.new(mock_rest({ value = projects }))

      local result
      api:get_projects(function(_, p) result = p end)
      assert.same(projects, result)
    end)

    it('returns empty list when no value', function()
      local api = CoreApi.new(mock_rest({}))

      local result
      api:get_projects(function(_, p) result = p end)
      assert.same({}, result)
    end)

    it('propagates errors', function()
      local api_err = { message = 'fail', type = 'http', status_code = 500 }
      local api = CoreApi.new(mock_rest(nil, api_err))

      local got_err
      api:get_projects(function(e, _) got_err = e end)
      assert.equals('fail', got_err.message)
    end)
  end)

  describe('get_project', function()
    it('returns project data', function()
      local project = { id = 'guid', name = 'MyProject' }
      local api = CoreApi.new(mock_rest(project))

      local result
      api:get_project('MyProject', function(_, p) result = p end)
      assert.equals('MyProject', result.name)
    end)

    it('validates project_id is required', function()
      local api = CoreApi.new(mock_rest({}))

      local got_err
      api:get_project('', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates nil project_id', function()
      local api = CoreApi.new(mock_rest({}))

      local got_err
      api:get_project(nil, function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)
  end)
end)
