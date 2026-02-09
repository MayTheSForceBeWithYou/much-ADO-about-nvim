-- much-ADO-about-nvim API module
-- Azure DevOps REST client using curl via vim.system()
-- This module MUST NOT manipulate buffers or windows

local M = {}

local state = require('ado.state')

--- Build authorization header value
---@return string
local function build_auth_header()
  local pat = vim.env.ADO_PAT
  local encoded = vim.base64.encode(':' .. pat)
  return 'Basic ' .. encoded
end

--- Build the full URL for an API endpoint
---@param endpoint string API endpoint path
---@param project string|nil Project name (inserted after org URL if provided)
---@return string
local function build_url(endpoint, project)
  local org_url = state.get('org_url')
  if project then
    return string.format('%s/%s/_apis/%s', org_url, project, endpoint)
  else
    return string.format('%s/_apis/%s', org_url, endpoint)
  end
end

-- Maximum response size (10MB) to prevent memory issues
local MAX_RESPONSE_SIZE = 10 * 1024 * 1024

--- Parse curl error into user-friendly message
---@param code number Exit code
---@param stderr string Standard error output
---@param stdout string Standard output (may contain error body)
---@return string error_message
local function parse_curl_error(code, stderr, stdout)
  stderr = stderr or ''
  stdout = stdout or ''

  -- Common curl error patterns
  if stderr:match('Could not resolve host') then
    return 'Cannot reach Azure DevOps. Check your network connection and ADO_ORG_URL.'
  elseif stderr:match('Connection refused') then
    return 'Connection refused. Verify ADO_ORG_URL is correct.'
  elseif stderr:match('Operation timed out') or stderr:match('Connection timed out') then
    return 'Request timed out. Try again later.'
  elseif stderr:match('SSL') or stderr:match('certificate') then
    return 'SSL/TLS error. Check your network configuration.'
  end

  -- Try to parse error from response body (for HTTP errors)
  local ok, body = pcall(vim.json.decode, stdout)
  if ok and type(body) == 'table' and body.message then
    return 'API error: ' .. body.message
  end

  -- Generic fallback
  if stderr ~= '' then
    return 'Request failed: ' .. stderr
  end

  return 'Request failed with code ' .. code
end

--- Execute an API request
--- SECURITY WARNING: curl_args contains the Authorization header with the user's PAT.
--- Never log, print, or expose curl_args in error messages or debug output.
--- The PAT grants access to the user's Azure DevOps resources.
---@param method string HTTP method (GET, POST, etc.)
---@param endpoint string API endpoint
---@param opts table|nil Options: { project = string, body = table, query = table }
---@param callback function Callback(err, response)
function M.request(method, endpoint, opts, callback)
  opts = opts or {}

  local url = build_url(endpoint, opts.project)

  -- Append query parameters
  if opts.query then
    local params = {}
    for k, v in pairs(opts.query) do
      table.insert(params, string.format('%s=%s', k, vim.uri_encode(tostring(v))))
    end
    if #params > 0 then
      url = url .. '?' .. table.concat(params, '&')
    end
  end

  local curl_args = {
    'curl',
    '-s',                                    -- Silent mode
    '-w', '\n%{http_code}',                  -- Append HTTP status code
    '--max-time', '30',                      -- 30 second timeout
    '-X', method,
    '-H', 'Authorization: ' .. build_auth_header(),
    '-H', 'Content-Type: application/json',
  }

  if opts.body then
    table.insert(curl_args, '-d')
    table.insert(curl_args, vim.json.encode(opts.body))
  end

  table.insert(curl_args, url)

  vim.system(curl_args, { text = true }, function(obj)
    vim.schedule(function()
      -- Handle curl execution failure
      if obj.code ~= 0 then
        callback(parse_curl_error(obj.code, obj.stderr, obj.stdout), nil)
        return
      end

      local stdout = obj.stdout or ''

      -- Check response size
      if #stdout > MAX_RESPONSE_SIZE then
        callback('Response too large (>' .. (MAX_RESPONSE_SIZE / 1024 / 1024) .. 'MB)', nil)
        return
      end

      -- Split response body from HTTP status code
      local lines = vim.split(stdout, '\n')
      local http_code = tonumber(lines[#lines]) or 0
      table.remove(lines)  -- Remove the status code line
      local body = table.concat(lines, '\n')

      -- Handle HTTP errors
      if http_code >= 400 then
        local ok, decoded = pcall(vim.json.decode, body)
        local message
        if ok and type(decoded) == 'table' and decoded.message then
          message = decoded.message
        elseif http_code == 401 then
          message = 'Authentication failed. Check your ADO_PAT.'
        elseif http_code == 403 then
          message = 'Access denied. Check PAT permissions.'
        elseif http_code == 404 then
          message = 'Resource not found. Check project name and endpoint.'
        else
          message = 'HTTP error ' .. http_code
        end
        callback(message, nil)
        return
      end

      -- Parse JSON response
      if body == '' then
        callback(nil, {})
        return
      end

      local ok, decoded = pcall(vim.json.decode, body)
      if not ok then
        callback('Failed to parse JSON response: ' .. tostring(decoded), nil)
        return
      end

      callback(nil, decoded)
    end)
  end)
end

--- Fetch list of projects
---@param callback function Callback(err, projects)
function M.get_projects(callback)
  -- TODO: Implement actual API call
  -- Endpoint: projects?api-version=7.0
  M.request('GET', 'projects', { query = { ['api-version'] = '7.0' } }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response.value or {})
  end)
end

--- Execute a WIQL query to get work item IDs
---@param project string Project name
---@param wiql string WIQL query string
---@param callback function Callback(err, work_item_refs)
function M.query_work_items(project, wiql, callback)
  -- TODO: Implement actual API call
  -- Endpoint: wit/wiql?api-version=7.0
  M.request('POST', 'wit/wiql', {
    project = project,
    query = { ['api-version'] = '7.0' },
    body = { query = wiql },
  }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response.workItems or {})
  end)
end

--- Fetch work item details by IDs (batch)
---@param project string Project name
---@param ids number[] Work item IDs
---@param callback function Callback(err, work_items)
function M.get_work_items(project, ids, callback)
  -- TODO: Implement actual API call
  -- Endpoint: wit/workitems?ids=1,2,3&api-version=7.0
  if #ids == 0 then
    callback(nil, {})
    return
  end

  M.request('GET', 'wit/workitems', {
    project = project,
    query = {
      ids = table.concat(ids, ','),
      ['api-version'] = '7.0',
    },
  }, function(err, response)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, response.value or {})
  end)
end

return M
