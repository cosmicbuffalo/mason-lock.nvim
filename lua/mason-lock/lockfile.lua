local config = require("mason-lock.config")
local registry = require("mason-registry")
local async_io = require("mason-lock.async_io")
local cache = require("mason-lock.cache")
local notify = require("mason-lock.notify")

local M = {}

-- Debounce state
local _debounce_timer = nil
local _debounce_delay = 500 -- milliseconds

local uv = vim.uv or vim.loop

local function read_file_sync(file)
  local fd = assert(io.open(file, "r"))
  local data = fd:read("*a")
  fd:close()
  return data
end

local function sort_entries(entries)
  table.sort(entries, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

local function format(entries)
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

local function is_in_ensure_installed(package_name)
  for _, pkg in ipairs(config.ensure_installed) do
    if type(pkg) == "string" and pkg == package_name then
      return true
    elseif type(pkg) == "table" and pkg[1] == package_name then
      return true
    end
  end
  return false
end

--- Read lockfile synchronously (kept for backwards compatibility)
---@return table The parsed lockfile data
function M.read()
  local content = read_file_sync(config.lockfile_path)
  return vim.json.decode(content)
end

--- Read lockfile asynchronously
---@param callback fun(err: string|nil, data: table|nil) Called with error or data
function M.read_async(callback)
  async_io.read_file(config.lockfile_path, function(err, data)
    if err then
      callback(err, nil)
      return
    end

    local ok, parsed = pcall(vim.json.decode, data)
    if not ok then
      callback("Failed to parse lockfile JSON: " .. tostring(parsed), nil)
      return
    end

    callback(nil, parsed)
  end)
end

--- Collect package entries for writing
---@param callback fun(entries: table) Called with collected entries
local function collect_entries(callback)
  local packages = registry.get_installed_packages()
  local entries = {}
  local pending = 0
  local total = #packages

  if total == 0 then
    callback({})
    return
  end

  for _, package in pairs(packages) do
    if package:is_installed() then
      -- Filter based on lockfile_scope
      local should_include = config.lockfile_scope ~= "ensure_installed" or is_in_ensure_installed(package.name)

      if should_include then
        pending = pending + 1
        -- Get version - this should be synchronous for installed packages
        local version = package:get_installed_version()
        if version then
          table.insert(entries, {
            name = package.name,
            version = version,
          })
        end
      end
    end
  end

  -- Sort and return
  entries = sort_entries(entries)
  callback(entries)
end

--- Write lockfile synchronously (deprecated, kept for backwards compatibility)
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

  -- Update cache
  local cache_data = {}
  for _, entry in ipairs(entries) do
    cache_data[entry.name] = entry.version
  end
  cache.set(cache_data)

  notify.notify("Wrote Mason lockfile")
end

--- Write lockfile asynchronously
---@param callback fun(err: string|nil)|nil Optional callback
function M.write_async(callback)
  if config._restore_in_progress then
    if callback then
      callback(nil)
    end
    return
  end

  local progress = notify.write_progress()

  collect_entries(function(entries)
    local content = format(entries)

    async_io.write_file(config.lockfile_path, content, function(err)
      if err then
        progress:cancel("Failed to write lockfile: " .. tostring(err))
        if callback then
          callback(err)
        end
        return
      end

      -- Update cache with new data
      local cache_data = {}
      for _, entry in ipairs(entries) do
        cache_data[entry.name] = entry.version
      end
      cache.set(cache_data)

      progress:finish("Wrote Mason lockfile")
      if callback then
        callback(nil)
      end
    end)
  end)
end

--- Schedule a debounced write
---@param callback fun(err: string|nil)|nil Optional callback
function M.schedule_write(callback)
  -- Cancel any pending timer
  if _debounce_timer then
    uv.timer_stop(_debounce_timer)
    uv.close(_debounce_timer)
    _debounce_timer = nil
  end

  -- Create new timer
  _debounce_timer = uv.new_timer()
  uv.timer_start(_debounce_timer, _debounce_delay, 0, function()
    vim.schedule(function()
      if _debounce_timer then
        uv.timer_stop(_debounce_timer)
        uv.close(_debounce_timer)
        _debounce_timer = nil
      end
      M.write_async(callback)
    end)
  end)
end

--- Restore packages from lockfile synchronously (deprecated, kept for backwards compatibility)
function M.restore()
  local lock_data = {}
  local ok, lockfile_str = pcall(read_file_sync, config.lockfile_path)
  if not ok then
    notify.notify("Mason lockfile does not exist", vim.log.levels.ERROR)
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
      notify.notify("Timed out waiting for Mason package install", vim.log.levels.ERROR)
    elseif status == -2 then
      notify.notify("Wait on Mason package install was interrupted", vim.log.levels.ERROR)
    end
  end

  config._restore_in_progress = false
  notify.notify("Restored Mason package versions from lockfile")
end

--- Restore packages from lockfile asynchronously
---@param callback fun(err: string|nil)|nil Optional callback
function M.restore_async(callback)
  M.read_async(function(err, lock_data)
    if err then
      notify.notify("Mason lockfile does not exist or is invalid", vim.log.levels.ERROR)
      if callback then
        callback(err)
      end
      return
    end

    if not lock_data or vim.tbl_isempty(lock_data) then
      notify.notify("Lockfile is empty", vim.log.levels.WARN)
      if callback then
        callback(nil)
      end
      return
    end

    config._restore_in_progress = true

    local ui = require("mason.ui")
    ui.open()

    -- Count packages
    local package_names = {}
    for package_name, _ in pairs(lock_data) do
      table.insert(package_names, package_name)
    end

    local total = #package_names
    local finished_count = 0
    local failed_packages = {}

    local progress = notify.restore_progress(total)

    for package_name, package_version in pairs(lock_data) do
      local ok_pkg, pkg = pcall(registry.get_package, package_name)
      if not ok_pkg or not pkg then
        finished_count = finished_count + 1
        table.insert(failed_packages, package_name)
        progress:update(package_name .. " (not found)")
      else
        local handle = pkg:install({
          version = package_version,
        })

        handle:once("closed", function()
          finished_count = finished_count + 1
          vim.schedule(function()
            progress:update(package_name)

            -- Check if all done
            if finished_count >= total then
              config._restore_in_progress = false

              if #failed_packages > 0 then
                notify.notify(
                  string.format(
                    "Restored %d/%d packages. Failed: %s",
                    total - #failed_packages,
                    total,
                    table.concat(failed_packages, ", ")
                  ),
                  vim.log.levels.WARN
                )
              else
                progress:finish()
              end

              if callback then
                callback(nil)
              end
            end
          end)
        end)
      end
    end

    -- Handle edge case where all packages failed synchronously
    if finished_count >= total then
      config._restore_in_progress = false
      if callback then
        callback(nil)
      end
    end
  end)
end

return M
