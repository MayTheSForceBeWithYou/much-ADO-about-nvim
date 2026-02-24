-- Tests for ado.sdk.api.work_item_tracking_api module

describe('WorkItemTrackingApi', function()
  local WIT

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
    package.loaded['ado.sdk.api.work_item_tracking_api'] = nil
    package.loaded['ado.sdk.api.client_base'] = nil
    package.loaded['ado.sdk.http.errors'] = nil
    WIT = require('ado.sdk.api.work_item_tracking_api')
  end)

  describe('query_by_wiql', function()
    it('returns work item refs', function()
      local refs = { { id = 1, url = '...' }, { id = 2, url = '...' } }
      local api = WIT.new(mock_rest({ workItems = refs }))

      local result
      api:query_by_wiql('SELECT ...', 'MyProject', function(_, r) result = r end)
      assert.same(refs, result)
    end)

    it('returns empty when no workItems', function()
      local api = WIT.new(mock_rest({}))

      local result
      api:query_by_wiql('SELECT ...', 'MyProject', function(_, r) result = r end)
      assert.same({}, result)
    end)

    it('validates wiql is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:query_by_wiql('', 'P', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates project is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:query_by_wiql('SELECT', '', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('propagates errors', function()
      local api_err = { message = 'fail', type = 'http', status_code = 400 }
      local api = WIT.new(mock_rest(nil, api_err))

      local got_err
      api:query_by_wiql('SELECT', 'P', function(e, _) got_err = e end)
      assert.equals('fail', got_err.message)
    end)
  end)

  describe('get_work_items', function()
    it('returns work items from value field', function()
      local items = { { id = 1, fields = {} }, { id = 2, fields = {} } }
      local api = WIT.new(mock_rest({ value = items }))

      local result
      api:get_work_items({ 1, 2 }, 'P', function(_, r) result = r end)
      assert.same(items, result)
    end)

    it('returns empty list for empty ids', function()
      local api = WIT.new(mock_rest({}))

      local result
      api:get_work_items({}, 'P', function(_, r) result = r end)
      assert.same({}, result)
    end)

    it('validates project is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:get_work_items({ 1 }, '', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)
  end)

  describe('get_work_item', function()
    it('returns single work item', function()
      local item = { id = 42, fields = { ['System.Title'] = 'Test' } }
      local api = WIT.new(mock_rest(item))

      local result
      api:get_work_item(42, 'P', function(_, r) result = r end)
      assert.equals(42, result.id)
    end)

    it('validates id is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:get_work_item(nil, 'P', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates project is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:get_work_item(1, '', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)
  end)

  describe('get_work_item_type', function()
    it('returns work item type definition', function()
      local wit_type = {
        name = 'Bug',
        referenceName = 'Microsoft.VSTS.WorkItemTypes.Bug',
      }
      local api = WIT.new(mock_rest(wit_type))

      local result
      api:get_work_item_type('Bug', 'P', function(_, r) result = r end)
      assert.equals('Bug', result.name)
      assert.equals('Microsoft.VSTS.WorkItemTypes.Bug', result.referenceName)
    end)

    it('validates type_name is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:get_work_item_type('', 'P', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates project is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:get_work_item_type('Bug', '', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('propagates errors', function()
      local api_err = { message = 'not found', type = 'http', status_code = 404 }
      local api = WIT.new(mock_rest(nil, api_err))

      local got_err
      api:get_work_item_type('Bug', 'P', function(e, _) got_err = e end)
      assert.equals('not found', got_err.message)
    end)
  end)

  describe('get_work_item_type_layout', function()
    it('returns form layout', function()
      local form_layout = {
        pages = { { id = 'page1', label = 'Details', sections = {} } },
        systemControls = { { id = 'System.Title', label = 'Title' } },
      }
      local api = WIT.new(mock_rest(form_layout))

      local result
      api:get_work_item_type_layout('proc-id', 'Microsoft.VSTS.WorkItemTypes.Bug', function(_, r) result = r end)
      assert.equals(1, #result.pages)
      assert.equals('Details', result.pages[1].label)
      assert.equals(1, #result.systemControls)
    end)

    it('uses org-scoped endpoint (nil project)', function()
      local captured_project
      local rest = {
        get = function(_, endpoint, project, query, callback)
          captured_project = project
          callback(nil, { pages = {}, systemControls = {} })
        end,
        post = function() end,
      }
      local api = WIT.new(rest)
      api:get_work_item_type_layout('proc-id', 'ref-name', function() end)
      assert.is_nil(captured_project)
    end)

    it('overrides api-version to 7.1-preview.1', function()
      local captured_query
      local rest = {
        get = function(_, endpoint, project, query, callback)
          captured_query = query
          callback(nil, { pages = {}, systemControls = {} })
        end,
        post = function() end,
      }
      local api = WIT.new(rest)
      api:get_work_item_type_layout('proc-id', 'ref-name', function() end)
      assert.equals('7.1-preview.1', captured_query['api-version'])
    end)

    it('validates process_id is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:get_work_item_type_layout('', 'ref', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates wit_ref_name is required', function()
      local api = WIT.new(mock_rest({}))

      local got_err
      api:get_work_item_type_layout('proc', '', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('propagates errors', function()
      local api_err = { message = 'fail', type = 'http', status_code = 500 }
      local api = WIT.new(mock_rest(nil, api_err))

      local got_err
      api:get_work_item_type_layout('proc', 'ref', function(e, _) got_err = e end)
      assert.equals('fail', got_err.message)
    end)
  end)
end)
