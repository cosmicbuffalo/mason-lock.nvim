# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-01-21

Major refactor introducing a fully asynchronous, non-blocking architecture with fidget.nvim integration for visual progress feedback.

### Added
- **Non-blocking async I/O**: All file operations now use `vim.uv`/libuv via new `async_io.lua` module
  - Asynchronous file reading, writing, and existence checks
  - No more blocking `vim.wait()` calls that freeze the UI
- **In-memory lockfile cache**: New `cache.lua` module for fast lockfile data access
  - Lockfile is preloaded on startup for instant version lookups
  - Cache is automatically updated after lockfile writes
  - Supports queued callbacks during initial load
- **Progress notifications with fidget.nvim**: New `notify.lua` module with optional fidget.nvim integration
  - Visual progress indicators for lockfile write and restore operations
  - Shows real-time progress during package restoration (e.g., "Installing 3/10: lua-language-server")
  - Graceful fallback to `vim.notify` when fidget.nvim is not installed
- **Debounced lockfile writes**: New `schedule_write()` function prevents rapid successive writes
  - 500ms debounce delay coalesces multiple install/uninstall events into a single write
- **Comprehensive test suite**: Full test coverage with plenary.nvim
  - Tests for async_io, cache, config, lockfile, and notify modules
  - Mock mason-registry for isolated unit testing
  - Test helpers for temp files, notification capture, and async waiting
- **CI/CD pipeline**: GitHub Actions workflow for automated testing
  - Tests against Neovim stable and nightly
  - StyLua formatting checks
  - Selene linting
- **Developer tooling**: Makefile with common development tasks
  - `make test` - Run test suite
  - `make format` - Format code with StyLua
  - `make lint` - Lint with Selene
  - `make check` - Run all checks

### Changed
- **Lockfile operations are now async**: `lockfile.write()` and `lockfile.restore()` accept callbacks
  - Registry event listeners now use `schedule_write()` for debounced writes
- **Version lookup uses cache**: `config.get_locked_version()` reads from in-memory cache instead of disk
- **Improved restore operation**: Package installation happens concurrently with progress tracking
  - Failed packages are tracked and reported at the end
  - No more blocking `vim.wait()` with 60-second timeout
- **Code formatting**: Converted from tabs to 2-space indentation throughout
