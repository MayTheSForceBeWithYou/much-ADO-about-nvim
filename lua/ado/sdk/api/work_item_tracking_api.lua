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

--- Get a work item type definition by name
---@param type_name string Work item type display name (e.g. "Bug")
---@param project string Project name or ID
---@param callback fun(err: ado.sdk.ApiError|nil, wit_type: table|nil)
function WorkItemTrackingApi:get_work_item_type(type_name, project, callback)
  if not type_name or type_name == '' then
    callback(errors.validation('type_name is required'), nil)
    return
  end
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end

  self.rest:get('wit/workitemtypes/' .. type_name, project, nil, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response)
  end)
end

--- Get valid state names for a work item type (e.g. "To Do", "Doing", "Done")
---@param type_name string Work item type display name (e.g. "Task", "Bug")
---@param project string Project name or ID
---@param callback fun(err: ado.sdk.ApiError|nil, states: string[]|nil)
function WorkItemTrackingApi:get_work_item_type_states(type_name, project, callback)
  if not type_name or type_name == '' then
    callback(errors.validation('type_name is required'), nil)
    return
  end
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end

  local endpoint = 'wit/workitemtypes/' .. type_name .. '/states'
  self.rest:get(endpoint, project, nil, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    local items = self:extract_collection(response)
    local names = {}
    for _, item in ipairs(items) do
      if type(item) == 'table' and item.name then
        table.insert(names, item.name)
      end
    end
    callback(nil, names)
  end)
end

--- Get the form layout for a work item type in a process
---@param process_id string Process template GUID
---@param wit_ref_name string Work item type reference name (e.g. "Microsoft.VSTS.WorkItemTypes.Bug")
---@param callback fun(err: ado.sdk.ApiError|nil, layout: ado.sdk.FormLayout|nil)
function WorkItemTrackingApi:get_work_item_type_layout(process_id, wit_ref_name, callback)
  if not process_id or process_id == '' then
    callback(errors.validation('process_id is required'), nil)
    return
  end
  if not wit_ref_name or wit_ref_name == '' then
    callback(errors.validation('wit_ref_name is required'), nil)
    return
  end

  local endpoint = 'work/processes/' .. process_id .. '/workItemTypes/' .. wit_ref_name .. '/layout'
  self.rest:get(endpoint, nil, { ['api-version'] = '7.1-preview.1' }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response)
  end)
end

--- Update a work item field (e.g. System.State) via JSON Patch
--- Uses Content-Type: application/json-patch+json per ADO API requirement
---@param id number Work item ID
---@param project string Project name or ID
---@param patch table[] JSON Patch operations, e.g. { { op = "add", path = "/fields/System.State", value = "In Progress" } }
---@param callback fun(err: ado.sdk.ApiError|nil, work_item: ado.sdk.WorkItem|nil)
function WorkItemTrackingApi:update_work_item(id, project, patch, callback)
  if not id then
    callback(errors.validation('work item id is required'), nil)
    return
  end
  if not project or project == '' then
    callback(errors.validation('project is required'), nil)
    return
  end
  if not patch or type(patch) ~= 'table' or #patch == 0 then
    callback(errors.validation('patch operations are required'), nil)
    return
  end

  local endpoint = 'wit/workitems/' .. tostring(id)
  self.rest:patch(endpoint, project, nil, patch, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response)
  end)
end

return WorkItemTrackingApi
