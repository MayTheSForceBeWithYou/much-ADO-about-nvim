-- Tests for ado.sdk.api.pipelines_api module

describe('PipelinesApi', function()
  local PipelinesApi

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
    package.loaded['ado.sdk.api.pipelines_api'] = nil
    package.loaded['ado.sdk.api.client_base'] = nil
    package.loaded['ado.sdk.http.errors'] = nil
    PipelinesApi = require('ado.sdk.api.pipelines_api')
  end)

  describe('list_pipelines', function()
    it('returns pipelines from value field', function()
      local pipelines = {
        { id = 1, name = 'CI Pipeline', folder = '\\' },
        { id = 2, name = 'CD Pipeline', folder = '\\Deploy' },
      }
      local api = PipelinesApi.new(mock_rest({ value = pipelines }))

      local result
      api:list_pipelines('MyProject', function(_, r) result = r end)
      assert.same(pipelines, result)
    end)

    it('returns empty list when no pipelines', function()
      local api = PipelinesApi.new(mock_rest({ value = {} }))

      local result
      api:list_pipelines('MyProject', function(_, r) result = r end)
      assert.same({}, result)
    end)

    it('validates project is required', function()
      local api = PipelinesApi.new(mock_rest({}))

      local got_err
      api:list_pipelines('', function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates project is required (nil)', function()
      local api = PipelinesApi.new(mock_rest({}))

      local got_err
      api:list_pipelines(nil, function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('propagates HTTP errors', function()
      local api_err = { message = 'Access denied. Check PAT permissions.', type = 'http', status_code = 403 }
      local api = PipelinesApi.new(mock_rest(nil, api_err))

      local got_err
      api:list_pipelines('MyProject', function(e, _) got_err = e end)
      assert.equals('Access denied. Check PAT permissions.', got_err.message)
    end)

    it('uses api-version 7.1-preview.1', function()
      local captured_query
      local rest = {
        get = function(_, endpoint, project, query, callback)
          captured_query = query
          callback(nil, { value = {} })
        end,
      }
      local api = PipelinesApi.new(rest)
      api:list_pipelines('P', function() end)
      assert.equals('7.1-preview.1', captured_query['api-version'])
    end)
  end)

  describe('list_runs', function()
    it('returns runs from value field', function()
      local runs = {
        { id = 101, state = 'completed', result = 'succeeded' },
        { id = 102, state = 'completed', result = 'failed' },
      }
      local api = PipelinesApi.new(mock_rest({ value = runs }))

      local result
      api:list_runs('MyProject', 1, nil, function(_, r) result = r end)
      assert.same(runs, result)
    end)

    it('returns empty list when no runs', function()
      local api = PipelinesApi.new(mock_rest({ value = {} }))

      local result
      api:list_runs('MyProject', 1, nil, function(_, r) result = r end)
      assert.same({}, result)
    end)

    it('validates project is required', function()
      local api = PipelinesApi.new(mock_rest({}))

      local got_err
      api:list_runs('', 1, nil, function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates pipeline_id is required', function()
      local api = PipelinesApi.new(mock_rest({}))

      local got_err
      api:list_runs('MyProject', nil, nil, function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('passes top option in query', function()
      local captured_query
      local rest = {
        get = function(_, endpoint, project, query, callback)
          captured_query = query
          callback(nil, { value = {} })
        end,
      }
      local api = PipelinesApi.new(rest)
      api:list_runs('P', 1, { top = 25 }, function() end)
      assert.equals('25', captured_query['$top'])
    end)

    it('propagates HTTP errors', function()
      local api_err = { message = 'not found', type = 'http', status_code = 404 }
      local api = PipelinesApi.new(mock_rest(nil, api_err))

      local got_err
      api:list_runs('MyProject', 1, nil, function(e, _) got_err = e end)
      assert.equals('not found', got_err.message)
    end)
  end)

  describe('get_run', function()
    it('returns run details', function()
      local run = {
        id = 101,
        state = 'completed',
        result = 'succeeded',
        createdDate = '2024-01-15T10:30:00Z',
        finishedDate = '2024-01-15T10:45:00Z',
      }
      local api = PipelinesApi.new(mock_rest(run))

      local result
      api:get_run('MyProject', 1, 101, function(_, r) result = r end)
      assert.equals(101, result.id)
      assert.equals('completed', result.state)
      assert.equals('succeeded', result.result)
    end)

    it('validates project is required', function()
      local api = PipelinesApi.new(mock_rest({}))

      local got_err
      api:get_run('', 1, 101, function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates pipeline_id is required', function()
      local api = PipelinesApi.new(mock_rest({}))

      local got_err
      api:get_run('MyProject', nil, 101, function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('validates run_id is required', function()
      local api = PipelinesApi.new(mock_rest({}))

      local got_err
      api:get_run('MyProject', 1, nil, function(e, _) got_err = e end)
      assert.equals('validation', got_err.type)
    end)

    it('propagates HTTP errors', function()
      local api_err = { message = 'HTTP error 500', type = 'http', status_code = 500 }
      local api = PipelinesApi.new(mock_rest(nil, api_err))

      local got_err
      api:get_run('MyProject', 1, 101, function(e, _) got_err = e end)
      assert.equals('HTTP error 500', got_err.message)
    end)

    it('uses project-scoped endpoint', function()
      local captured_project
      local rest = {
        get = function(_, endpoint, project, query, callback)
          captured_project = project
          callback(nil, { id = 1 })
        end,
      }
      local api = PipelinesApi.new(rest)
      api:get_run('TestProject', 1, 101, function() end)
      assert.equals('TestProject', captured_project)
    end)
  end)
end)

describe('pipeline_run_detail helpers', function()
  local detail

  before_each(function()
    package.loaded['ado.ui.pipeline_run_detail'] = nil
    package.loaded['ado.config'] = nil
    package.loaded['ado.log'] = nil
    package.loaded['ado.state'] = nil

    -- Stub heavy dependencies so module loads in headless mode
    package.loaded['ado.config'] = {
      get = function()
        return { ui = { border = 'rounded' }, keymaps = { close = 'q' } }
      end,
    }
    package.loaded['ado.log'] = {
      debug = function() end,
    }
    package.loaded['ado.state'] = {
      get = function() return nil end,
    }

    detail = require('ado.ui.pipeline_run_detail')
  end)

  describe('_compute_status', function()
    it('returns result when state is completed', function()
      assert.equals('succeeded', detail._compute_status({ state = 'completed', result = 'succeeded' }))
      assert.equals('failed', detail._compute_status({ state = 'completed', result = 'failed' }))
      assert.equals('canceled', detail._compute_status({ state = 'completed', result = 'canceled' }))
    end)

    it('returns completed when state is completed with no result', function()
      assert.equals('completed', detail._compute_status({ state = 'completed', result = '' }))
    end)

    it('returns in progress for inProgress state', function()
      assert.equals('in progress', detail._compute_status({ state = 'inProgress' }))
    end)

    it('returns canceling for canceling state', function()
      assert.equals('canceling', detail._compute_status({ state = 'canceling' }))
    end)

    it('returns unknown for empty state', function()
      assert.equals('unknown', detail._compute_status({ state = '' }))
    end)
  end)

  describe('_build_lines', function()
    it('includes pipeline name and run id', function()
      local pipeline = { id = 5, name = 'My CI' }
      local run = { id = 42, state = 'completed', result = 'succeeded' }
      local lines = detail._build_lines(pipeline, run)
      local text = table.concat(lines, '\n')
      assert.truthy(text:find('My CI'))
      assert.truthy(text:find('42'))
    end)

    it('shows branch from resources.repositories.self.refName', function()
      local pipeline = { id = 1, name = 'P' }
      local run = {
        id = 10,
        state = 'completed',
        result = 'succeeded',
        resources = {
          repositories = {
            self = { refName = 'refs/heads/main', version = 'abc123' },
          },
        },
      }
      local lines = detail._build_lines(pipeline, run)
      local text = table.concat(lines, '\n')
      assert.truthy(text:find('main'))
      assert.truthy(text:find('abc123'))
    end)

    it('shows web URL from run _links', function()
      local pipeline = { id = 1, name = 'P' }
      local run = {
        id = 10,
        state = 'completed',
        result = 'succeeded',
        _links = { web = { href = 'https://dev.azure.com/org/proj/_build/results?buildId=10' } },
      }
      local lines = detail._build_lines(pipeline, run)
      local text = table.concat(lines, '\n')
      assert.truthy(text:find('https://'))
    end)

    it('shows state and result fields', function()
      local pipeline = { id = 1, name = 'P' }
      local run = { id = 1, state = 'completed', result = 'failed' }
      local lines = detail._build_lines(pipeline, run)
      local text = table.concat(lines, '\n')
      assert.truthy(text:find('completed'))
      assert.truthy(text:find('failed'))
    end)
  end)
end)

describe('pipeline_runs_list helpers', function()
  local runs_list

  before_each(function()
    package.loaded['ado.ui.pipeline_runs_list'] = nil
    package.loaded['ado.config'] = nil
    package.loaded['ado.log'] = nil
    package.loaded['ado.state'] = nil

    package.loaded['ado.config'] = {
      get = function()
        return { ui = { border = 'rounded' }, keymaps = { close = 'q', select = '<CR>', next_item = 'j', prev_item = 'k', refresh = 'R' } }
      end,
    }
    package.loaded['ado.log'] = { debug = function() end }
    package.loaded['ado.state'] = { get = function() return nil end, is_loading = function() return false end }

    runs_list = require('ado.ui.pipeline_runs_list')
  end)

  describe('_format_run_status', function()
    it('returns succeeded for completed/succeeded', function()
      assert.equals('succeeded', runs_list._format_run_status({ state = 'completed', result = 'succeeded' }))
    end)

    it('returns failed for completed/failed', function()
      assert.equals('failed', runs_list._format_run_status({ state = 'completed', result = 'failed' }))
    end)

    it('returns canceled for completed/canceled', function()
      assert.equals('canceled', runs_list._format_run_status({ state = 'completed', result = 'canceled' }))
    end)

    it('returns in progress for inProgress', function()
      assert.equals('in progress', runs_list._format_run_status({ state = 'inProgress' }))
    end)

    it('returns unknown for empty state', function()
      assert.equals('unknown', runs_list._format_run_status({ state = '' }))
    end)
  end)

  describe('_format_run', function()
    it('includes run id and status', function()
      local run = { id = 99, state = 'completed', result = 'succeeded' }
      local line = runs_list._format_run(run)
      assert.truthy(line:find('99'))
      assert.truthy(line:find('succeeded'))
    end)

    it('includes branch when present', function()
      local run = {
        id = 5,
        state = 'inProgress',
        resources = {
          repositories = {
            self = { refName = 'refs/heads/feature/my-branch' },
          },
        },
      }
      local line = runs_list._format_run(run)
      assert.truthy(line:find('feature/my%-branch'))
    end)

    it('includes date when present', function()
      local run = { id = 1, state = 'completed', result = 'succeeded', createdDate = '2024-06-01T12:00:00Z' }
      local line = runs_list._format_run(run)
      assert.truthy(line:find('2024%-06%-01'))
    end)
  end)
end)
