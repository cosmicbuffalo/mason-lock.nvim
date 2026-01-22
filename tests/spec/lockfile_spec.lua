describe("lockfile", function()
  local lockfile
  local config
  local cache

  local temp_dir
  local lockfile_path

  before_each(function()
    -- Reset modules
    package.loaded["mason-lock.lockfile"] = nil
    package.loaded["mason-lock.config"] = nil
    package.loaded["mason-lock.cache"] = nil
    package.loaded["mason-lock.notify"] = nil

    -- Clear mock registry
    mock_registry._clear()

    temp_dir = test_helpers.create_temp_dir()
    lockfile_path = temp_dir .. "/mason-lock.json"

    config = require("mason-lock.config")
    config.lockfile_path = lockfile_path
    config.lockfile_scope = "all"
    config.locked_packages = {}
    config.preserve_uninstalled = true
    config._restore_in_progress = false

    cache = require("mason-lock.cache")
    lockfile = require("mason-lock.lockfile")
  end)

  after_each(function()
    test_helpers.cleanup_temp_dir(temp_dir)
  end)

  describe("read", function()
    it("should read lockfile asynchronously", function()
      local content = '{"stylua": "0.18.0"}'
      test_helpers.write_file(lockfile_path, content)

      local result = nil
      local err = nil
      local done = false

      lockfile.read(function(e, data)
        err = e
        result = data
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)
      assert.are.equal("0.18.0", result["stylua"])
    end)

    it("should return error for non-existent file", function()
      local err = nil
      local done = false

      lockfile.read(function(e, _data)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_not_nil(err)
    end)
  end)

  describe("write", function()
    it("should write lockfile asynchronously", function()
      mock_registry._add_mock_package("lua-language-server", "3.6.0")

      local err = nil
      local done = false

      lockfile.write(function(e)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)

      local content = test_helpers.read_file(lockfile_path)
      assert.is_not_nil(content)
      assert.is_truthy(string.find(content, "lua%-language%-server"))
    end)

    it("should skip write during restore", function()
      config._restore_in_progress = true
      mock_registry._add_mock_package("package", "1.0.0")

      local done = false
      lockfile.write(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      local content = test_helpers.read_file(lockfile_path)
      assert.is_nil(content)
    end)

    it("should update cache after write", function()
      mock_registry._add_mock_package("package", "2.0.0")

      local done = false
      lockfile.write(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      assert.is_true(cache.is_loaded())
      assert.are.equal("2.0.0", cache.get_version("package"))
    end)
  end)

  describe("schedule_write", function()
    it("should debounce multiple writes", function()
      mock_registry._add_mock_package("package", "1.0.0")

      local call_count = 0
      local original_write = lockfile.write
      lockfile.write = function(callback)
        call_count = call_count + 1
        original_write(callback)
      end

      -- Schedule multiple writes rapidly
      lockfile.schedule_write()
      lockfile.schedule_write()
      lockfile.schedule_write()

      -- Wait for debounce to complete
      vim.wait(700)

      -- Should only have called write once
      assert.are.equal(1, call_count)

      lockfile.write = original_write
    end)
  end)

  describe("preserve_uninstalled", function()
    it("should preserve entries for uninstalled packages by default", function()
      -- Write initial lockfile with a package
      local initial_content = '{"old-package": "1.0.0"}'
      test_helpers.write_file(lockfile_path, initial_content)

      -- Load the cache with existing data
      cache.set({ ["old-package"] = "1.0.0" })

      -- Add a new installed package (old-package is not installed)
      mock_registry._add_mock_package("new-package", "2.0.0")

      local done = false
      lockfile.write(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      local content = test_helpers.read_file(lockfile_path)
      assert.is_truthy(string.find(content, "new%-package"))
      assert.is_truthy(string.find(content, "old%-package"))
    end)

    it("should update version for installed packages while preserving uninstalled", function()
      -- Set up cache with both packages
      cache.set({
        ["installed-pkg"] = "1.0.0",
        ["uninstalled-pkg"] = "2.0.0",
      })

      -- Only installed-pkg is actually installed, with a new version
      mock_registry._add_mock_package("installed-pkg", "1.1.0")

      local done = false
      lockfile.write(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      local content = test_helpers.read_file(lockfile_path)
      -- installed-pkg should have new version
      assert.is_truthy(string.find(content, '"installed%-pkg": "1.1.0"'))
      -- uninstalled-pkg should be preserved with old version
      assert.is_truthy(string.find(content, '"uninstalled%-pkg": "2.0.0"'))
    end)

    it("should not preserve uninstalled when preserve_uninstalled is false", function()
      config.preserve_uninstalled = false

      -- Set up cache with an uninstalled package
      cache.set({ ["old-package"] = "1.0.0" })

      -- Add a new installed package
      mock_registry._add_mock_package("new-package", "2.0.0")

      local done = false
      lockfile.write(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      local content = test_helpers.read_file(lockfile_path)
      assert.is_truthy(string.find(content, "new%-package"))
      assert.is_falsy(string.find(content, "old%-package"))
    end)

    it("should work on first write with no existing lockfile", function()
      -- No existing lockfile or cache
      cache.invalidate()

      mock_registry._add_mock_package("first-package", "1.0.0")

      local done = false
      lockfile.write(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      local content = test_helpers.read_file(lockfile_path)
      assert.is_truthy(string.find(content, "first%-package"))
    end)

    it("should fall back to reading lockfile when cache is not loaded", function()
      -- Write lockfile but don't load cache
      local initial_content = '{"cached-pkg": "1.0.0"}'
      test_helpers.write_file(lockfile_path, initial_content)
      cache.invalidate()

      mock_registry._add_mock_package("new-pkg", "2.0.0")

      local done = false
      lockfile.write(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      local content = test_helpers.read_file(lockfile_path)
      assert.is_truthy(string.find(content, "new%-pkg"))
      assert.is_truthy(string.find(content, "cached%-pkg"))
    end)
  end)

  describe("restore", function()
    it("should restore packages from lockfile", function()
      local content = '{"lua-language-server": "3.6.0"}'
      test_helpers.write_file(lockfile_path, content)

      mock_registry._add_mock_package("lua-language-server", "3.5.0")

      local err = nil
      local done = false

      lockfile.restore(function(e)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 2000))
      assert.is_nil(err)
    end)

    it("should return error for missing lockfile", function()
      local err = nil
      local done = false

      lockfile.restore(function(e)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_not_nil(err)
    end)

    it("should handle empty lockfile", function()
      test_helpers.write_file(lockfile_path, "{}")

      local done = false
      lockfile.restore(function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
    end)
  end)
end)
