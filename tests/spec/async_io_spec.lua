describe("async_io", function()
  local async_io = require("mason-lock.async_io")

  local temp_dir
  local test_file

  before_each(function()
    temp_dir = test_helpers.create_temp_dir()
    test_file = temp_dir .. "/test.txt"
  end)

  after_each(function()
    test_helpers.cleanup_temp_dir(temp_dir)
  end)

  describe("read_file", function()
    it("should read file content asynchronously", function()
      local expected_content = "Hello, World!"
      test_helpers.write_file(test_file, expected_content)

      local result = nil
      local err = nil
      local done = false

      async_io.read_file(test_file, function(e, data)
        err = e
        result = data
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)
      assert.are.equal(expected_content, result)
    end)

    it("should return error for non-existent file", function()
      local result = nil
      local err = nil
      local done = false

      async_io.read_file(temp_dir .. "/nonexistent.txt", function(e, data)
        err = e
        result = data
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_not_nil(err)
      assert.is_nil(result)
    end)

    it("should handle empty files", function()
      test_helpers.write_file(test_file, "")

      local result = nil
      local err = nil
      local done = false

      async_io.read_file(test_file, function(e, data)
        err = e
        result = data
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)
      assert.are.equal("", result)
    end)
  end)

  describe("write_file", function()
    it("should write content to file asynchronously", function()
      local content = "Test content"
      local err = nil
      local done = false

      async_io.write_file(test_file, content, function(e)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)

      local actual = test_helpers.read_file(test_file)
      assert.are.equal(content, actual)
    end)

    it("should overwrite existing file", function()
      test_helpers.write_file(test_file, "original content")
      local new_content = "new content"
      local err = nil
      local done = false

      async_io.write_file(test_file, new_content, function(e)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)

      local actual = test_helpers.read_file(test_file)
      assert.are.equal(new_content, actual)
    end)

    it("should handle JSON content", function()
      local json_content = '{"package": "1.0.0"}'
      local err = nil
      local done = false

      async_io.write_file(test_file, json_content, function(e)
        err = e
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_nil(err)

      local actual = test_helpers.read_file(test_file)
      assert.are.equal(json_content, actual)
    end)
  end)

  describe("file_exists", function()
    it("should return true for existing file", function()
      test_helpers.write_file(test_file, "content")

      local result = nil
      local done = false

      async_io.file_exists(test_file, function(exists)
        result = exists
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_true(result)
    end)

    it("should return false for non-existent file", function()
      local result = nil
      local done = false

      async_io.file_exists(temp_dir .. "/nonexistent.txt", function(exists)
        result = exists
        done = true
      end)

      assert.is_true(test_helpers.wait_for(function()
        return done
      end, 1000))
      assert.is_false(result)
    end)
  end)
end)
