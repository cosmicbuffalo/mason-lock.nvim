-- Minimal init for testing mason-lock.nvim
local plenary_path = vim.env.PLENARY_PATH or "/tmp/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 0 then
  plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
end
if vim.fn.isdirectory(plenary_path) == 0 then
  plenary_path = vim.fn.expand("~/.local/share/nvim/site/pack/testing/start/plenary.nvim")
end

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Load plenary plugin to register commands
vim.cmd("runtime plugin/plenary.vim")

-- Disable swap files for tests
vim.opt.swapfile = false

-- Test helpers module
_G.test_helpers = {}

--- Create a temporary directory
---@return string path The temporary directory path
function _G.test_helpers.create_temp_dir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

--- Clean up a temporary directory
---@param dir string The directory to remove
function _G.test_helpers.cleanup_temp_dir(dir)
  if dir and vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, "rf")
  end
end

--- Wait for a condition with timeout
---@param condition fun(): boolean The condition function
---@param timeout_ms number Timeout in milliseconds
---@return boolean success True if condition was met
function _G.test_helpers.wait_for(condition, timeout_ms)
  timeout_ms = timeout_ms or 5000
  local start = vim.uv.now()
  while vim.uv.now() - start < timeout_ms do
    if condition() then
      return true
    end
    vim.wait(10)
  end
  return false
end

--- Capture vim.notify calls
---@return table A table with captured notifications and a restore function
function _G.test_helpers.capture_notifications()
  local notifications = {}
  local original_notify = vim.notify

  vim.notify = function(msg, level, opts)
    table.insert(notifications, {
      msg = msg,
      level = level,
      opts = opts,
    })
  end

  return {
    notifications = notifications,
    restore = function()
      vim.notify = original_notify
    end,
    clear = function()
      notifications = {}
    end,
  }
end

--- Create a mock file with content
---@param path string The file path
---@param content string The content to write
function _G.test_helpers.write_file(path, content)
  local f = io.open(path, "w")
  if f then
    f:write(content)
    f:close()
  end
end

--- Read a file's content
---@param path string The file path
---@return string|nil content The file content or nil if not found
function _G.test_helpers.read_file(path)
  local f = io.open(path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    return content
  end
  return nil
end

-- Mock mason-registry for tests
local mock_registry = {
  _packages = {},
  _listeners = {},

  get_installed_packages = function()
    return mock_registry._packages
  end,

  get_package = function(name)
    for _, pkg in ipairs(mock_registry._packages) do
      if pkg.name == name then
        return pkg
      end
    end
    error("Package not found: " .. name)
  end,

  on = function(self, event, callback)
    if not self._listeners[event] then
      self._listeners[event] = {}
    end
    table.insert(self._listeners[event], callback)
  end,

  emit = function(self, event, ...)
    if self._listeners[event] then
      for _, callback in ipairs(self._listeners[event]) do
        callback(...)
      end
    end
  end,

  -- Test helpers
  _add_mock_package = function(name, version, installed)
    local pkg = {
      name = name,
      _version = version,
      _installed = installed ~= false,
      is_installed = function(self)
        return self._installed
      end,
      get_installed_version = function(self)
        return self._version
      end,
      install = function(_self, _opts)
        local handle = {
          _callbacks = {},
          once = function(h, event, callback)
            h._callbacks[event] = callback
          end,
        }
        -- Simulate async install completion
        vim.defer_fn(function()
          if handle._callbacks["closed"] then
            handle._callbacks["closed"]()
          end
        end, 10)
        return handle
      end,
    }
    table.insert(mock_registry._packages, pkg)
    return pkg
  end,

  _clear = function()
    mock_registry._packages = {}
    mock_registry._listeners = {}
  end,
}

-- Mock mason.ui for tests
local mock_ui = {
  open = function() end,
}

-- Mock mason-core.package for tests
local mock_package = {
  _mason_lock_patched = false,
  install = function(self, _opts, _callback)
    return self
  end,
}

-- Register mocks
package.loaded["mason-registry"] = mock_registry
package.loaded["mason.ui"] = mock_ui
package.loaded["mason-core.package"] = mock_package

-- Expose mock registry for tests
_G.mock_registry = mock_registry
_G.mock_package = mock_package
