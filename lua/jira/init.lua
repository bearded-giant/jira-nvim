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

local function get_cache_key(project_key, view_name)
  if view_name == "My Issues" then
    local sorted = vim.tbl_map(function(p) return p end, state.my_issues_projects)
    table.sort(sorted)
    return "global:MyIssues:" .. table.concat(sorted, ",")
  end
  local key = project_key .. ":" .. view_name
  if view_name == "JQL" then
    key = key .. ":" .. (state.custom_jql or "")
  end
  return key
end

M.setup_keymaps = function()
  local opts = { noremap = true, silent = true, buffer = state.buf }
  vim.keymap.set("n", "o", function() require("jira").toggle_node() end, opts)
  vim.keymap.set("n", "<CR>", function() require("jira").toggle_node() end, opts)
  vim.keymap.set("n", "<Tab>", function() require("jira").toggle_node() end, opts)

  -- Tab switching
  vim.keymap.set("n", "S", function() require("jira").load_view(state.project_key, "Active Sprint") end, opts)
  vim.keymap.set("n", "B", function() require("jira").load_view(state.project_key, "Backlog") end, opts)
  vim.keymap.set("n", "M", function() require("jira").prompt_my_issues_projects() end, opts)
  vim.keymap.set("n", "J", function() require("jira").prompt_jql() end, opts)
  vim.keymap.set("n", "H", function() require("jira").load_view(state.project_key, "Help") end, opts)
  vim.keymap.set("n", "K", function() require("jira").show_issue_details() end, opts)
  vim.keymap.set("n", "m", function() require("jira").read_task() end, opts)
  vim.keymap.set("n", "gx", function() require("jira").open_in_browser() end, opts)

  -- Issue actions
  vim.keymap.set("n", "s", function() require("jira").change_status() end, opts)
  vim.keymap.set("n", "c", function() require("jira").create_story() end, opts)
  vim.keymap.set("n", "d", function() require("jira").close_issue() end, opts)

  -- Actions
  vim.keymap.set("n", "r", function()
    local cache_key = get_cache_key(state.project_key, state.current_view)
    state.cache[cache_key] = nil
    require("jira").load_view(state.project_key, state.current_view)
  end, opts)

  vim.keymap.set("n", "q", function()
    if state.win and api.nvim_win_is_valid(state.win) then
       api.nvim_win_close(state.win, true)
    end
  end, opts)
end

M.load_view = function(project_key, view_name)
  state.project_key = project_key
  state.current_view = view_name

  if view_name == "Help" then
    vim.schedule(function()
      if not state.win or not api.nvim_win_is_valid(state.win) then
        ui.create_window()
        ui.setup_static_highlights()
      end
      state.tree = {}
      state.line_map = {}
      render.clear(state.buf)
      render.render_help(view_name)
      M.setup_keymaps()
    end)
    return
  end

  local cache_key = get_cache_key(project_key, view_name)
  local cached_issues = state.cache[cache_key]

  local function process_issues(issues)
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
        if not cached_issues then
          vim.notify("Loaded " .. view_name .. " for " .. project_key, vim.log.levels.INFO)
        end
      end

      M.setup_keymaps()
    end)
  end

  if cached_issues then
    process_issues(cached_issues)
    return
  end

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

    state.cache[cache_key] = issues
    process_issues(issues)
  end)
end

M.prompt_jql = function()
  vim.ui.input({ prompt = "JQL: ", default = state.custom_jql or "" }, function(input)
    if not input or input == "" then return end
    state.custom_jql = input
    M.load_view(state.project_key, "JQL")
  end)
end

M.show_issue_details = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node then return end

  ui.show_issue_details_popup(node)
end

M.read_task = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then return end

  ui.start_loading("Fetching full details for " .. node.key .. "...")
  local jira_api = require("jira.jira-api.api")
  jira_api.get_issue(node.key, function(issue, err)
    vim.schedule(function()
      ui.stop_loading()
      if err then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      local fields = issue.fields or {}
      local lines = {}
      table.insert(lines, "# " .. issue.key .. ": " .. (fields.summary or ""))
      table.insert(lines, "")
      table.insert(lines, "**Status**: " .. (fields.status and fields.status.name or "Unknown"))
      table.insert(lines, "**Assignee**: " .. (fields.assignee and fields.assignee.displayName or "Unassigned"))
      table.insert(lines, "**Priority**: " .. (fields.priority and fields.priority.name or "None"))
      table.insert(lines, "")
      table.insert(lines, "## Description")
      table.insert(lines, "")

      if fields.description then
        local md = util.adf_to_markdown(fields.description)
        for line in md:gmatch("[^\r\n]+") do
          table.insert(lines, line)
        end
      else
        table.insert(lines, "_No description_")
      end

      local p_config = config.get_project_config(state.project_key)
      local ac_field = p_config.acceptance_criteria_field
      if ac_field and fields[ac_field] then
        table.insert(lines, "")
        table.insert(lines, "## Acceptance Criteria")
        table.insert(lines, "")
        local ac_md = util.adf_to_markdown(fields[ac_field])
        for line in ac_md:gmatch("[^\r\n]+") do
          table.insert(lines, line)
        end
      end

      ui.open_markdown_view("Jira: " .. issue.key, lines)
    end)
  end)
end

M.open_in_browser = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then return end

  local base = config.options.jira.base
  if not base or base == "" then
    vim.notify("Jira base URL is not configured", vim.log.levels.ERROR)
    return
  end

  if not base:match("/$") then
    base = base .. "/"
  end

  local url = base .. "browse/" .. node.key
  vim.ui.open(url)
end

M.change_status = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then
    vim.notify("No issue under cursor", vim.log.levels.WARN)
    return
  end

  local jira_api = require("jira.jira-api.api")

  ui.start_loading("Fetching transitions...")
  jira_api.get_transitions(node.key, function(transitions, err)
    vim.schedule(function()
      ui.stop_loading()
      if err then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      if not transitions or #transitions == 0 then
        vim.notify("No transitions available for " .. node.key, vim.log.levels.WARN)
        return
      end

      vim.ui.select(transitions, {
        prompt = "Transition " .. node.key .. " to:",
        format_item = function(item)
          return item.name
        end,
      }, function(choice)
        if not choice then return end

        ui.start_loading("Transitioning...")
        jira_api.transition_issue(node.key, choice.id, function(success, t_err)
          vim.schedule(function()
            ui.stop_loading()
            if t_err then
              vim.notify("Transition failed: " .. t_err, vim.log.levels.ERROR)
              return
            end
            vim.notify(node.key .. " -> " .. choice.name, vim.log.levels.INFO)

            local cache_key = get_cache_key(state.project_key, state.current_view)
            state.cache[cache_key] = nil
            if state.current_view == "My Issues" then
              M.load_my_issues_view()
            else
              M.load_view(state.project_key, state.current_view)
            end
          end)
        end)
      end)
    end)
  end)
end

M.close_issue = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then
    vim.notify("No issue under cursor", vim.log.levels.WARN)
    return
  end

  local jira_api = require("jira.jira-api.api")

  ui.start_loading("Finding done transition...")
  jira_api.get_transitions(node.key, function(transitions, err)
    vim.schedule(function()
      ui.stop_loading()
      if err then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      local done_transition = nil
      for _, t in ipairs(transitions or {}) do
        local name_upper = (t.name or ""):upper()
        if name_upper:find("DONE") or name_upper:find("CLOSED") or name_upper:find("RESOLVED") or name_upper:find("COMPLETE") then
          done_transition = t
          break
        end
      end

      if not done_transition then
        vim.notify("No 'Done' transition found. Use 's' to see all transitions.", vim.log.levels.WARN)
        return
      end

      ui.start_loading("Closing issue...")
      jira_api.transition_issue(node.key, done_transition.id, function(success, t_err)
        vim.schedule(function()
          ui.stop_loading()
          if t_err then
            vim.notify("Failed to close: " .. t_err, vim.log.levels.ERROR)
            return
          end
          vim.notify(node.key .. " -> " .. done_transition.name, vim.log.levels.INFO)

          local cache_key = get_cache_key(state.project_key, state.current_view)
          state.cache[cache_key] = nil
          if state.current_view == "My Issues" then
            M.load_my_issues_view()
          else
            M.load_view(state.project_key, state.current_view)
          end
        end)
      end)
    end)
  end)
end

M._prompt_and_create_story = function(project_key)
  vim.ui.input({ prompt = "Story summary: " }, function(summary)
    if not summary or summary == "" then return end

    local jira_api = require("jira.jira-api.api")
    ui.start_loading("Creating story...")

    jira_api.create_issue(project_key, summary, "Story", function(result, err)
      vim.schedule(function()
        ui.stop_loading()
        if err then
          vim.notify("Failed to create: " .. err, vim.log.levels.ERROR)
          return
        end
        vim.notify("Created " .. result.key .. ": " .. summary, vim.log.levels.INFO)

        local cache_key = get_cache_key(state.project_key, state.current_view)
        state.cache[cache_key] = nil
        if state.current_view == "Backlog" then
          M.load_view(state.project_key, state.current_view)
        elseif state.current_view == "My Issues" then
          local my_cache_key = get_cache_key(nil, "My Issues")
          state.cache[my_cache_key] = nil
          M.load_my_issues_view()
        end
      end)
    end)
  end)
end

M.create_story = function()
  if state.current_view == "My Issues" then
    if #state.my_issues_projects == 0 then
      vim.notify("No projects configured", vim.log.levels.WARN)
      return
    elseif #state.my_issues_projects == 1 then
      M._prompt_and_create_story(state.my_issues_projects[1])
    else
      vim.ui.select(state.my_issues_projects, {
        prompt = "Create story in project:",
      }, function(selected_project)
        if not selected_project then return end
        M._prompt_and_create_story(selected_project)
      end)
    end
  else
    local project = state.project_key
    if not project or project == "" then
      vim.notify("No project context", vim.log.levels.WARN)
      return
    end
    M._prompt_and_create_story(project)
  end
end

M.load_my_issues_view = function()
  if #state.my_issues_projects == 0 then
    vim.notify("No projects selected. Press M to configure.", vim.log.levels.WARN)
    return
  end

  state.current_view = "My Issues"

  local cache_key = get_cache_key(nil, "My Issues")
  local cached_issues = state.cache[cache_key]

  local function process_issues(issues)
    vim.schedule(function()
      ui.stop_loading()
      if not state.win or not api.nvim_win_is_valid(state.win) then
        ui.create_window()
        ui.setup_static_highlights()
      end

      if not issues or #issues == 0 then
        state.tree = {}
        render.clear(state.buf)
        render.render_issue_tree(state.tree, state.current_view)
        vim.notify("No issues found.", vim.log.levels.WARN)
      else
        state.tree = util.build_issue_tree(issues)
        render.clear(state.buf)
        render.render_issue_tree(state.tree, state.current_view)
      end
      M.setup_keymaps()
    end)
  end

  if cached_issues then
    process_issues(cached_issues)
    return
  end

  local project_list = table.concat(state.my_issues_projects, ", ")
  local jql = string.format("assignee = currentUser() AND project IN (%s) ORDER BY updated DESC", project_list)

  ui.start_loading("Loading My Issues...")

  sprint.get_issues_by_jql(state.my_issues_projects[1], jql, function(issues, err)
    if err then
      vim.schedule(function()
        ui.stop_loading()
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    state.cache[cache_key] = issues
    process_issues(issues)
  end)
end

M.prompt_my_issues_projects = function()
  local default = table.concat(state.my_issues_projects, ", ")
  vim.ui.input({ prompt = "My Issues - Projects (comma-separated): ", default = default }, function(input)
    if not input then return end
    if input == "" then
      state.my_issues_projects = {}
      vim.notify("My Issues projects cleared", vim.log.levels.INFO)
      return
    end
    state.my_issues_projects = {}
    for _, p in ipairs(vim.split(input, ",", { trimempty = true })) do
      table.insert(state.my_issues_projects, vim.trim(p):upper())
    end
    local cache_key = get_cache_key(nil, "My Issues")
    state.cache[cache_key] = nil
    M.load_my_issues_view()
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