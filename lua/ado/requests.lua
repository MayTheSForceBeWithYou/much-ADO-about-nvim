-- much-ADO-about-nvim requests module
-- Async request orchestration with stale response gating
-- Ensures one request at a time and ignores outdated responses

local M = {}

local state = require('ado.state')
local log = require('ado.log')

--- Get the SDK client (new ADO Lua SDK)
---@return table|nil client
---@return string|nil error_message
local function get_client()
  return require('ado.ado_client').get()
end

---@param err any
---@return string
local function err_msg(err)
  if type(err) == 'table' then
    return err.message or tostring(err)
  end
  return tostring(err)
end

---@param res table|nil
---@return table
local function data_value(res)
  return (res and res.data and res.data.value) or {}
end

--- Execute a request with stale gating
--- If a new request comes in, the old one's response will be ignored
---@param request_fn function Function that takes a callback
---@param on_success function Callback for successful, non-stale response
---@param on_error function|nil Callback for errors
function M.execute(request_fn, on_success, on_error)
  -- Prevent concurrent requests
  if state.is_loading() then
    log.debug('execute: skipped, request already in progress')
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
      log.debug('execute: stale response (seq %d), ignoring', seq)
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

--- Fetch and load projects into state (uses ADO Lua SDK via ado_client)
---@param callback function|nil Called after projects are loaded
function M.load_projects(callback)
  log.debug('load_projects: fetching via ADO Lua SDK')
  local ado_client, cerr = require('ado.ado_client').get()
  if not ado_client then
    vim.notify('ADO SDK unavailable: ' .. tostring(cerr), vim.log.levels.ERROR)
    return
  end
  M.execute(
    function(cb)
      ado_client.projects:list({}, {
        callback = function(res, err)
          if err then
            cb(err.message, nil)
            return
          end
          cb(nil, res.data and res.data.value or {})
        end,
      })
    end,
    function(projects)
      log.debug('load_projects: received %d projects', #projects)
      state.set('projects', projects)
      if callback then callback(projects) end
    end
  )
end

--- Fetch teams in the current project (optionally only "my teams") and set state.team_area_paths.
--- Each team is mapped to area path as projectName\teamName. Also updates cache.
---@param opts table|nil Optional: { mine = true } to fetch only teams the user is a member of
---@param callback function|nil Called with list of area path strings
function M.load_teams(opts, callback)
  local project = state.get('project')
  if not project then
    if callback then callback({}) end
    return
  end
  opts = opts or { mine = true }
  if type(opts) == 'function' then
    callback = opts
    opts = { mine = true }
  end
  local cache = require('ado.cache')
  local org_url = state.get('org_url')
  -- Return cached teams if we have them and caller didn't force refresh
  if not opts.refresh then
    local cached = cache.get_teams_cache(org_url, project)
    if cached and #cached > 0 then
      local paths = {}
      for _, t in ipairs(cached) do
        table.insert(paths, t.area_path or (t.projectName and t.name and (t.projectName .. '\\' .. t.name)))
      end
      state.set('team_area_paths', paths)
      log.debug('load_teams: using %d cached teams', #paths)
      if callback then callback(paths) end
      return
    end
  end
  log.debug('load_teams: fetching teams for project=%s mine=%s', project, opts.mine and 'true' or 'false')
  local client, cerr = get_client()
  if not client then
    log.debug('load_teams failed: %s', tostring(cerr))
    state.set('team_area_paths', {})
    if callback then callback({}) end
    return
  end
  local params = {}
  if opts.mine then
    params['$mine'] = 'true'
  end
  M.execute(
    function(cb)
      client.projects:list_teams(project, params, {
        callback = function(res, err)
          if err then
            cb(err_msg(err), nil)
            return
          end
          cb(nil, data_value(res))
        end,
      })
    end,
    function(teams)
      local paths = {}
      local for_cache = {}
      for _, t in ipairs(teams or {}) do
        local pname = t.projectName or project
        local area_path = pname .. '\\' .. (t.name or '')
        table.insert(paths, area_path)
        table.insert(for_cache, { id = t.id, name = t.name, projectName = pname, area_path = area_path })
      end
      state.set('team_area_paths', paths)
      cache.set_teams_cache(org_url, project, for_cache)
      log.debug('load_teams: got %d teams', #paths)
      if callback then callback(paths) end
    end,
    function(err)
      log.debug('load_teams failed: %s', tostring(err))
      state.set('team_area_paths', {})
      if callback then callback({}) end
    end
  )
end

--- Fallback state names when the API does not return valid states for the work item type
local STATE_FALLBACK = { 'To Do', 'In Progress', 'Done', 'Removed' }

--- Load valid state names for a work item type (for the State field picker)
---@param wit_type string Work item type display name (e.g. "Task", "Bug")
---@param callback function Called with (err, state_names); state_names is empty on error
function M.load_states_for_wit(wit_type, callback)
  local project = state.get('project')
  if not project or not wit_type or wit_type == '' then
    if callback then callback('Project and work item type required', STATE_FALLBACK) end
    return
  end
  local client, cerr = get_client()
  if not client then
    log.debug('load_states_for_wit: using fallback for type "%s" (err=%s)', wit_type, tostring(cerr))
    if callback then callback(nil, STATE_FALLBACK) end
    return
  end
  client.work_items:get_type_states(wit_type, { project = project }, {
    callback = function(res, err)
      local names = {}
      if not err then
        for _, s in ipairs(data_value(res)) do
          names[#names + 1] = type(s) == 'table' and s.name or s
        end
      end
      if err or #names == 0 then
        log.debug('load_states_for_wit: using fallback for type "%s" (err=%s)', wit_type, err and err_msg(err) or 'empty')
        if callback then callback(nil, STATE_FALLBACK) end
        return
      end
      if callback then callback(nil, names) end
    end,
  })
end

--- Update work item state via JSON Patch (Content-Type: application/json-patch+json)
---@param id number Work item ID
---@param new_state string New state value (e.g. "In Progress", "Done")
---@param callback function|nil Called on completion: callback(err) with err nil on success
function M.update_state(id, new_state, callback)
  local project = state.get('project')
  if not project then
    local err = 'No project selected'
    if callback then callback(err) else vim.notify(err, vim.log.levels.ERROR) end
    return
  end
  if not id or not new_state or new_state == '' then
    local err = 'Work item ID and state are required'
    if callback then callback(err) else vim.notify(err, vim.log.levels.ERROR) end
    return
  end

  local patch = {
    { op = 'add', path = '/fields/System.State', value = new_state },
  }
  log.debug('update_state: PATCH work item #%d state=%s', id, new_state)
  local client, cerr = get_client()
  if not client then
    if callback then callback(cerr) else vim.notify(cerr, vim.log.levels.ERROR) end
    return
  end
  M.execute(
    function(cb)
      client.work_items:update(id, patch, { project = project }, {
        callback = function(res, err)
          if err then
            cb(err_msg(err), nil)
            return
          end
          cb(nil, res and res.data or res)
        end,
      })
    end,
    function(updated)
      -- Update in-memory state so detail view shows new state without refetch
      local item = state.get('selected_work_item')
      if item and item.id == id and item.fields then
        item.fields['System.State'] = new_state
      end
      if callback then callback(nil) end
    end,
    function(err)
      if callback then callback(err or 'Update failed') else vim.notify('Failed to update state: ' .. tostring(err), vim.log.levels.ERROR) end
    end
  )
end

--- Sort work items in place using list_sort_field / list_sort_dir.
--- get_batch does not preserve WIQL order, so the list always re-sorts here.
---@param items table[]
---@return table[]
function M.sort_work_items(items)
  items = items or {}
  local field = state.get('list_sort_field') or 'id'
  local dir = state.get('list_sort_dir') or 'desc'
  table.sort(items, function(a, b)
    if field == 'state' then
      local sa = ((a.fields or {})['System.State'] or ''):lower()
      local sb = ((b.fields or {})['System.State'] or ''):lower()
      if sa ~= sb then
        if dir == 'asc' then
          return sa < sb
        end
        return sa > sb
      end
      return (a.id or 0) > (b.id or 0)
    end
    local ia, ib = a.id or 0, b.id or 0
    if dir == 'asc' then
      return ia < ib
    end
    return ia > ib
  end)
  return items
end

--- Fetch and load work items for the current project
---@param callback function|nil Called after work items are loaded
function M.load_work_items(callback)
  local project = state.get('project')
  if not project then
    vim.notify('No project selected', vim.log.levels.ERROR)
    return
  end

  local area_path = state.get('area_path')
  local where_clauses = { '[System.TeamProject] = @project' }
  if area_path then
    where_clauses[#where_clauses + 1] =
      string.format("[System.AreaPath] UNDER '%s'", area_path:gsub("'", "''"))
  end

  local state_filter = state.get('list_state_filter') or 'active'
  if state_filter == 'active' then
    where_clauses[#where_clauses + 1] = "[System.State] NOT IN ('Closed', 'Removed')"
  elseif state_filter ~= 'all' and state_filter ~= '' then
    where_clauses[#where_clauses + 1] =
      string.format("[System.State] = '%s'", tostring(state_filter):gsub("'", "''"))
  end

  local assignee_filter = state.get('list_assignee_filter') or 'me'
  if assignee_filter == 'me' then
    where_clauses[#where_clauses + 1] = '[System.AssignedTo] = @Me'
  elseif assignee_filter == 'unassigned' then
    where_clauses[#where_clauses + 1] = "[System.AssignedTo] = ''"
  elseif assignee_filter ~= 'all' and assignee_filter ~= '' then
    where_clauses[#where_clauses + 1] =
      string.format("[System.AssignedTo] = '%s'", tostring(assignee_filter):gsub("'", "''"))
  end

  local sort_field = state.get('list_sort_field') or 'id'
  local sort_dir = state.get('list_sort_dir') or 'desc'
  local order_col = sort_field == 'state' and '[System.State]' or '[System.Id]'
  local order_dir = sort_dir == 'asc' and 'ASC' or 'DESC'

  local wiql = string.format([[
    SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo]
    FROM WorkItems
    WHERE %s
    ORDER BY %s %s
  ]], table.concat(where_clauses, ' AND '), order_col, order_dir)

  log.debug('load_work_items: querying project=%s state=%s assignee=%s sort=%s %s',
    project, tostring(state_filter), tostring(assignee_filter), sort_field, order_dir)
  local client, cerr = get_client()
  if not client then
    vim.notify('ADO SDK unavailable: ' .. tostring(cerr), vim.log.levels.ERROR)
    return
  end
  M.execute(
    function(cb)
      client.work_items:run_wiql(wiql, { project = project, ['$top'] = 200 }, {
        callback = function(res, err)
          if err then
            cb(err_msg(err), nil)
            return
          end

          local refs = (res and res.data and res.data.workItems) or {}
          local ids = {}
          for _, ref in ipairs(refs) do
            table.insert(ids, ref.id)
          end

          if #ids == 0 then
            log.debug('load_work_items: WIQL returned 0 results')
            cb(nil, {})
            return
          end

          log.debug('load_work_items: WIQL returned %d refs, fetching details', #ids)

          -- Limit batch size
          -- TODO: Handle pagination for large result sets
          ids = vim.list_slice(ids, 1, 200)

          client.work_items:get_batch(ids, { project = project, ['$expand'] = 'all' }, {
            callback = function(bres, berr)
              if berr then
                cb(err_msg(berr), nil)
                return
              end
              cb(nil, data_value(bres))
            end,
          })
        end,
      })
    end,
    function(work_items)
      work_items = M.sort_work_items(work_items or {})
      log.debug('load_work_items: loaded %d work items', #work_items)
      state.set('work_items', work_items)
      -- Background: preload team members for assignee picker
      M.load_team_members()
      if callback then callback(work_items) end
    end
  )
end

--- Decode XML attribute entities
---@param s string
---@return string
local function decode_xml_attr(s)
  return s:gsub('&amp;', '&'):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"')
end

--- Parse an XML string into a tree of {tag, attrs, children}
--- Minimal parser sufficient for Azure DevOps xmlForm structures
---@param xml string
---@return table root node with children
local function parse_xml(xml)
  local root = { tag = 'root', attrs = {}, children = {} }
  local stack = { root }

  for raw in xml:gmatch('<([^>]+)>') do
    if raw:sub(1, 1) == '/' then
      -- Closing tag
      if #stack > 1 then table.remove(stack) end
    else
      local self_closing = raw:sub(-1) == '/'
      if self_closing then raw = raw:sub(1, -2) end

      local tag = raw:match('^(%w+)')
      local attrs = {}
      for k, v in raw:gmatch('(%w+)="([^"]*)"') do
        attrs[k] = decode_xml_attr(v)
      end

      local elem = { tag = tag, attrs = attrs, children = {} }
      table.insert(stack[#stack].children, elem)

      if not self_closing then
        table.insert(stack, elem)
      end
    end
  end

  return root
end

--- Find a direct child by tag name
---@param node table XML tree node
---@param tag string Tag name to find
---@return table|nil
local function find_child(node, tag)
  for _, child in ipairs(node.children) do
    if child.tag == tag then return child end
  end
  return nil
end

--- Recursively collect all Control elements from an XML subtree
---@param node table XML tree node
---@return ado.sdk.FormControl[]
local function collect_controls(node)
  local controls = {}
  for _, child in ipairs(node.children) do
    if child.tag == 'Control' and child.attrs.FieldName then
      -- Strip accelerator key markers from labels (e.g. "Assi&gned To" → "Assigned To")
      local label = (child.attrs.Label or ''):gsub('&', '')
      table.insert(controls, {
        id = child.attrs.FieldName,
        label = label,
        controlType = child.attrs.Type or 'FieldControl',
        visible = true,
        readOnly = child.attrs.ReadOnly == 'True',
      })
    else
      -- Recurse into Column, Group, etc.
      for _, ctrl in ipairs(collect_controls(child)) do
        table.insert(controls, ctrl)
      end
    end
  end
  return controls
end

--- Collect groups with labels from an XML subtree (one level of named groups)
---@param node table XML tree node
---@return ado.sdk.FormGroup[]
local function collect_groups(node)
  local groups = {}
  for _, child in ipairs(node.children) do
    if child.tag == 'Group' and child.attrs.Label and child.attrs.Label ~= '' then
      local ctrls = collect_controls(child)
      if #ctrls > 0 then
        table.insert(groups, {
          id = child.attrs.Label,
          label = child.attrs.Label,
          visible = true,
          controls = ctrls,
        })
      end
    elseif child.tag == 'Column' or child.tag == 'Group' then
      -- Recurse into unnamed groups and columns to find named groups deeper
      for _, g in ipairs(collect_groups(child)) do
        table.insert(groups, g)
      end
    end
  end
  return groups
end

--- Convert an xmlForm string into a FormLayout structure
---@param xml_form string The xmlForm XML string from the WIT API
---@return ado.sdk.FormLayout
local function xml_form_to_layout(xml_form)
  local tree = parse_xml(xml_form)
  local form = find_child(tree, 'FORM') or tree
  local layout_elem = find_child(form, 'Layout') or form

  local result = { pages = {}, systemControls = {} }

  for _, child in ipairs(layout_elem.children) do
    if child.tag == 'TabGroup' then
      -- Each Tab becomes a page
      for _, tab in ipairs(child.children) do
        if tab.tag == 'Tab' then
          local label = tab.attrs.Label or ''
          -- Classify tab type for filtering
          local page_type = 'custom'
          local lower = label:lower()
          if lower == 'history' then page_type = 'history'
          elseif lower == 'links' then page_type = 'links'
          elseif lower == 'attachments' then page_type = 'attachments'
          end

          local groups = collect_groups(tab)
          -- If no named groups, collect all controls as a single unnamed group
          if #groups == 0 then
            local ctrls = collect_controls(tab)
            if #ctrls > 0 then
              groups = { { id = '', label = '', visible = true, controls = ctrls } }
            end
          end

          table.insert(result.pages, {
            id = label,
            label = label,
            pageType = page_type,
            visible = true,
            sections = { { id = label, groups = groups } },
          })
        end
      end
    elseif child.tag == 'Group' then
      -- Top-level groups (before TabGroup) contain system controls
      for _, ctrl in ipairs(collect_controls(child)) do
        table.insert(result.systemControls, ctrl)
      end
    end
  end

  return result
end

-- Expose for testing
M._parse_xml = parse_xml
M._xml_form_to_layout = xml_form_to_layout

--- Fetch and cache the form layout for a work item type
--- Uses the WIT API's get_work_item_type endpoint which returns xmlForm,
--- a project-scoped XML layout that works for all process types (including locked).
--- Fails silently on error — the detail pane falls back to hardcoded rendering.
---@param wit_type string Work item type display name (e.g. "Bug")
---@param callback function|nil Called with the FormLayout when available
function M.ensure_layout(wit_type, callback)
  local layouts = state.get('layouts') or {}
  if layouts[wit_type] then
    log.debug('ensure_layout: cache hit for "%s"', wit_type)
    if callback then callback(layouts[wit_type]) end
    return
  end
  if state.is_loading() then
    log.debug('ensure_layout: skipped for "%s", request in progress', wit_type)
    return
  end

  log.debug('ensure_layout: fetching layout for "%s"', wit_type)
  local client, cerr = get_client()
  if not client then
    log.debug('ensure_layout: failed for "%s": %s', wit_type, tostring(cerr))
    return
  end
  local project = state.get('project')
  M.execute(
    function(cb)
      client.work_items:get_type(wit_type, { project = project }, {
        callback = function(res, err)
          if err then cb(err_msg(err), nil) return end
          local wit_def = res and res.data or {}
          if not wit_def.xmlForm or wit_def.xmlForm == '' then
            cb('No form layout available', nil)
            return
          end
          log.debug('ensure_layout: parsing xmlForm for "%s" (%d bytes)', wit_type, #wit_def.xmlForm)
          local ok, form_layout = pcall(xml_form_to_layout, wit_def.xmlForm)
          if not ok then
            cb('Failed to parse form layout: ' .. tostring(form_layout), nil)
            return
          end
          local n_pages = #(form_layout.pages or {})
          local n_sys = #(form_layout.systemControls or {})
          log.debug('ensure_layout: parsed layout for "%s" (%d pages, %d system controls)', wit_type, n_pages, n_sys)
          cb(nil, form_layout)
        end,
      })
    end,
    function(form_layout)
      log.debug('ensure_layout: cached layout for "%s"', wit_type)
      local ls = state.get('layouts') or {}
      ls[wit_type] = form_layout
      state.set('layouts', ls)
      if callback then callback(form_layout) end
    end,
    -- Silent error handler: layout is a background enhancement, not user-initiated
    function(err)
      log.debug('ensure_layout: failed for "%s": %s', wit_type, tostring(err))
    end
  )
end

--- Load team members for the current project's teams (background preload for assignee picker)
--- Fetches members of each cached team, deduplicates, and stores in state.team_members
---@param callback function|nil Called with team_members array when done
function M.load_team_members(callback)
  local project = state.get('project')
  local org_url = state.get('org_url')
  if not project or not org_url then
    if callback then callback({}) end
    return
  end

  -- Get team list from cache
  local cache = require('ado.cache')
  local cached_teams = cache.get_teams_cache(org_url, project) or {}
  if #cached_teams == 0 then
    log.debug('load_team_members: no cached teams, skipping')
    if callback then callback({}) end
    return
  end

  local client, cerr = get_client()
  if not client then
    log.debug('load_team_members: %s', tostring(cerr))
    if callback then callback({}) end
    return
  end
  local pending = #cached_teams
  local all_members = {}
  local seen = {}

  for _, team in ipairs(cached_teams) do
    local team_id = team.id or team.name
    if not team_id then
      pending = pending - 1
      if pending == 0 then
        state.set('team_members', all_members)
        log.debug('load_team_members: loaded %d unique members', #all_members)
        if callback then callback(all_members) end
      end
    else
      client.projects:list_team_members(project, team_id, {}, {
        callback = function(res, err)
          if not err then
            for _, m in ipairs(data_value(res)) do
              local ident = m.identity or m
              local member = {
                id = ident.id or m.id,
                displayName = ident.displayName or m.displayName,
                uniqueName = ident.uniqueName or m.uniqueName,
              }
              local key = member.uniqueName or member.displayName
              if key and not seen[key] then
                seen[key] = true
                table.insert(all_members, member)
              end
            end
          else
            log.debug('load_team_members: error for team %s: %s', team_id, err_msg(err))
          end
          pending = pending - 1
          if pending == 0 then
            state.set('team_members', all_members)
            log.debug('load_team_members: loaded %d unique members', #all_members)
            if callback then callback(all_members) end
          end
        end,
      })
    end
  end
end

--- Fetch work item update history lazily (cache on first load).
-- Uses ADO_Lua_SDK work_items:get_updates — no raw HTTP in the plugin.
-- The result is cached in state.history_cache[work_item_id] so subsequent
-- calls to the same item are instant.
---@param work_item_id number Work item ID
---@param callback fun(err: string|nil, updates: table[]|nil)
function M.load_history(work_item_id, callback)
  local project = state.get('project')
  if not project then
    if callback then callback('No project selected', nil) end
    return
  end

  -- Serve from cache when available
  local history_cache = state.get('history_cache') or {}
  if history_cache[work_item_id] then
    log.debug('load_history: cache hit for #%d', work_item_id)
    if callback then callback(nil, history_cache[work_item_id]) end
    return
  end

  local ado_client, cerr = get_client()
  if not ado_client then
    local msg = 'ADO SDK unavailable: ' .. tostring(cerr)
    log.debug('load_history: %s', msg)
    if callback then callback(msg, nil) end
    return
  end

  log.debug('load_history: fetching updates for #%d project=%s', work_item_id, project)
  ado_client.work_items:get_updates(work_item_id, { project = project }, {
    callback = function(res, err)
      if err then
        local msg = err.message or tostring(err)
        log.debug('load_history: error for #%d: %s', work_item_id, msg)
        if callback then callback(msg, nil) end
        return
      end
      local updates = (res and res.data and res.data.value) or {}
      log.debug('load_history: got %d updates for #%d', #updates, work_item_id)
      -- Cache by work item ID (persists across tab switches for this session)
      local hc = state.get('history_cache') or {}
      hc[work_item_id] = updates
      state.set('history_cache', hc)
      if callback then callback(nil, updates) end
    end,
  })
end

--- Search identities org-wide via vssps API (for assignee typeahead)
---@param query string Search prefix
---@param callback fun(err: string|nil, identities: ado.sdk.Identity[]|nil)
function M.search_identities(query, callback)
  if not query or query == '' then
    if callback then callback(nil, {}) end
    return
  end
  local client, cerr = get_client()
  if not client then
    if callback then callback(tostring(cerr), nil) end
    return
  end
  client.identity:search(query, {}, {
    callback = function(res, err)
      if err then
        log.debug('search_identities: error: %s', err_msg(err))
        if callback then callback(err_msg(err), nil) end
        return
      end
local identities = data_value(res)
        if #identities == 0 and res and res.data and type(res.data.identities) == 'table' then
          identities = res.data.identities
        end
        local mapped = {}
        for _, id in ipairs(identities) do
          local props = id.properties or {}
          local function prop(name)
            local p = props[name]
            if type(p) == 'table' then
              return p['$value'] or p.value
            end
            return p
          end
          mapped[#mapped + 1] = {
            id = id.id,
            displayName = id.providerDisplayName or id.displayName,
            email = prop('Mail') or prop('Account') or id.uniqueName or id.email or '',
          }
        end
        if callback then callback(nil, mapped) end
    end,
  })
end

--- Update a work item's assignee via JSON Patch
---@param id number Work item ID
---@param email string Assignee email/UPN (empty string to clear)
---@param callback function|nil Called with (err) — nil on success
function M.update_assignee(id, email, callback)
  local project = state.get('project')
  if not project then
    local err = 'No project selected'
    if callback then callback(err) else vim.notify(err, vim.log.levels.ERROR) end
    return
  end
  if not id then
    local err = 'Work item ID is required'
    if callback then callback(err) else vim.notify(err, vim.log.levels.ERROR) end
    return
  end

  local patch = {
    { op = 'add', path = '/fields/System.AssignedTo', value = email or '' },
  }
  log.debug('update_assignee: PATCH work item #%d assignee=%s', id, email or '(clear)')
  local client, cerr = get_client()
  if not client then
    if callback then callback(cerr) else vim.notify(cerr, vim.log.levels.ERROR) end
    return
  end
  M.execute(
    function(cb)
      client.work_items:update(id, patch, { project = project }, {
        callback = function(res, err)
          if err then
            cb(err_msg(err), nil)
            return
          end
          cb(nil, res and res.data or res)
        end,
      })
    end,
    function(updated)
      local item = state.get('selected_work_item')
      if item and item.id == id and item.fields then
        item.fields['System.AssignedTo'] = updated.fields and updated.fields['System.AssignedTo']
      end
      if callback then callback(nil) end
    end,
    function(err)
      if callback then callback(err or 'Update failed') else vim.notify('Failed to update assignee: ' .. tostring(err), vim.log.levels.ERROR) end
    end
  )
end

return M
