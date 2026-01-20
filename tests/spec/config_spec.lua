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

      assert.are.equal("ensure_installed", config.lockfile_scope)
      assert.is_table(config.ensure_installed)
    end)

    it("should override lockfile_path", function()
      config.setup({ lockfile_path = lockfile_path })
      assert.are.equal(lockfile_path, config.lockfile_path)
    end)

    it("should override lockfile_scope", function()
      config.setup({ lockfile_scope = "all" })
      assert.are.equal("all", config.lockfile_scope)
    end)

    it("should override ensure_installed", function()
      local packages = { "lua-language-server", "stylua" }
      config.setup({ ensure_installed = packages })
      assert.are.same(packages, config.ensure_installed)
    end)

    it("should reject invalid lockfile_scope", function()
      local capture = test_helpers.capture_notifications()

      config.setup({ lockfile_scope = "invalid" })

      capture.restore()
      assert.are.equal(1, #capture.notifications)
      assert.is_truthy(string.find(capture.notifications[1].msg, "Invalid lockfile_scope"))
    end)
  end)

  describe("get_pinned_version", function()
    it("should return nil for unpinned package", function()
      config.ensure_installed = { "lua-language-server", "stylua" }
      assert.is_nil(config.get_pinned_version("lua-language-server"))
    end)

    it("should return version for pinned package", function()
      config.ensure_installed = {
        { "lua-language-server", version = "3.6.0" },
        "stylua",
      }
      assert.are.equal("3.6.0", config.get_pinned_version("lua-language-server"))
    end)

    it("should return nil for package not in ensure_installed", function()
      config.ensure_installed = { "stylua" }
      assert.is_nil(config.get_pinned_version("lua-language-server"))
    end)
  end)

  describe("get_locked_version", function()
    it("should return pinned version first", function()
      config.ensure_installed = {
        { "lua-language-server", version = "3.6.0" },
      }
      -- Even if cache has different version
      cache.set({ ["lua-language-server"] = "3.5.0" })

      assert.are.equal("3.6.0", config.get_locked_version("lua-language-server"))
    end)

    it("should return cached version when not pinned", function()
      config.ensure_installed = { "lua-language-server" }
      cache.set({ ["lua-language-server"] = "3.5.0" })

      assert.are.equal("3.5.0", config.get_locked_version("lua-language-server"))
    end)

    it("should return nil when not found", function()
      config.ensure_installed = {}
      cache.set({})

      assert.is_nil(config.get_locked_version("nonexistent"))
    end)

    it("should fall back to sync read when cache not loaded", function()
      config.lockfile_path = lockfile_path
      config.ensure_installed = {}
      -- Don't load cache
      test_helpers.write_file(lockfile_path, '{"package": "1.0.0"}')

      local version = config.get_locked_version("package")
      assert.are.equal("1.0.0", version)
    end)
  end)
end)
