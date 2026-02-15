-- Azure DevOps SDK Work Item Tracking API client
-- WIQL queries, work item CRUD

local ClientBase = require('ado.sdk.api.client_base')
local errors = require('ado.sdk.http.errors')

---@class ado.sdk.WorkItemTrackingApi : ado.sdk.ClientBase
local WorkItemTrackingApi = setmetatable({}, { __index = ClientBase })
WorkItemTrackingApi.__index = WorkItemTrackingApi

-- Resource Area ID for WIT API (from azure-devops-node-api)
WorkItemTrackingApi.RESOURCE_AREA_ID = '5264459e-e5e0-4571-b150-2ef732ce8b62'

--- Create a new WorkItemTrackingApi client
---@param rest_client ado.sdk.RestClient
---@return ado.sdk.WorkItemTrackingApi
function WorkItemTrackingApi.new(rest_client)
  local instance = ClientBase.new(rest_client, WorkItemTrackingApi.RESOURCE_AREA_ID)
  return setmetatable(instance, WorkItemTrackingApi)
end

--- Execute a WIQL query to find work items
---@param wiql string WIQL query string
---@param project string Project name or ID
---@param callback fun(err: ado.sdk.ApiError|nil, refs: ado.sdk.WorkItemReference[]|nil)
function WorkItemTrackingApi:query_by_wiql(wiql, project, callback)
  if not wiql or wiql == '' then
    callback(errors.validation('wiql query is required'), nil)
    return
  end
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end

  self.rest:post('wit/wiql', project, nil, { query = wiql }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response.workItems or {})
  end)
end

--- Get work items by IDs (batch)
---@param ids number[] Array of work item IDs
---@param project string Project name or ID
---@param callback fun(err: ado.sdk.ApiError|nil, work_items: ado.sdk.WorkItem[]|nil)
function WorkItemTrackingApi:get_work_items(ids, project, callback)
  if not ids or #ids == 0 then
    callback(nil, {})
    return
  end
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end

  self.rest:get('wit/workitems', project, {
    ids = table.concat(ids, ','),
  }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, self:extract_collection(response))
  end)
end

--- Get a single work item by ID
---@param id number Work item ID
---@param project string Project name or ID
---@param callback fun(err: ado.sdk.ApiError|nil, work_item: ado.sdk.WorkItem|nil)
function WorkItemTrackingApi:get_work_item(id, project, callback)
  if not id then
    callback(errors.validation('work item id is required'), nil)
    return
  end
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end

  self.rest:get('wit/workitems/' .. tostring(id), project, nil, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response)
  end)
end

return WorkItemTrackingApi
