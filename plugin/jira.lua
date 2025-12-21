vim.api.nvim_create_user_command("Jira", function(opts)
  require("jira").open(opts.args ~= "" and opts.args or nil)
end, { nargs = "?" })
