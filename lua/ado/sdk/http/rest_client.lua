-- Azure DevOps SDK REST client
-- HTTP transport via curl + vim.system()
-- Zero dependency on plugin state, config, or UI

local errors = require('ado.sdk.http.errors')

---@class ado.sdk.RestClient
---@field private _org_url string Organization URL (no trailing slash)
---@field private _auth_handler ado.sdk.AuthHandler Auth handler instance
---@field private _api_version string Default API version
---@field private _timeout number HTTP timeout in seconds
---@field private _max_response_size number Maximum response size in bytes
local RestClient = {}
RestClient.__index = RestClient

--- Create a new REST client
---@param org_url string Azure DevOps organization URL
---@param auth_handler ado.sdk.AuthHandler Authentication handler
---@param opts ado.sdk.ConnectionOptions|nil Connection options
---@return ado.sdk.RestClient
function RestClient.new(org_url, auth_handler, opts)
  assert(type(org_url) == 'string' and org_url ~= '', 'org_url must be a non-empty string')
  assert(auth_handler, 'auth_handler is required')

  opts = opts or {}
  local self = setmetatable({}, RestClient)

  -- Normalize: strip trailing slash
  if org_url:sub(-1) == '/' then
    org_url = org_url:sub(1, -2)
  end

  self._org_url = org_url
  self._auth_handler = auth_handler
  self._api_version = opts.api_version or '7.0'
  self._timeout = opts.timeout or 30
  self._max_response_size = opts.max_response_size or (10 * 1024 * 1024)

  return self
end

--- Build the full URL for an API endpoint
---@param endpoint string API path (e.g. "wit/workitems")
---@param project string|nil Project scope (inserted between org and _apis)
---@return string
function RestClient:build_url(endpoint, project)
  if project then
    return string.format('%s/%s/_apis/%s', self._org_url, project, endpoint)
  else
    return string.format('%s/_apis/%s', self._org_url, endpoint)
  end
end

--- Encode query parameters into a URL query string
--- Always injects api-version
---@param params table<string, string|number>|nil Additional key-value pairs
---@return string Query string starting with "?" or empty string if no params
function RestClient:encode_query(params)
  local all = {}
  all['api-version'] = self._api_version

  if params then
    for k, v in pairs(params) do
      all[k] = tostring(v)
    end
  end

  local parts = {}
  for k, v in pairs(all) do
    table.insert(parts, string.format('%s=%s', k, vim.uri_encode(v)))
  end

  if #parts > 0 then
    return '?' .. table.concat(parts, '&')
  end
  return ''
end

--- Execute an HTTP request
--- SECURITY: curl_args contains the Authorization header with the user's PAT.
--- Never log, print, or expose curl_args in error messages or debug output.
---@param method string HTTP method (GET, POST, PATCH, DELETE)
---@param url string Full URL (already built via build_url + encode_query)
---@param body table|nil JSON body (will be encoded)
---@param callback ado.sdk.Callback Callback(err, decoded_response)
function RestClient:request(method, url, body, callback)
  -- Log the request (URL is safe — no auth credentials in it)
  local log = require('ado.log')
  log.debug('HTTP %s %s', method, url)

  local headers = {
    ['Content-Type'] = 'application/json',
  }
  self._auth_handler:prepare_request(headers)

  local curl_args = {
    'curl',
    '-s',
    '-w', '\n%{http_code}',
    '--max-time', tostring(self._timeout),
    '-X', method,
  }

  for k, v in pairs(headers) do
    table.insert(curl_args, '-H')
    table.insert(curl_args, k .. ': ' .. v)
  end

  if body then
    table.insert(curl_args, '-d')
    table.insert(curl_args, vim.json.encode(body))
  end

  table.insert(curl_args, url)

  local max_size = self._max_response_size
  vim.system(curl_args, { text = true }, function(obj)
    vim.schedule(function()
      -- Handle curl execution failure
      if obj.code ~= 0 then
        log.debug('HTTP transport error: curl exit code %d', obj.code)
        callback(errors.transport(obj.code, obj.stderr, obj.stdout), nil)
        return
      end

      local stdout = obj.stdout or ''

      -- Check response size
      if #stdout > max_size then
        callback(errors.response_too_large(#stdout, max_size), nil)
        return
      end

      -- Split response body from HTTP status code
      local lines = vim.split(stdout, '\n')
      local http_code = tonumber(lines[#lines]) or 0
      table.remove(lines)
      local response_body = table.concat(lines, '\n')

      -- Handle HTTP errors
      if http_code >= 400 then
        log.debug('HTTP %d error for %s %s', http_code, method, url)
        callback(errors.http(http_code, response_body), nil)
        return
      end

      log.debug('HTTP %d OK for %s %s (%d bytes)', http_code, method, url, #response_body)

      -- Parse JSON response
      if response_body == '' then
        callback(nil, {})
        return
      end

      local ok, decoded = pcall(vim.json.decode, response_body)
      if not ok then
        log.debug('JSON parse error for %s %s', method, url)
        callback(errors.parse(response_body, decoded), nil)
        return
      end

      callback(nil, decoded)
    end)
  end)
end

--- Convenience: GET request
---@param endpoint string API endpoint path
---@param project string|nil Project scope
---@param query table<string,string|number>|nil Additional query params
---@param callback ado.sdk.Callback
function RestClient:get(endpoint, project, query, callback)
  local url = self:build_url(endpoint, project) .. self:encode_query(query)
  self:request('GET', url, nil, callback)
end

--- Convenience: POST request
---@param endpoint string API endpoint path
---@param project string|nil Project scope
---@param query table<string,string|number>|nil Additional query params
---@param body table JSON body
---@param callback ado.sdk.Callback
function RestClient:post(endpoint, project, query, body, callback)
  local url = self:build_url(endpoint, project) .. self:encode_query(query)
  self:request('POST', url, body, callback)
end

--- Get the default API version
---@return string
function RestClient:get_api_version()
  return self._api_version
end

return RestClient
