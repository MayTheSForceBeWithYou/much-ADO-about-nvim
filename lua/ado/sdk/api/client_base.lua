-- Azure DevOps SDK base class for all domain API clients
-- Provides shared infrastructure inherited by CoreApi, WorkItemTrackingApi, etc.

---@class ado.sdk.ClientBase
---@field protected rest ado.sdk.RestClient The HTTP client
---@field protected resource_area_id string|nil Resource area GUID
local ClientBase = {}
ClientBase.__index = ClientBase

--- Create a new client base (called by subclasses, not directly)
---@param rest_client ado.sdk.RestClient
---@param resource_area_id string|nil
---@return ado.sdk.ClientBase
function ClientBase.new(rest_client, resource_area_id)
  local self = setmetatable({}, ClientBase)
  self.rest = rest_client
  self.resource_area_id = resource_area_id
  return self
end

--- Extract a value list from a standard Azure DevOps collection response
--- Most list endpoints return { count = N, value = [...] }
---@param response table Decoded API response
---@param key string|nil Field name to extract (default "value")
---@return any[] items The extracted list
function ClientBase:extract_collection(response, key)
  key = key or 'value'
  return response[key] or {}
end

return ClientBase
