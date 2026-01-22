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

local function is_in_locked_packages(package_name)
  for _, pkg in ipairs(config.locked_packages) do
    if type(pkg) == "string" and pkg == package_name then
      return true
    elseif type(pkg) == "table" and pkg[1] == package_name then
      return true
    end
  end
  return false
end

--- Read lockfile asynchronously
---@param callback fun(err: string|nil, data: table|nil) Called with error or data
function M.read(callback)
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
  local installed_names = {} -- Track installed package names

  for _, package in pairs(packages) do
    if package:is_installed() then
      -- Filter based on lockfile_scope
      local should_include = config.lockfile_scope ~= "locked_packages" or is_in_locked_packages(package.name)

      if should_include then
        -- Get version - this should be synchronous for installed packages
        local version = package:get_installed_version()
        if version then
          table.insert(entries, {
            name = package.name,
            version = version,
          })
          installed_names[package.name] = true
        end
      end
    end
  end

  -- Preserve uninstalled entries from existing lockfile
  if config.preserve_uninstalled then
    local merge_existing = function(existing_data)
      if config._debug_mode then
        vim.notify(
          "[mason-lock DEBUG] merge_existing called, existing_data: " .. vim.inspect(existing_data),
          vim.log.levels.DEBUG
        )
        vim.notify("[mason-lock DEBUG] installed_names: " .. vim.inspect(installed_names), vim.log.levels.DEBUG)
      end
      if existing_data then
        for pkg_name, pkg_version in pairs(existing_data) do
          if not installed_names[pkg_name] then
            -- Check lockfile_scope for uninstalled packages too
            local should_include = config.lockfile_scope ~= "locked_packages" or is_in_locked_packages(pkg_name)
            if config._debug_mode then
              vim.notify(
                "[mason-lock DEBUG] pkg: " .. pkg_name .. ", should_include: " .. tostring(should_include),
                vim.log.levels.DEBUG
              )
            end
            if should_include then
              table.insert(entries, { name = pkg_name, version = pkg_version })
            end
          end
        end
      end
      if config._debug_mode then
        vim.notify("[mason-lock DEBUG] final entries: " .. vim.inspect(entries), vim.log.levels.DEBUG)
      end
      entries = sort_entries(entries)
      callback(entries)
    end

    if config._debug_mode then
      vim.notify("[mason-lock DEBUG] cache.is_loaded(): " .. tostring(cache.is_loaded()), vim.log.levels.DEBUG)
    end
    if cache.is_loaded() then
      merge_existing(cache.get())
    else
      -- Fallback: read lockfile directly
      M.read(function(err, data)
        if config._debug_mode then
          vim.notify("[mason-lock DEBUG] M.read fallback, err: " .. tostring(err), vim.log.levels.DEBUG)
        end
        merge_existing(err and nil or data)
      end)
    end
    return
  end

  -- Original path when preserve_uninstalled is false
  entries = sort_entries(entries)
  callback(entries)
end

--- Write lockfile asynchronously
---@param callback fun(err: string|nil)|nil Optional callback
function M.write(callback)
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
      M.write(callback)
    end)
  end)
end

--- Restore packages from lockfile asynchronously
---@param callback fun(err: string|nil)|nil Optional callback
function M.restore(callback)
  M.read(function(err, lock_data)
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
