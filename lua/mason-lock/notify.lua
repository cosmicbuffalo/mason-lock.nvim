-- Unified notification module with fidget.nvim integration
local M = {}

--- Check if fidget.nvim is available
---@return boolean, table|nil
local function get_fidget()
  local ok, fidget = pcall(require, "fidget")
  if ok and fidget.progress and fidget.progress.handle then
    return true, fidget
  end
  return false, nil
end

--- Send a notification
---@param msg string The message to display
---@param level number|nil The log level (vim.log.levels.*), defaults to INFO
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify("[mason-lock]: " .. msg, level)
end

--- Create a progress handle for long-running operations
---@param title string The title for the progress task
---@param message string|nil Initial message
---@return table A handle with report() and finish() methods
function M.progress_start(title, message)
  local has_fidget, fidget = get_fidget()

  if has_fidget then
    local handle = fidget.progress.handle.create({
      title = title,
      message = message or "Starting...",
      lsp_client = { name = "mason-lock.nvim" },
      percentage = 0,
    })
    return {
      _fidget_handle = handle,
      report = function(self, opts)
        if self._fidget_handle then
          self._fidget_handle:report({
            message = opts.message,
            percentage = opts.percentage,
          })
        end
      end,
      finish = function(self, finish_message)
        if self._fidget_handle then
          if finish_message then
            self._fidget_handle.message = finish_message
          end
          self._fidget_handle:finish()
        end
      end,
      cancel = function(self, error_message)
        if self._fidget_handle then
          if error_message then
            self._fidget_handle.message = error_message
          end
          self._fidget_handle:finish()
        end
      end,
    }
  else
    -- Fallback: use vim.notify for key events
    if message then
      M.notify(message)
    end
    return {
      report = function(_, _)
        -- No-op in fallback mode to avoid spamming notifications
      end,
      finish = function(_, finish_message)
        if finish_message then
          M.notify(finish_message)
        end
      end,
      cancel = function(_, error_message)
        if error_message then
          M.notify(error_message, vim.log.levels.ERROR)
        end
      end,
    }
  end
end

--- Create a progress handle specifically for restore operations
---@param total_packages number Total number of packages to restore
---@return table A handle with update_progress(), finish(), and cancel() methods
function M.restore_progress(total_packages)
  local handle = M.progress_start("Lockfile Restore", string.format("Restoring %d packages...", total_packages))
  local completed = 0

  return {
    _handle = handle,
    update = function(self, package_name)
      completed = completed + 1
      local percentage = math.floor((completed / total_packages) * 100)
      self._handle:report({
        message = string.format("Installing %d/%d: %s", completed, total_packages, package_name),
        percentage = percentage,
      })
    end,
    finish = function(self)
      self._handle:finish(string.format("Restored %d packages from lockfile", total_packages))
    end,
    cancel = function(self, error_message)
      self._handle:cancel(error_message)
    end,
  }
end

--- Create a progress handle for write operations
---@return table A handle with finish() and cancel() methods
function M.write_progress()
  return M.progress_start("Lockfile Write", "Writing lockfile...")
end

return M
