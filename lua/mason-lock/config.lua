local M = {}

local defaults = {
  lockfile_path = vim.fn.stdpath("config") .. "/mason-lock.json",
  lockfile_scope = "locked_packages",
  locked_packages = {},
  preserve_uninstalled = true,
}

M.lockfile_path = defaults.lockfile_path
M.lockfile_scope = defaults.lockfile_scope
M.locked_packages = defaults.locked_packages
M.preserve_uninstalled = defaults.preserve_uninstalled
-- Internal state
M._restore_in_progress = false
M._debug_mode = false

local function validate(cfg)
  if not cfg then
    return true, nil
  end

  if cfg.lockfile_scope then
    if cfg.lockfile_scope ~= "locked_packages" and cfg.lockfile_scope ~= "all" then
      return false, 'Invalid lockfile_scope "' .. cfg.lockfile_scope .. '". Must be "locked_packages" or "all"'
    end
  end

  return true, nil
end

function M.setup(cfg)
  local ok, err = validate(cfg)
  if not ok then
    vim.notify("[mason-lock]: " .. err, vim.log.levels.ERROR)
    return
  end
  if not cfg then
    return
  end
  if cfg.lockfile_path then
    M.lockfile_path = cfg.lockfile_path
  end
  if cfg.lockfile_scope then
    M.lockfile_scope = cfg.lockfile_scope
  end
  if cfg.locked_packages then
    M.locked_packages = cfg.locked_packages
  end
  if cfg.preserve_uninstalled ~= nil then
    M.preserve_uninstalled = cfg.preserve_uninstalled
  end
end

function M.get_pinned_version(package_name)
  for _, pkg in ipairs(M.locked_packages) do
    if type(pkg) == "table" and pkg[1] == package_name and pkg.version then
      return pkg.version
    end
  end
  return nil
end

---@param package_name string The package name
---@return string|nil version The locked version or nil
function M.get_locked_version(package_name)
  local pinned_version = M.get_pinned_version(package_name)
  if pinned_version then
    return pinned_version
  end

  local cache = require("mason-lock.cache")
  return cache.get_version(package_name)
end

return M
