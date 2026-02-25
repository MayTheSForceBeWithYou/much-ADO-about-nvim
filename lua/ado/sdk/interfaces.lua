-- Azure DevOps SDK type definitions
-- LuaCATS annotations for API data models
-- No runtime code; exists for language server type checking

---@class ado.sdk.ConnectionOptions
---@field api_version string? API version string (default "7.0")
---@field timeout number? HTTP timeout in seconds (default 30)
---@field max_response_size number? Maximum response body size in bytes (default 10MB)

---@class ado.sdk.AuthHandler
---@field prepare_request fun(self: ado.sdk.AuthHandler, headers: table<string,string>): table<string,string>
---@field get_type fun(self: ado.sdk.AuthHandler): string

---@class ado.sdk.ApiError
---@field message string Human-readable error message
---@field status_code number|nil HTTP status code (nil for transport errors)
---@field type string Error category: "transport"|"http"|"parse"|"validation"
---@field raw string|nil Raw error body or stderr

---@class ado.sdk.TeamProjectReference
---@field id string Project GUID
---@field name string Project name
---@field description string|nil Project description
---@field url string API URL for this project
---@field state string Project state (e.g. "wellFormed")
---@field revision number Project revision number
---@field visibility string "private"|"public"
---@field lastUpdateTime string ISO8601 timestamp

---@class ado.sdk.WebApiTeam
---@field id string Team GUID
---@field name string Team name
---@field projectId string Project GUID
---@field projectName string Project name
---@field url string API URL for this team
---@field description string|nil Team description

---@class ado.sdk.WorkItemReference
---@field id number Work item ID
---@field url string API URL for this work item

---@class ado.sdk.WorkItem
---@field id number Work item ID
---@field rev number Work item revision
---@field url string API URL
---@field fields table<string, any> Field name to value map

---@class ado.sdk.WorkItemQueryResult
---@field queryType string "flat"|"oneHop"|"tree"
---@field queryResultType string
---@field asOf string ISO8601 timestamp
---@field columns table[] Column definitions
---@field workItems ado.sdk.WorkItemReference[] Work item references

---@class ado.sdk.FormControl
---@field id string Field reference name (e.g. "System.Title")
---@field label string Display label
---@field controlType string "FieldControl"|"HtmlFieldControl"|"DateTimeControl"|etc
---@field visible boolean
---@field readOnly boolean

---@class ado.sdk.FormGroup
---@field id string
---@field label string
---@field visible boolean
---@field controls ado.sdk.FormControl[]

---@class ado.sdk.FormSection
---@field id string
---@field groups ado.sdk.FormGroup[]

---@class ado.sdk.FormPage
---@field id string
---@field label string
---@field pageType string "custom"|"history"|"links"|"attachments"
---@field visible boolean
---@field sections ado.sdk.FormSection[]

---@class ado.sdk.FormLayout
---@field pages ado.sdk.FormPage[]
---@field systemControls ado.sdk.FormControl[]

---@alias ado.sdk.Callback fun(err: ado.sdk.ApiError|nil, result: any)

return {}
