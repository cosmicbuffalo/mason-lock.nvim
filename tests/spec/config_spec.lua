describe("config", function()
  local config
  local cache

  local temp_dir
  local lockfile_path

  before_each(function()
    -- Reset modules
    package.loaded["mason-lock.config"] = nil
    package.loaded["mason-lock.cache"] = nil

    temp_dir = test_helpers.create_temp_dir()
    lockfile_path = temp_dir .. "/mason-lock.json"

    config = require("mason-lock.config")
    cache = require("mason-lock.cache")
  end)

  after_each(function()
    test_helpers.cleanup_temp_dir(temp_dir)
  end)

  describe("setup", function()
    it("should use defaults when no config provided", function()
      config.setup(nil)

      assert.are.equal("locked_packages", config.lockfile_scope)
      assert.is_table(config.locked_packages)
    end)

    it("should override lockfile_path", function()
      config.setup({ lockfile_path = lockfile_path })
      assert.are.equal(lockfile_path, config.lockfile_path)
    end)

    it("should override lockfile_scope", function()
      config.setup({ lockfile_scope = "all" })
      assert.are.equal("all", config.lockfile_scope)
    end)

    it("should override locked_packages", function()
      local packages = { "lua-language-server", "stylua" }
      config.setup({ locked_packages = packages })
      assert.are.same(packages, config.locked_packages)
    end)

    it("should reject invalid lockfile_scope", function()
      local capture = test_helpers.capture_notifications()

      config.setup({ lockfile_scope = "invalid" })

      capture.restore()
      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "Invalid lockfile_scope"))
    end)

    it("should translate deprecated ensure_installed to locked_packages", function()
      local capture = test_helpers.capture_notifications()
      local packages = { "lua-language-server", "stylua" }

      config.setup({ ensure_installed = packages })

      capture.restore()
      assert.are.same(packages, config.locked_packages)
      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "ensure_installed.*deprecated"))
    end)

    it("should translate deprecated lockfile_scope ensure_installed to locked_packages", function()
      local capture = test_helpers.capture_notifications()

      config.setup({ lockfile_scope = "ensure_installed" })

      capture.restore()
      assert.are.equal("locked_packages", config.lockfile_scope)
      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "lockfile_scope.*ensure_installed.*deprecated"))
    end)

    it("should prefer locked_packages over ensure_installed when both provided", function()
      local capture = test_helpers.capture_notifications()
      local old_packages = { "stylua" }
      local new_packages = { "lua-language-server", "stylua" }

      config.setup({ ensure_installed = old_packages, locked_packages = new_packages })

      capture.restore()
      assert.are.same(new_packages, config.locked_packages)
      -- No deprecation warning since locked_packages was provided
      assert.are.equal(0, #capture.notifications)
    end)
  end)

  describe("get_pinned_version", function()
    it("should return nil for unpinned package", function()
      config.locked_packages = { "lua-language-server", "stylua" }
      assert.is_nil(config.get_pinned_version("lua-language-server"))
    end)

    it("should return version for pinned package", function()
      config.locked_packages = {
        { "lua-language-server", version = "3.6.0" },
        "stylua",
      }
      assert.are.equal("3.6.0", config.get_pinned_version("lua-language-server"))
    end)

    it("should return nil for package not in locked_packages", function()
      config.locked_packages = { "stylua" }
      assert.is_nil(config.get_pinned_version("lua-language-server"))
    end)
  end)

  describe("get_locked_version", function()
    it("should return pinned version first", function()
      config.locked_packages = {
        { "lua-language-server", version = "3.6.0" },
      }
      -- Even if cache has different version
      cache.set({ ["lua-language-server"] = "3.5.0" })

      assert.are.equal("3.6.0", config.get_locked_version("lua-language-server"))
    end)

    it("should return cached version when not pinned", function()
      config.locked_packages = { "lua-language-server" }
      cache.set({ ["lua-language-server"] = "3.5.0" })

      assert.are.equal("3.5.0", config.get_locked_version("lua-language-server"))
    end)

    it("should return nil when not found", function()
      config.locked_packages = {}
      cache.set({})

      assert.is_nil(config.get_locked_version("nonexistent"))
    end)

    it("should return nil for unknown package", function()
      config.locked_packages = {}
      assert.is_nil(config.get_locked_version("package"))
    end)
  end)
end)
