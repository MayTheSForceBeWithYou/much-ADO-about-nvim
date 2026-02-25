-- Azure DevOps SDK Core API client
-- Projects and organization-level resources

local ClientBase = require('ado.sdk.api.client_base')
local errors = require('ado.sdk.http.errors')

---@class ado.sdk.CoreApi : ado.sdk.ClientBase
local CoreApi = setmetatable({}, { __index = ClientBase })
CoreApi.__index = CoreApi

-- Resource Area ID for Core API (from azure-devops-node-api)
CoreApi.RESOURCE_AREA_ID = '79134c72-4a58-4b42-976c-04e7115f32bf'

--- Create a new CoreApi client
---@param rest_client ado.sdk.RestClient
---@return ado.sdk.CoreApi
function CoreApi.new(rest_client)
  local instance = ClientBase.new(rest_client, CoreApi.RESOURCE_AREA_ID)
  return setmetatable(instance, CoreApi)
end

--- Get all projects in the organization
---@param callback fun(err: ado.sdk.ApiError|nil, projects: ado.sdk.TeamProjectReference[]|nil)
function CoreApi:get_projects(callback)
  self.rest:get('projects', nil, nil, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, self:extract_collection(response))
  end)
end

--- Get a single project by name or ID
---@param project_id string Project name or GUID
---@param callback fun(err: ado.sdk.ApiError|nil, project: ado.sdk.TeamProjectReference|nil)
function CoreApi:get_project(project_id, callback)
  if not project_id or project_id == '' then
    callback(errors.validation('project_id is required'), nil)
    return
  end
  self.rest:get('projects/' .. project_id, nil, { includeCapabilities = 'true' }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response)
  end)
end

--- Get teams in a project (optionally only teams the current user is a member of)
---@param project_id string Project name or GUID
---@param opts table|nil Optional: { mine = true } to return only teams the user is a member of
---@param callback fun(err: ado.sdk.ApiError|nil, teams: ado.sdk.WebApiTeam[]|nil)
function CoreApi:get_teams(project_id, opts, callback)
  if not project_id or project_id == '' then
    callback(errors.validation('project_id is required'), nil)
    return
  end
  if type(opts) == 'function' then
    callback = opts
    opts = nil
  end
  opts = opts or {}
  local query = {}
  if opts.mine then
    query['$mine'] = 'true'
  end
  self.rest:get('projects/' .. project_id .. '/teams', nil, query, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, self:extract_collection(response))
  end)
end

return CoreApi
