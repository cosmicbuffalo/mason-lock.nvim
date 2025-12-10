local config = require("mason-lock.config")
local registry = require("mason-registry")

local M = {}

function read_file(file)
	local fd = assert(io.open(file, "r"))
	local data = fd:read("*a")
	fd:close()
	return data
end

function sort_entries(entries)
	table.sort(entries, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return entries
end

function format(entries)
	local lines = { "{" }

	for i, package in ipairs(entries) do
		local line = string.format("  %q: %q", package.name, package.version)
		if i < #entries then
			line = line .. ","
		end
		table.insert(lines, line)
	end

	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

function is_in_ensure_installed(package_name)
	for _, pkg in ipairs(config.ensure_installed) do
		if type(pkg) == "string" and pkg == package_name then
			return true
		elseif type(pkg) == "table" and pkg[1] == package_name then
			return true
		end
	end
	return false
end

function M.read()
	local content = read_file(config.lockfile_path)
	return vim.json.decode(content)
end

function M.write()
	if config._restore_in_progress then
		return
	end

	local packages = registry.get_installed_packages()

	local entries = {}
	for _, package in pairs(packages) do
		if package:is_installed() == false then
			table.insert(entries, nil)
			return
		end

		-- Filter based on lockfile_scope
		if config.lockfile_scope == "ensure_installed" then
			if is_in_ensure_installed(package.name) then
				table.insert(entries, {
					name = package.name,
					version = package:get_installed_version(),
				})
			end
		else
			table.insert(entries, {
				name = package.name,
				version = package:get_installed_version(),
			})
		end
	end

	vim.wait(5000, function()
		return #packages == #entries
	end)

	-- remove anything that failed
	for i, package in pairs(entries) do
		if package == nil then
			entries[i] = nil
		end
	end

	-- sort alphabetically
	entries = sort_entries(entries)

	-- write to file
	local f = assert(io.open(config.lockfile_path, "wb"))
	f:write(format(entries))
	f:close()

	vim.notify("[mason-lock]: Wrote Mason lockfile")
end

function M.restore()
	local lock_data = {}
	local ok, lockfile_str = pcall(read_file, config.lockfile_path)
	if not ok then
		vim.notify("[mason-lock]: Mason lockfile does not exist", vim.log.levels.ERROR)
		return
	end

	lock_data = vim.json.decode(lockfile_str)

	config._restore_in_progress = true

	local ui = require("mason.ui")
	ui.open()

	local package_names = {}
	local finished_handles = {}

	for package_name, package_version in pairs(lock_data) do
		table.insert(package_names, package_name)
		local pkg = registry.get_package(package_name)
		local handle = pkg:install({
			version = package_version,
		})

		handle:once("closed", function()
			table.insert(finished_handles, package_name)
		end)
	end

	local happy, status = vim.wait(1000 * 60, function()
		return #finished_handles == #package_names
	end, 300)

	if not happy then
		if status == -1 then
			vim.notify("[mason-lock]: Timedout waiting for Mason package install", vim.log.levels.ERROR)
		elseif status == -2 then
			vim.notify("[mason-lock]: Wait on Mason package install was interrupted", vim.log.levels.ERROR)
		end
	end

	config._restore_in_progress = false
	vim.notify("[mason-lock]: Restored Mason package versions from lockfile")
end

return M
