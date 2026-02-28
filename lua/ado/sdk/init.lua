-- Azure DevOps SDK for Neovim
-- Connection factory (WebApi equivalent from azure-devops-node-api)
-- Zero dependency on plugin state, config, or UI

local RestClient = require('ado.sdk.http.rest_client')
local auth = require('ado.sdk.auth')

---@class ado.sdk.Connection
---@field private _rest ado.sdk.RestClient
---@field private _core_api ado.sdk.CoreApi|nil Lazily created
---@field private _wit_api ado.sdk.WorkItemTrackingApi|nil Lazily created
---@field private _identity_api ado.sdk.IdentityApi|nil Lazily created
---@field private _pipelines_api ado.sdk.PipelinesApi|nil Lazily created
local Connection = {}
Connection.__index = Connection

--- Create a new Azure DevOps connection
---@param org_url string Organization URL (e.g. "https://dev.azure.com/myorg")
---@param auth_handler ado.sdk.AuthHandler Authentication handler
---@param opts ado.sdk.ConnectionOptions|nil Connection options
---@return ado.sdk.Connection
function Connection.new(org_url, auth_handler, opts)
  local self = setmetatable({}, Connection)
  self._rest = RestClient.new(org_url, auth_handler, opts)
  self._core_api = nil
  self._wit_api = nil
  self._identity_api = nil
  self._pipelines_api = nil
  return self
end

--- Get the Core API client (projects, teams)
--- Lazily creates the client on first call
---@return ado.sdk.CoreApi
function Connection:get_core_api()
  if not self._core_api then
    self._core_api = require('ado.sdk.api.core_api').new(self._rest)
  end
  return self._core_api
end

--- Get the Work Item Tracking API client (WIQL, work items)
--- Lazily creates the client on first call
---@return ado.sdk.WorkItemTrackingApi
function Connection:get_work_item_tracking_api()
  if not self._wit_api then
    self._wit_api = require('ado.sdk.api.work_item_tracking_api').new(self._rest)
  end
  return self._wit_api
end

--- Get the Identity API client (identity search via vssps)
--- Lazily creates the client on first call
---@return ado.sdk.IdentityApi
function Connection:get_identity_api()
  if not self._identity_api then
    self._identity_api = require('ado.sdk.api.identity_api').new(self._rest)
  end
  return self._identity_api
end

--- Get the Pipelines API client (pipelines, runs)
--- Lazily creates the client on first call
---@return ado.sdk.PipelinesApi
function Connection:get_pipelines_api()
  if not self._pipelines_api then
    self._pipelines_api = require('ado.sdk.api.pipelines_api').new(self._rest)
  end
  return self._pipelines_api
end

--- Get the underlying REST client (for advanced/custom requests)
---@return ado.sdk.RestClient
function Connection:get_rest_client()
  return self._rest
end

-- Module-level exports
local M = {}

--- Create a new connection to Azure DevOps
---@param org_url string Organization URL
---@param auth_handler ado.sdk.AuthHandler Auth handler (use require('ado.sdk').auth.pat(token))
---@param opts ado.sdk.ConnectionOptions|nil Options
---@return ado.sdk.Connection
function M.new(org_url, auth_handler, opts)
  return Connection.new(org_url, auth_handler, opts)
end

--- Auth handler constructors
M.auth = auth

return M
