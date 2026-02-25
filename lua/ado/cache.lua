-- much-ADO-about-nvim cache module
-- Persists last selected project/area path and optional teams list per (org, project).
-- Uses stdpath('data')/ado/state.json so it survives restarts.

local M = {}

local log = require('ado.log')

---@type table|nil Cached in-memory state
local memory = nil

--- Build cache key for org + project
---@param org_url string
---@param project string
---@return string
local function key(org_url, project)
  return (org_url or '') .. '|' .. (project or '')
end

--- Path to state file
---@return string
function M.path()
  local data_dir = vim.fn.stdpath('data')
  local ado_dir = data_dir .. '/ado'
  if vim.fn.isdirectory(ado_dir) == 0 then
    vim.fn.mkdir(ado_dir, 'p')
  end
  return ado_dir .. '/state.json'
end

--- Load state from disk (or return in-memory cache)
---@return table { last_area_paths = table<string,string>, teams_cache = table<string, table[]> }
function M.load()
  if memory then
    return memory
  end
  local path = M.path()
  local ok, contents = pcall(vim.fn.readfile, path)
  if not ok or not contents or #contents == 0 then
    memory = { last_area_paths = {}, teams_cache = {} }
    return memory
  end
  local body = table.concat(contents, '\n')
  local decoded = vim.json.decode(body)
  if type(decoded) ~= 'table' then
    memory = { last_area_paths = {}, teams_cache = {} }
    return memory
  end
  memory = {
    last_area_paths = type(decoded.last_area_paths) == 'table' and decoded.last_area_paths or {},
    teams_cache = type(decoded.teams_cache) == 'table' and decoded.teams_cache or {},
  }
  return memory
end

--- Persist state to disk
function M.save()
  local data = memory or { last_area_paths = {}, teams_cache = {} }
  local path = M.path()
  local body = vim.json.encode({
    last_area_paths = data.last_area_paths,
    teams_cache = data.teams_cache,
  })
  local ok, err = pcall(vim.fn.writefile, vim.split(body, '\n'), path)
  if not ok then
    log.debug('cache.save failed: %s', tostring(err))
  end
end

--- Get last selected area path for (org, project)
---@param org_url string
---@param project string
---@return string|nil
function M.get_last_area_path(org_url, project)
  local data = M.load()
  return data.last_area_paths[key(org_url, project)]
end

--- Set last selected area path for (org, project) and persist
---@param org_url string
---@param project string
---@param area_path string
function M.set_last_area_path(org_url, project, area_path)
  local data = M.load()
  data.last_area_paths[key(org_url, project)] = area_path
  M.save()
end

--- Get cached teams (array of { id, name, projectName, area_path }) for (org, project)
---@param org_url string
---@param project string
---@return table[]|nil
function M.get_teams_cache(org_url, project)
  local data = M.load()
  return data.teams_cache[key(org_url, project)]
end

--- Set teams cache for (org, project) and persist
---@param org_url string
---@param project string
---@param teams table[] Array of team objects with area_path
function M.set_teams_cache(org_url, project, teams)
  local data = M.load()
  data.teams_cache[key(org_url, project)] = teams
  M.save()
end

--- Clear in-memory cache (e.g. for tests)
function M.clear()
  memory = nil
end

return M
