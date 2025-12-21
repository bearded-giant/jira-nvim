local M = {}

---@class JiraConfig
---@field jira JiraConfigOptions

---@class JiraConfigOptions
---@field base string URL of your Jira instance (e.g. https://your-domain.atlassian.net)
---@field email string Your Jira email
---@field token string Your Jira API token
---@field story_point_field? string Field ID for story points (default: customfield_10023)

---@type JiraConfig
M.defaults = {
  jira = {
    base = "",
    email = "",
    token = "",
    story_point_field = "customfield_10023",
  },
}

---@type JiraConfig
M.options = vim.deepcopy(M.defaults)

---@param opts JiraConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
