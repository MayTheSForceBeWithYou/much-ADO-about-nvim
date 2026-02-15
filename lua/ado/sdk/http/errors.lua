-- Azure DevOps SDK error normalization
-- Factory functions producing ado.sdk.ApiError instances

local M = {}

--- Create a transport error (curl failure, DNS, timeout, SSL)
---@param code number curl exit code
---@param stderr string curl stderr output
---@param stdout string curl stdout (may contain partial response)
---@return ado.sdk.ApiError
function M.transport(code, stderr, stdout)
  stderr = stderr or ''
  stdout = stdout or ''

  local message
  if stderr:match('Could not resolve host') then
    message = 'Cannot reach Azure DevOps. Check your network connection and ADO_ORG_URL.'
  elseif stderr:match('Connection refused') then
    message = 'Connection refused. Verify ADO_ORG_URL is correct.'
  elseif stderr:match('Operation timed out') or stderr:match('Connection timed out') then
    message = 'Request timed out. Try again later.'
  elseif stderr:match('SSL') or stderr:match('certificate') then
    message = 'SSL/TLS error. Check your network configuration.'
  else
    -- Try to extract message from response body
    local ok, body = pcall(vim.json.decode, stdout)
    if ok and type(body) == 'table' and body.message then
      message = 'API error: ' .. body.message
    elseif stderr ~= '' then
      message = 'Request failed: ' .. stderr
    else
      message = 'Request failed with code ' .. code
    end
  end

  return {
    message = message,
    status_code = nil,
    type = 'transport',
    raw = stderr ~= '' and stderr or nil,
  }
end

--- Create an HTTP error (4xx/5xx status)
---@param status_code number HTTP status code
---@param body string Raw response body
---@return ado.sdk.ApiError
function M.http(status_code, body)
  local message

  -- Try to extract API error message from response body
  local ok, decoded = pcall(vim.json.decode, body)
  if ok and type(decoded) == 'table' and decoded.message then
    message = decoded.message
  elseif status_code == 401 then
    message = 'Authentication failed. Check your ADO_PAT.'
  elseif status_code == 403 then
    message = 'Access denied. Check PAT permissions.'
  elseif status_code == 404 then
    message = 'Resource not found. Check project name and endpoint.'
  else
    message = 'HTTP error ' .. status_code
  end

  return {
    message = message,
    status_code = status_code,
    type = 'http',
    raw = body ~= '' and body or nil,
  }
end

--- Create a parse error (invalid JSON response)
---@param body string The body that failed to parse
---@param parse_error string The pcall error string
---@return ado.sdk.ApiError
function M.parse(body, parse_error)
  return {
    message = 'Failed to parse JSON response: ' .. tostring(parse_error),
    status_code = nil,
    type = 'parse',
    raw = body,
  }
end

--- Create a validation error (bad parameters before request)
---@param message string Validation failure description
---@return ado.sdk.ApiError
function M.validation(message)
  return {
    message = message,
    status_code = nil,
    type = 'validation',
    raw = nil,
  }
end

--- Create an error for oversized responses
---@param size number Actual response size in bytes
---@param max number Maximum allowed size in bytes
---@return ado.sdk.ApiError
function M.response_too_large(size, max)
  return {
    message = string.format('Response too large (%dMB > %dMB limit)',
      math.floor(size / 1024 / 1024),
      math.floor(max / 1024 / 1024)),
    status_code = nil,
    type = 'transport',
    raw = nil,
  }
end

return M
