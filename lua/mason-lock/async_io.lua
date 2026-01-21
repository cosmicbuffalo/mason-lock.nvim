-- Async file I/O module using vim.uv (libuv)
local M = {}

local uv = vim.uv or vim.loop

--- Read a file asynchronously
---@param path string The file path to read
---@param callback fun(err: string|nil, data: string|nil) Called with error or data
function M.read_file(path, callback)
  uv.fs_open(path, "r", 438, function(open_err, fd)
    if open_err then
      vim.schedule(function()
        callback(open_err, nil)
      end)
      return
    end

    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err then
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          callback(stat_err, nil)
        end)
        return
      end

      uv.fs_read(fd, stat.size, 0, function(read_err, data)
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          if read_err then
            callback(read_err, nil)
          else
            callback(nil, data)
          end
        end)
      end)
    end)
  end)
end

--- Write a file asynchronously
---@param path string The file path to write
---@param content string The content to write
---@param callback fun(err: string|nil) Called with error or nil on success
function M.write_file(path, content, callback)
  -- Use 438 (0666) for permissions, will be modified by umask
  uv.fs_open(path, "w", 438, function(open_err, fd)
    if open_err then
      vim.schedule(function()
        callback(open_err)
      end)
      return
    end

    uv.fs_write(fd, content, 0, function(write_err, _)
      uv.fs_close(fd, function() end)
      vim.schedule(function()
        if write_err then
          callback(write_err)
        else
          callback(nil)
        end
      end)
    end)
  end)
end

--- Check if a file exists asynchronously
---@param path string The file path to check
---@param callback fun(exists: boolean) Called with true if file exists
function M.file_exists(path, callback)
  uv.fs_stat(path, function(err, stat)
    vim.schedule(function()
      callback(err == nil and stat ~= nil)
    end)
  end)
end

return M
