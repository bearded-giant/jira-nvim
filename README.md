# jira.nvim

A Neovim plugin for viewing and managing Jira issues with an interactive TUI.

## Features

- **Sprint Board** - View active sprint issues with parent/subtask hierarchy
- **Backlog View** - Browse backlog items not in active sprints
- **My Issues** - Cross-project view of issues assigned to you
- **Custom JQL** - Run arbitrary JQL queries
- **Status Transitions** - Change issue status via picker
- **Create Stories** - Quick story creation with minimal input
- **Close Issues** - One-keypress close to Done status
- **Issue Details** - Popup with status, assignee, priority, time tracking
- **Markdown View** - Read full issue description and acceptance criteria
- **Browser Integration** - Open issues in your browser

## Requirements

- Neovim 0.9+
- curl
- Jira Cloud instance with API access

## Installation

Using lazy.nvim:

```lua
{
  "your-username/jira.nvim",
  config = function()
    require("jira").setup({
      jira = {
        base = "https://your-domain.atlassian.net",
        email = "your-email@example.com",
        token = "your-api-token",
      },
    })
  end,
}
```

For local development:

```lua
{
  dir = "~/path/to/jira.nvim",
  config = function()
    require("jira").setup({
      jira = {
        base = "https://your-domain.atlassian.net",
        email = vim.fn.getenv("JIRA_EMAIL"),
        token = vim.fn.getenv("JIRA_API_TOKEN"),
      },
    })
  end,
}
```

## Configuration

```lua
require("jira").setup({
  jira = {
    base = "https://your-domain.atlassian.net",  -- Required: Jira instance URL
    email = "your-email@example.com",             -- Required: Atlassian account email
    token = "your-api-token",                     -- Required: API token
    limit = 500,                                  -- Optional: Max issues per query (default: 500)
  },
  projects = {
    -- Optional: Project-specific custom field overrides
    ["PROJECT_KEY"] = {
      story_point_field = "customfield_10035",
      acceptance_criteria_field = "customfield_10016",
    },
  },
})
```

### API Token

Generate an API token at: https://id.atlassian.com/manage-profile/security/api-tokens

### Finding Custom Field IDs

Story points and acceptance criteria use custom fields that vary per Jira instance. To find yours:

```bash
curl -s -u "email:token" "https://your-domain.atlassian.net/rest/api/3/field" | \
  jq '.[] | select(.custom==true) | {id, name}'
```

## Usage

Open the Jira board:

```vim
:Jira PROJECT_KEY
```

Or without a project key (you will be prompted):

```vim
:Jira
```

## Keymaps

### Navigation

| Key | Action |
|-----|--------|
| `o` / `Enter` / `Tab` | Toggle node expand/collapse |
| `q` | Close board |

### Views

| Key | Action |
|-----|--------|
| `S` | Switch to Active Sprint |
| `B` | Switch to Backlog |
| `M` | My Issues (configure projects, then load) |
| `J` | Custom JQL search |
| `H` | Show help |
| `r` | Refresh current view |

### Issue Actions

| Key | Action |
|-----|--------|
| `s` | Change issue status |
| `c` | Create new story |
| `d` | Close issue (transition to Done) |
| `K` | Show issue details popup |
| `m` | Read full task as markdown |
| `gx` | Open issue in browser |

## Views

### Active Sprint

Shows all issues in the current active sprint for the specified project. Issues are displayed hierarchically with parent tasks and their subtasks.

### Backlog

Shows issues not assigned to an active sprint and not in Done status.

### My Issues

Cross-project view showing issues assigned to you. When you press `M`, you are prompted for a comma-separated list of project keys (e.g., `SEC, PLAT, INFRA`). The plugin remembers your selection for the session.

### Custom JQL

Press `J` to enter any JQL query. The query is executed against your configured projects.

## Display

Each issue line shows:

- Expand/collapse indicator (for parent issues)
- Issue type icon (Bug, Story, Task, Sub-task)
- Issue key
- Summary (truncated)
- Story points (for parent issues)
- Progress bar (aggregate time for parent issues)
- Time spent / estimated
- Assignee
- Status badge

## License

MIT
