-- Integration tests for Azure DevOps SDK
-- End-to-end tests with mocked vim.system

describe('SDK integration', function()
  local original_system
  local sdk

  before_each(function()
    original_system = vim.system
    -- Clear all SDK module caches
    for key, _ in pairs(package.loaded) do
      if key:match('^ado%.sdk') then
        package.loaded[key] = nil
      end
    end
    sdk = require('ado.sdk')
  end)

  after_each(function()
    vim.system = original_system
  end)

  it('fetches projects end-to-end', function()
    local projects_json = vim.json.encode({
      count = 2,
      value = {
        { id = 'guid-1', name = 'Project1', state = 'wellFormed' },
        { id = 'guid-2', name = 'Project2', state = 'wellFormed' },
      },
    })

    vim.system = function(_, _, cb)
      vim.schedule(function()
        cb({ code = 0, stdout = projects_json .. '\n200', stderr = '' })
      end)
      return {}
    end

    local conn = sdk.new('https://dev.azure.com/testorg', sdk.auth.pat('test-pat'))
    local core = conn:get_core_api()

    local result, got_err
    core:get_projects(function(err, projects)
      got_err = err
      result = projects
    end)

    assert.is_nil(got_err)
    assert.equals(2, #result)
    assert.equals('Project1', result[1].name)
    assert.equals('Project2', result[2].name)
  end)

  it('handles HTTP 401 end-to-end', function()
    vim.system = function(_, _, cb)
      vim.schedule(function()
        cb({ code = 0, stdout = '{"message":"Unauthorized"}\n401', stderr = '' })
      end)
      return {}
    end

    local conn = sdk.new('https://dev.azure.com/testorg', sdk.auth.pat('bad-pat'))
    local core = conn:get_core_api()

    local got_err
    core:get_projects(function(err, _)
      got_err = err
    end)

    assert.is_not_nil(got_err)
    assert.equals('http', got_err.type)
    assert.equals(401, got_err.status_code)
    assert.equals('Unauthorized', got_err.message)
  end)

  it('handles curl transport failure end-to-end', function()
    vim.system = function(_, _, cb)
      vim.schedule(function()
        cb({ code = 6, stdout = '', stderr = 'Could not resolve host: bad.example.com' })
      end)
      return {}
    end

    local conn = sdk.new('https://bad.example.com', sdk.auth.pat('test'))
    local core = conn:get_core_api()

    local got_err
    core:get_projects(function(err, _)
      got_err = err
    end)

    assert.is_not_nil(got_err)
    assert.equals('transport', got_err.type)
    assert.truthy(got_err.message:match('reach') or got_err.message:match('network'))
  end)

  it('executes WIQL query end-to-end', function()
    local wiql_response = vim.json.encode({
      workItems = {
        { id = 1, url = 'https://...' },
        { id = 2, url = 'https://...' },
      },
    })

    vim.system = function(_, _, cb)
      vim.schedule(function()
        cb({ code = 0, stdout = wiql_response .. '\n200', stderr = '' })
      end)
      return {}
    end

    local conn = sdk.new('https://dev.azure.com/testorg', sdk.auth.pat('test-pat'))
    local wit = conn:get_work_item_tracking_api()

    local result
    wit:query_by_wiql('SELECT [System.Id] FROM WorkItems', 'MyProject', function(err, refs)
      assert.is_nil(err)
      result = refs
    end)

    assert.equals(2, #result)
    assert.equals(1, result[1].id)
  end)

  it('fetches work items by ID end-to-end', function()
    local items_response = vim.json.encode({
      count = 2,
      value = {
        { id = 1, rev = 1, fields = { ['System.Title'] = 'Item 1' } },
        { id = 2, rev = 3, fields = { ['System.Title'] = 'Item 2' } },
      },
    })

    vim.system = function(_, _, cb)
      vim.schedule(function()
        cb({ code = 0, stdout = items_response .. '\n200', stderr = '' })
      end)
      return {}
    end

    local conn = sdk.new('https://dev.azure.com/testorg', sdk.auth.pat('test-pat'))
    local wit = conn:get_work_item_tracking_api()

    local result
    wit:get_work_items({ 1, 2 }, 'MyProject', function(err, items)
      assert.is_nil(err)
      result = items
    end)

    assert.equals(2, #result)
    assert.equals('Item 1', result[1].fields['System.Title'])
  end)

  it('verifies curl args include auth and method', function()
    local captured_args

    vim.system = function(args, _, cb)
      captured_args = args
      vim.schedule(function()
        cb({ code = 0, stdout = '{}\n200', stderr = '' })
      end)
      return {}
    end

    local conn = sdk.new('https://dev.azure.com/testorg', sdk.auth.pat('test-pat'))
    conn:get_core_api():get_projects(function() end)

    assert.equals('curl', captured_args[1])

    -- Verify method
    local has_get = false
    for i, arg in ipairs(captured_args) do
      if arg == '-X' and captured_args[i + 1] == 'GET' then
        has_get = true
      end
    end
    assert.is_true(has_get)

    -- Verify auth header is present (without exposing the value)
    local has_auth = false
    for _, arg in ipairs(captured_args) do
      if type(arg) == 'string' and arg:match('^Authorization:') then
        has_auth = true
      end
    end
    assert.is_true(has_auth)

    -- Verify URL contains api-version
    local url_arg = captured_args[#captured_args]
    assert.truthy(url_arg:match('api%-version=7%.0'))
    assert.truthy(url_arg:match('_apis/projects'))
  end)
end)
