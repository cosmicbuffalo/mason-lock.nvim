describe("notify", function()
  local notify

  before_each(function()
    -- Reset module
    package.loaded["mason-lock.notify"] = nil
    -- Ensure fidget is not available in tests
    package.loaded["fidget"] = nil
    notify = require("mason-lock.notify")
  end)

  describe("notify", function()
    it("should call vim.notify with prefixed message", function()
      local capture = test_helpers.capture_notifications()

      notify.notify("Test message")

      capture.restore()
      assert.are.equal(1, #capture.notifications)
      assert.are.equal("[mason-lock]: Test message", capture.notifications[1].msg)
      assert.are.equal(vim.log.levels.INFO, capture.notifications[1].level)
    end)

    it("should respect log level", function()
      local capture = test_helpers.capture_notifications()

      notify.notify("Error message", vim.log.levels.ERROR)

      capture.restore()
      assert.are.equal(1, #capture.notifications)
      assert.are.equal(vim.log.levels.ERROR, capture.notifications[1].level)
    end)
  end)

  describe("progress_start", function()
    it("should return a handle with report and finish methods", function()
      local handle = notify.progress_start("test", "Starting...")

      assert.is_not_nil(handle)
      assert.is_function(handle.report)
      assert.is_function(handle.finish)
      assert.is_function(handle.cancel)
    end)

    it("should notify on start when message provided (fallback mode)", function()
      local capture = test_helpers.capture_notifications()

      notify.progress_start("test", "Starting task...")

      capture.restore()
      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "Starting task"))
    end)

    it("should notify on finish", function()
      local handle = notify.progress_start("test", "Starting...")

      local capture = test_helpers.capture_notifications()
      handle:finish("Task completed")
      capture.restore()

      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "Task completed"))
    end)

    it("should notify error on cancel", function()
      local handle = notify.progress_start("test", "Starting...")

      local capture = test_helpers.capture_notifications()
      handle:cancel("Task failed")
      capture.restore()

      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "Task failed"))
      assert.are.equal(vim.log.levels.ERROR, capture.notifications[1].level)
    end)
  end)

  describe("restore_progress", function()
    it("should create progress handle for restore operation", function()
      local handle = notify.restore_progress(5)

      assert.is_not_nil(handle)
      assert.is_function(handle.update)
      assert.is_function(handle.finish)
      assert.is_function(handle.cancel)
    end)

    it("should track progress updates", function()
      local handle = notify.restore_progress(3)

      -- In fallback mode, update is a no-op
      handle:update("package1")
      handle:update("package2")
      handle:update("package3")

      local capture = test_helpers.capture_notifications()
      handle:finish()
      capture.restore()

      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "Restored 3 packages"))
    end)
  end)

  describe("write_progress", function()
    it("should create progress handle for write operation", function()
      local handle = notify.write_progress()

      assert.is_not_nil(handle)
      assert.is_function(handle.report)
      assert.is_function(handle.finish)
      assert.is_function(handle.cancel)
    end)
  end)

  describe("with fidget.nvim mocked", function()
    local mock_fidget

    before_each(function()
      -- Create a mock fidget module
      local mock_handle = {
        _reports = {},
        _finished = false,
        report = function(self, opts)
          table.insert(self._reports, opts)
        end,
        finish = function(self)
          self._finished = true
        end,
      }

      mock_fidget = {
        progress = {
          handle = {
            create = function(opts)
              mock_handle._create_opts = opts
              return mock_handle
            end,
          },
        },
        _mock_handle = mock_handle,
      }

      package.loaded["fidget"] = mock_fidget
      package.loaded["mason-lock.notify"] = nil
      notify = require("mason-lock.notify")
    end)

    after_each(function()
      package.loaded["fidget"] = nil
    end)

    it("should use fidget for progress when available", function()
      local handle = notify.progress_start("test-title", "Starting...")

      assert.is_not_nil(handle._fidget_handle)
      assert.are.equal("test-title", mock_fidget._mock_handle._create_opts.title)
      assert.are.equal("Starting...", mock_fidget._mock_handle._create_opts.message)
    end)

    it("should call fidget report on progress update", function()
      local handle = notify.progress_start("test", "Starting...")

      handle:report({ message = "Progress...", percentage = 50 })

      assert.are.equal(1, #mock_fidget._mock_handle._reports)
      assert.are.equal("Progress...", mock_fidget._mock_handle._reports[1].message)
      assert.are.equal(50, mock_fidget._mock_handle._reports[1].percentage)
    end)

    it("should call fidget finish on complete", function()
      local handle = notify.progress_start("test", "Starting...")

      handle:finish("Done")

      assert.is_true(mock_fidget._mock_handle._finished)
    end)
  end)
end)
