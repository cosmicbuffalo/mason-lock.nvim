local async_io = require("mason-lock.async_io")

local M = {}

local _cache = nil
local _loading = false
local _loaded = false
local _callbacks = {}

---@param lockfile_path string Path to the lockfile
---@param callback fun(err: string|nil, data: table|nil)|nil Optional callback
function M.load(lockfile_path, callback)
  if _loaded then
    if callback then
      callback(nil, _cache)
    end
    return
  end

  if _loading then
    if callback then
      table.insert(_callbacks, callback)
    end
    return
  end

  _loading = true
  if callback then
    table.insert(_callbacks, callback)
  end

  async_io.read_file(lockfile_path, function(err, data)
    _loading = false

    if err then
      _loaded = false
      _cache = nil
      for _, cb in ipairs(_callbacks) do
        cb(err, nil)
      end
      _callbacks = {}
      return
    end

    local ok, parsed = pcall(vim.json.decode, data)
    if not ok then
      _loaded = false
      _cache = nil
      local parse_err = "Failed to parse lockfile JSON: " .. tostring(parsed)
      for _, cb in ipairs(_callbacks) do
        cb(parse_err, nil)
      end
      _callbacks = {}
      return
    end

    _cache = parsed
    _loaded = true

    for _, cb in ipairs(_callbacks) do
      cb(nil, _cache)
    end
    _callbacks = {}
  end)
end

---@return table|nil The cached data, or nil if not loaded
function M.get()
  return _cache
end

---@return boolean
function M.is_loaded()
  return _loaded
end

---@return boolean
function M.is_loading()
  return _loading
end

---@param data table The lockfile data to cache
function M.set(data)
  _cache = data
  _loaded = true
end

function M.invalidate()
  _cache = nil
  _loaded = false
  _loading = false
  _callbacks = {}
end

---@param package_name string The package name
---@return string|nil version The locked version or nil
function M.get_version(package_name)
  if not _loaded then
    return nil
  end
  return _cache and _cache[package_name] or nil
end

return M
