-- much-ADO-about-nvim requests module
-- Async request orchestration with stale response gating
-- Ensures one request at a time and ignores outdated responses

local M = {}

local state = require('ado.state')
local api = require('ado.api')

--- Execute a request with stale gating
--- If a new request comes in, the old one's response will be ignored
---@param request_fn function Function that takes a callback
---@param on_success function Callback for successful, non-stale response
---@param on_error function|nil Callback for errors
function M.execute(request_fn, on_success, on_error)
  -- Prevent concurrent requests
  if state.is_loading() then
    vim.notify('A request is already in progress', vim.log.levels.WARN)
    return
  end

  -- Get sequence ID for this request
  local seq = state.next_request_seq()
  state.set_loading(true)

  request_fn(function(err, result)
    -- Always clear loading state
    state.set_loading(false)

    -- Check if this response is stale
    if not state.is_current_seq(seq) then
      -- Response is stale, ignore it
      return
    end

    if err then
      if on_error then
        on_error(err)
      else
        vim.notify('Request failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
      return
    end

    on_success(result)
  end)
end

--- Fetch and load projects into state
---@param callback function|nil Called after projects are loaded
function M.load_projects(callback)
  M.execute(
    function(cb) api.get_projects(cb) end,
    function(projects)
      state.set('projects', projects)
      if callback then callback(projects) end
    end
  )
end

--- Fetch and load work items for the current project
---@param callback function|nil Called after work items are loaded
function M.load_work_items(callback)
  local project = state.get('project')
  if not project then
    vim.notify('No project selected', vim.log.levels.ERROR)
    return
  end

  -- TODO: Make WIQL query configurable
  local wiql = [[
    SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType]
    FROM WorkItems
    WHERE [System.TeamProject] = @project
    ORDER BY [System.Id] ASC
  ]]

  M.execute(
    function(cb)
      api.query_work_items(project, wiql, function(err, refs)
        if err then
          cb(err, nil)
          return
        end

        -- Extract IDs and fetch full details
        local ids = {}
        for _, ref in ipairs(refs) do
          table.insert(ids, ref.id)
        end

        if #ids == 0 then
          cb(nil, {})
          return
        end

        -- Limit batch size
        -- TODO: Handle pagination for large result sets
        ids = vim.list_slice(ids, 1, 200)

        api.get_work_items(project, ids, cb)
      end)
    end,
    function(work_items)
      state.set('work_items', work_items)
      if callback then callback(work_items) end
    end
  )
end

return M
