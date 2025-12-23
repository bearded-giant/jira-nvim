local state = {
  buf = nil,
  win = nil,
  dim_win = nil,
  ns = vim.api.nvim_create_namespace("Jira"),
  status_hls = {},
  tree = {},
  line_map = {},
  project_key = nil,
  current_view = nil,
  custom_jql = nil,
  cache = {},
  my_issues_projects = {},
}

return state
