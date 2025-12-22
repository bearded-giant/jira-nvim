local M = {}

local api = vim.api

local state = require "jira.state"
local config = require "jira.config"
local render = require "jira.render"
local util = require "jira.util"
local sprint = require("jira.jira-api.sprint")
local ui = require("jira.ui")

M.setup = function(opts)
  config.setup(opts)
end

M.toggle_node = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]

  if node and node.children and #node.children > 0 then
    node.expanded = not node.expanded
    render.clear(state.buf)
    render.render_issue_tree(state.tree, state.current_view)
    
    local line_count = api.nvim_buf_line_count(state.buf)
    if cursor[1] > line_count then
      cursor[1] = line_count
    end
    api.nvim_win_set_cursor(state.win, cursor)
  end
end

M.load_view = function(project_key, view_name)
  state.project_key = project_key
  state.current_view = view_name

  ui.start_loading("Loading " .. view_name .. " for " .. project_key .. "...")

  local fetch_fn
  if view_name == "Active Sprint" then
    fetch_fn = function(pk, cb) sprint.get_active_sprint_issues(pk, cb) end
  elseif view_name == "Backlog" then
    fetch_fn = function(pk, cb) sprint.get_backlog_issues(pk, cb) end
  elseif view_name == "JQL" then
    fetch_fn = function(pk, cb) sprint.get_issues_by_jql(pk, state.custom_jql, cb) end
  end

  fetch_fn(project_key, function(issues, err)
    if err then
      vim.schedule(function()
        ui.stop_loading()
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      ui.stop_loading()

      -- Setup UI if not already created
      if not state.win or not api.nvim_win_is_valid(state.win) then
        ui.create_window()
        ui.setup_static_highlights()
      end

      if not issues or #issues == 0 then
        state.tree = {}
        render.clear(state.buf)
        render.render_issue_tree(state.tree, state.current_view)
        vim.notify("No issues found in " .. view_name .. ".", vim.log.levels.WARN)
      else
        state.tree = util.build_issue_tree(issues)
        render.clear(state.buf)
        render.render_issue_tree(state.tree, state.current_view)
        vim.notify("Loaded " .. view_name .. " for " .. project_key, vim.log.levels.INFO)
      end

      -- Keymaps
      local opts = { noremap = true, silent = true, buffer = state.buf }
      vim.keymap.set("n", "o", function() require("jira").toggle_node() end, opts)
      vim.keymap.set("n", "<CR>", function() require("jira").toggle_node() end, opts)
      vim.keymap.set("n", "<Tab>", function() require("jira").toggle_node() end, opts)

      -- Tab switching
      vim.keymap.set("n", "S", function() require("jira").load_view(state.project_key, "Active Sprint") end, opts)
      vim.keymap.set("n", "B", function() require("jira").load_view(state.project_key, "Backlog") end, opts)
      vim.keymap.set("n", "J", function() require("jira").prompt_jql() end, opts)
    end)
  end)
end

M.prompt_jql = function()
  vim.ui.input({ prompt = "JQL: ", default = state.custom_jql or "" }, function(input)
    if not input or input == "" then return end
    state.custom_jql = input
    M.load_view(state.project_key, "JQL")
  end)
end

M.open = function(project_key)
  -- If already open, just focus
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_set_current_win(state.win)
    return
  end

  -- Validate Config
  local jc = config.options.jira
  if not jc.base or jc.base == "" or not jc.email or jc.email == "" or not jc.token or jc.token == "" then
    vim.notify("Jira configuration is missing. Please run setup() with base, email, and token.", vim.log.levels.ERROR)
    return
  end

  if not project_key then
    project_key = vim.fn.input("Jira Project Key: ")
  end

  if not project_key or project_key == "" then
     vim.notify("Project key is required", vim.log.levels.ERROR)
     return
  end

  M.load_view(project_key, "Active Sprint")
end

return M