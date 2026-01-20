describe("cache", function()
  local cache

  local temp_dir
  local lockfile_path

  before_each(function()
    -- Reload cache module to reset state
    package.loaded["mason-lock.cache"] = nil
    cache = require("mason-lock.cache")

    temp_dir = test_helpers.create_temp_dir()
    lockfile_path = temp_dir .. "/mason-lock.json"
  end)

  after_each(function()
    test_helpers.cleanup_temp_dir(temp_dir)
  end)

  describe("load", function()
    it("should load lockfile into cache", function()
      local lockfile_content = '{"lua-language-server": "3.6.0", "stylua": "0.18.0"}'
      test_helpers.write_file(lockfile_path, lockfile_content)

      local result = nil
      local err = nil
      local done = false

      cache.load(lockfile_path, function(e, data)
        err = e
        result = data
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.are.equal("3.6.0", result["lua-language-server"])
      assert.are.equal("0.18.0", result["stylua"])
    end)

    it("should return error for non-existent file", function()
      local err = nil
      local done = false

      cache.load(lockfile_path, function(e, _data)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_not_nil(err)
    end)

    it("should return error for invalid JSON", function()
      test_helpers.write_file(lockfile_path, "not valid json")

      local err = nil
      local done = false

      cache.load(lockfile_path, function(e, _data)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_not_nil(err)
      assert.is_truthy(string.find(err, "JSON"))
    end)

    it("should queue multiple callbacks during loading", function()
      local lockfile_content = '{"package": "1.0.0"}'
      test_helpers.write_file(lockfile_path, lockfile_content)

      local callback_count = 0
      local done = false

      cache.load(lockfile_path, function()
        callback_count = callback_count + 1
        if callback_count == 3 then
          done = true
        end
      end)

      cache.load(lockfile_path, function()
        callback_count = callback_count + 1
        if callback_count == 3 then
          done = true
        end
      end)

      cache.load(lockfile_path, function()
        callback_count = callback_count + 1
        if callback_count == 3 then
          done = true
        end
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.are.equal(3, callback_count)
    end)
  end)

  describe("get", function()
    it("should return nil when cache not loaded", function()
      assert.is_nil(cache.get())
    end)

    it("should return cached data after load", function()
      local lockfile_content = '{"package": "1.0.0"}'
      test_helpers.write_file(lockfile_path, lockfile_content)

      local done = false
      cache.load(lockfile_path, function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))

      local data = cache.get()
      assert.is_not_nil(data)
      assert.are.equal("1.0.0", data["package"])
    end)
  end)

  describe("is_loaded", function()
    it("should return false initially", function()
      assert.is_false(cache.is_loaded())
    end)

    it("should return true after successful load", function()
      local lockfile_content = '{"package": "1.0.0"}'
      test_helpers.write_file(lockfile_path, lockfile_content)

      local done = false
      cache.load(lockfile_path, function()
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_true(cache.is_loaded())
    end)
  end)

  describe("set", function()
    it("should update cache directly", function()
      local data = { package = "2.0.0" }
      cache.set(data)

      assert.is_true(cache.is_loaded())
      assert.are.equal("2.0.0", cache.get()["package"])
    end)
  end)

  describe("invalidate", function()
    it("should clear cached data", function()
      cache.set({ package = "1.0.0" })
      assert.is_true(cache.is_loaded())

      cache.invalidate()

      assert.is_false(cache.is_loaded())
      assert.is_nil(cache.get())
    end)
  end)

  describe("get_version", function()
    it("should return version for cached package", function()
      cache.set({ ["lua-language-server"] = "3.6.0" })
      assert.are.equal("3.6.0", cache.get_version("lua-language-server"))
    end)

    it("should return nil for non-cached package", function()
      cache.set({ ["lua-language-server"] = "3.6.0" })
      assert.is_nil(cache.get_version("nonexistent"))
    end)

    it("should return nil when cache not loaded", function()
      assert.is_nil(cache.get_version("package"))
    end)
  end)
end)
