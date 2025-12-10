config = require("mason-lock.config")

local M = {}

function M.patch_package_install()
	local Package = require("mason-core.package")

	-- Only patch once
	if Package._mason_lock_patched then
		return
	end

	local original_install = Package.install

	function Package:install(opts, callback)
		opts = opts or {}

		-- Check if package is pinned
		local pinned_version = config.get_pinned_version(self.name)
		if pinned_version ~= nil then
			-- If a version is specified and it doesn't match the pin, warn that requested version is being ignored
			if opts.version and opts.version ~= pinned_version then
				vim.notify(
					string.format(
						'[mason-lock]: Package "%s" is pinned to version "%s". Ignoring request to install version "%s".',
						self.name,
						pinned_version,
						opts.version
					),
					vim.log.levels.WARN
				)
			end

			-- Force the pinned version
			opts.version = pinned_version
		elseif not opts.version then
			-- Only inject version if not already specified and not pinned
			local locked_version = config.get_locked_version(self.name)
			if locked_version then
				opts.version = locked_version
			end
		end

		return original_install(self, opts, callback)
	end

	Package._mason_lock_patched = true
end

return M
