local M = {}

local api = vim.api

local state = require "jira.state"
local config = require "jira.config"
local render = require "jira.render"
local util = require "jira.util"
local sprint = require("jira.jira-api.sprint")

M.setup = function(opts)
  config.setup(opts)
end

M.open = function(project_key)
  project_key = project_key or os.getenv("JIRA_PROJECT")
  if not project_key then
    project_key = vim.fn.input("Jira Project Key: ")
  end

  if not project_key or project_key == "" then
     vim.notify("Project key is required", vim.log.levels.ERROR)
     return
  end

  vim.notify("Loading Dashboard for " .. project_key .. "...", vim.log.levels.INFO)
  local issues, err = sprint.get_active_sprint_issues(project_key)
  if err then
    vim.notify("Error: " .. err, vim.log.levels.ERROR)
    return
  end
  if #issues == 0 then
    vim.notify("No issues in active sprint.", vim.log.levels.WARN)
    return
  end

  -- Fetch Status Colors
  local api_client = require("jira.jira-api.api")
  local project_statuses, st_err = api_client.get_project_statuses(project_key)
  if not st_err and project_statuses then
    local function get_theme_color(groups, attr)
      for _, g in ipairs(groups) do
        local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
        if hl and hl[attr] then return hl[attr] end
      end
      return nil
    end

    local color_map = {
      ["green"] = get_theme_color({ "DiagnosticOk", "String", "DiffAdd" }, "fg") or "#a6e3a1",
      ["blue-gray"] = get_theme_color({ "DiagnosticInfo", "Function", "DiffChange" }, "fg") or "#89b4fa",
      ["medium-gray"] = get_theme_color({ "DiagnosticHint", "Comment", "NonText" }, "fg") or "#9399b2",
      ["yellow"] = get_theme_color({ "DiagnosticWarn", "WarningMsg", "Todo" }, "fg") or "#f9e2af",
      ["red"] = get_theme_color({ "DiagnosticError", "ErrorMsg", "DiffDelete" }, "fg") or "#f38ba8",
      ["brown"] = get_theme_color({ "Special", "Constant" }, "fg") or "#ef9f76",
    }

    local bg_base = get_theme_color({ "Normal" }, "bg") or "#1e1e2e"

    for _, itype in ipairs(project_statuses) do
      for _, st in ipairs(itype.statuses or {}) do
        local hl_name = "JiraStatus_" .. st.name:gsub("%s+", "_")
        local color_name = st.statusCategory and st.statusCategory.colorName or "medium-gray"
        local color = color_map[color_name] or color_map["medium-gray"]

        vim.api.nvim_set_hl(0, hl_name, {
          fg = bg_base,
          bg = color,
          bold = true,
        })
        state.status_hls[st.name] = hl_name
      end
    end
  end

  -- Backdrop
  local dim_buf = api.nvim_create_buf(false, true)
  state.dim_win = api.nvim_open_win(dim_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 100,
  })
  api.nvim_win_set_option(state.dim_win, "winblend", 50)
  api.nvim_win_set_option(state.dim_win, "winhighlight", "Normal:JiraDim")
  vim.api.nvim_set_hl(0, "JiraDim", { bg = "#000000" })

  state.buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")

  local height = 42
  local width = 160

  state.win = api.nvim_open_win(state.buf, true, {
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2 - 1,

    relative = 'editor',
    style = "minimal",
    border = { " ", " ", " ", " ", " ", " ", " ", " " },
    title = { { " 󱥚 Jira Board ", "StatusLineTerm" } },
    title_pos = "center",
    zindex = 101,
  })

  api.nvim_win_set_hl_ns(state.win, state.ns)
  api.nvim_win_set_option(state.win, "cursorline", true)

  api.nvim_create_autocmd("BufWipeout", {
    buffer = state.buf,
    callback = function()
      if state.dim_win and api.nvim_win_is_valid(state.dim_win) then
        api.nvim_win_close(state.dim_win, true)
        state.dim_win = nil
      end
    end,
  })

  vim.api.nvim_set_hl(0, "JiraTopLevel", {
    link = "CursorLineNr",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "JiraStoryPoint", {
    link = "Error",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "JiraAssignee", {
    link = "MoreMsg",
  })

  vim.api.nvim_set_hl(0, "JiraAssigneeUnassigned", {
    link = "Comment",
    italic = true,
  })

  vim.api.nvim_set_hl(0, "exgreen", {
    fg = "#a6e3a1", -- Green-ish
  })

  vim.api.nvim_set_hl(0, "JiraStatus", {
    link = "lualine_a_insert",
  })

  vim.api.nvim_set_hl(0, "JiraStatusRoot", {
    link = "lualine_a_insert",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "JiraIconBug", { fg = "#f38ba8" }) -- Red
  vim.api.nvim_set_hl(0, "JiraIconStory", { fg = "#a6e3a1" }) -- Green
  vim.api.nvim_set_hl(0, "JiraIconTask", { fg = "#89b4fa" }) -- Blue
  vim.api.nvim_set_hl(0, "JiraIconSubTask", { fg = "#94e2d5" }) -- Teal
  vim.api.nvim_set_hl(0, "JiraIconTest", { fg = "#fab387" }) -- Peach
  vim.api.nvim_set_hl(0, "JiraIconDesign", { fg = "#cba6f7" }) -- Mauve
  vim.api.nvim_set_hl(0, "JiraIconOverhead", { fg = "#9399b2" }) -- Overlay2
  vim.api.nvim_set_hl(0, "JiraIconImp", { fg = "#89dceb" }) -- Sky

  api.nvim_set_current_win(state.win)

  local tree = util.build_issue_tree(issues)
  render.render_issue_tree(tree)
end

return M
