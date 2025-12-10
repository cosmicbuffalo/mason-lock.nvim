local config = require("mason-lock.config")
local monkeypatch = require("mason-lock.monkeypatch")
local lockfile = require("mason-lock.lockfile")

local M = {}

function setup_user_commands()
	vim.api.nvim_create_user_command("MasonLock", function()
		lockfile.write()
	end, {
		desc = "Write current package versions to the Mason lockfile",
	})

	vim.api.nvim_create_user_command("MasonLockRestore", function()
		lockfile.restore()
	end, {
		desc = "Re-install Mason packages with the version specified in the lockfile",
	})
end

function setup_registry_listeners()
	local registry = require("mason-registry")
	registry:on(
		"package:install:success",
		vim.schedule_wrap(function(pkg, handle)
			lockfile.write()
		end)
	)

	registry:on(
		"package:uninstall:success",
		vim.schedule_wrap(function(pkg, handle)
			lockfile.write()
		end)
	)
end

function M.setup(cfg)
	config.setup(cfg)
	monkeypatch.patch_package_install()
	setup_user_commands()
	setup_registry_listeners()
end

-- Expose public API
M.write_lockfile = lockfile.write
M.restore_from_lockfile = lockfile.restore
M.ensure_installed = function()
	return config.ensure_installed
end

return M
