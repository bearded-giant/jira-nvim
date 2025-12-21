local M = {}

M.defaults = {
  jira = {
    base = os.getenv("JIRA_BASE"),
    email = os.getenv("JIRA_EMAIL"),
    token = os.getenv("JIRA_TOKEN"),
    story_point_field = "customfield_10023",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
