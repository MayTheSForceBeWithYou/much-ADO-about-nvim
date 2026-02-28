-- Azure DevOps SDK Pipelines API client
-- List pipelines, list runs, get run details

local ClientBase = require('ado.sdk.api.client_base')
local errors = require('ado.sdk.http.errors')

---@class ado.sdk.PipelinesApi : ado.sdk.ClientBase
local PipelinesApi = setmetatable({}, { __index = ClientBase })
PipelinesApi.__index = PipelinesApi

--- API version for the Pipelines REST API
PipelinesApi.API_VERSION = '7.1-preview.1'

--- Create a new PipelinesApi client
---@param rest_client ado.sdk.RestClient
---@return ado.sdk.PipelinesApi
function PipelinesApi.new(rest_client)
  local instance = ClientBase.new(rest_client, nil)
  return setmetatable(instance, PipelinesApi)
end

--- List pipelines in a project
---@param project string Project name or ID
---@param callback fun(err: ado.sdk.ApiError|nil, pipelines: table[]|nil)
function PipelinesApi:list_pipelines(project, callback)
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end

  self.rest:get('pipelines', project, { ['api-version'] = self.API_VERSION }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, self:extract_collection(response))
  end)
end

--- List runs for a pipeline
---@param project string Project name or ID
---@param pipeline_id number Pipeline ID
---@param opts table|nil Optional: { top = number }
---@param callback fun(err: ado.sdk.ApiError|nil, runs: table[]|nil)
function PipelinesApi:list_runs(project, pipeline_id, opts, callback)
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end
  if not pipeline_id then
    callback(errors.validation('pipeline_id is required'), nil)
    return
  end

  opts = opts or {}
  local query = { ['api-version'] = self.API_VERSION }
  if opts.top then
    query['$top'] = tostring(opts.top)
  end

  local endpoint = 'pipelines/' .. tostring(pipeline_id) .. '/runs'
  self.rest:get(endpoint, project, query, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, self:extract_collection(response))
  end)
end

--- Get details for a specific pipeline run
---@param project string Project name or ID
---@param pipeline_id number Pipeline ID
---@param run_id number Run ID
---@param callback fun(err: ado.sdk.ApiError|nil, run: table|nil)
function PipelinesApi:get_run(project, pipeline_id, run_id, callback)
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end
  if not pipeline_id then
    callback(errors.validation('pipeline_id is required'), nil)
    return
  end
  if not run_id then
    callback(errors.validation('run_id is required'), nil)
    return
  end

  local endpoint = 'pipelines/' .. tostring(pipeline_id) .. '/runs/' .. tostring(run_id)
  self.rest:get(endpoint, project, { ['api-version'] = self.API_VERSION }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response)
  end)
end

return PipelinesApi
