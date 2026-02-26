-- Azure DevOps SDK Identity API client
-- Identity search via vssps.dev.azure.com
-- Uses the same PAT auth as the regular org URL

local ClientBase = require('ado.sdk.api.client_base')
local errors = require('ado.sdk.http.errors')

---@class ado.sdk.IdentityApi : ado.sdk.ClientBase
local IdentityApi = setmetatable({}, { __index = ClientBase })
IdentityApi.__index = IdentityApi

--- Create a new IdentityApi client
---@param rest_client ado.sdk.RestClient
---@return ado.sdk.IdentityApi
function IdentityApi.new(rest_client)
  local instance = ClientBase.new(rest_client)
  return setmetatable(instance, IdentityApi)
end

--- Build the vssps base URL from the regular org URL
--- Handles both dev.azure.com and visualstudio.com URL patterns
---@return string
function IdentityApi:_vssps_url()
  local url = self.rest._org_url
  if url:match('dev%.azure%.com') then
    return url:gsub('dev%.azure%.com', 'vssps.dev.azure.com')
  elseif url:match('%.visualstudio%.com') then
    return url:gsub('%.visualstudio%.com', '.vssps.visualstudio.com')
  end
  return url
end

--- Search identities by display name prefix
---@param query string Search query (name prefix)
---@param callback fun(err: ado.sdk.ApiError|nil, identities: ado.sdk.Identity[]|nil)
function IdentityApi:search(query, callback)
  if not query or query == '' then
    callback(errors.validation('query is required'), nil)
    return
  end

  local base = self:_vssps_url()
  local url = base .. '/_apis/identities'
    .. self.rest:encode_query({
      searchFilter = 'General',
      filterValue = query,
      queryMembership = 'None',
    })

  self.rest:request('GET', url, nil, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    -- Normalize response to { displayName, email } list
    local raw = self:extract_collection(response)
    local identities = {}
    for _, item in ipairs(raw) do
      local email = nil
      if item.properties and item.properties.Mail and item.properties.Mail['$value'] then
        email = item.properties.Mail['$value']
      elseif item.properties and item.properties.Account and item.properties.Account['$value'] then
        email = item.properties.Account['$value']
      end
      local display_name = item.providerDisplayName or item.displayName or ''
      if display_name ~= '' then
        table.insert(identities, {
          displayName = display_name,
          email = email,
          id = item.id,
        })
      end
    end
    callback(nil, identities)
  end)
end

return IdentityApi
