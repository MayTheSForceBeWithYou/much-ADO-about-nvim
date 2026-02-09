-- much-ADO-about-nvim state module
-- Centralized in-memory state management
-- All shared data flows through this module

local M = {}

---@class AdoState
---@field org_url string|nil Azure DevOps organization URL
---@field project string|nil Current project name
---@field projects table|nil List of available projects
---@field work_items table|nil List of work items
---@field selected_work_item table|nil Currently selected work item
---@field request_seq number Current request sequence ID for stale gating
---@field loading boolean Whether a request is in progress

---@type AdoState
local state = {}

--- Reset state to initial values
function M.reset()
  state = {
    org_url = nil,
    project = nil,
    projects = nil,
    work_items = nil,
    selected_work_item = nil,
    request_seq = 0,
    loading = false,
  }
end

--- Get a state value
---@param key string
---@return any
function M.get(key)
  return state[key]
end

--- Set a state value
---@param key string
---@param value any
function M.set(key, value)
  state[key] = value
end

--- Increment and return the next request sequence ID
---@return number
function M.next_request_seq()
  state.request_seq = state.request_seq + 1
  return state.request_seq
end

--- Check if a request sequence ID is current (not stale)
---@param seq number
---@return boolean
function M.is_current_seq(seq)
  return seq == state.request_seq
end

--- Set loading state
---@param loading boolean
function M.set_loading(loading)
  state.loading = loading
end

--- Check if currently loading
---@return boolean
function M.is_loading()
  return state.loading
end

--- Subscribe to state changes (placeholder for reactive updates)
---@param key string State key to watch
---@param callback function Callback when state changes
---@return function unsubscribe
function M.subscribe(key, callback)
  -- TODO: Implement reactive state subscriptions
  -- For now, return a no-op unsubscribe function
  return function() end
end

-- Initialize state
M.reset()

return M
