# mason-lock.nvim

Provides lockfile functionality to [mason.nvim](https://github.com/williamboman/mason.nvim), with automatic version management and pinning support.

## How It Works

mason-lock.nvim intercepts package installations by monkey-patching `Package:install()`. When any package is being installed (via mason-lspconfig, Mason UI, or manually):

1. **For pinned packages**: Forces installation of the pinned version
2. **For packages in lockfile**: Installs the version specified in the lockfile
3. **For new packages**: Installs the latest version and adds it to the lockfile

This happens transparently - you don't need to change how you use Mason.

## Installation

### lazy.nvim

```lua
{
  "cosmicbuffalo/mason-lock.nvim",
  opts = {
    lockfile_path = vim.fn.stdpath("config") .. "/mason-lock.json", -- default
    lockfile_scope = "locked_packages", -- default: "locked_packages", or "all"
    locked_packages = {
      "shfmt",  -- unpinned: uses lockfile version or latest
      { "tree-sitter-cli", version = "v0.25.10" },  -- pinned
    },
    silent = false, -- default: suppress automatic progress notifications
  },
}
```

## Configuration

### `lockfile_path`

**Type**: `string`
**Default**: `vim.fn.stdpath("config") .. "/mason-lock.json"`

Path to the lockfile where package versions are stored.

### `lockfile_scope`

**Type**: `"locked_packages" | "all"`
**Default**: `"locked_packages"`

Controls which packages are written to the lockfile:

- `"locked_packages"`: Only packages listed in `locked_packages` are written to the lockfile
- `"all"`: All installed packages are written to the lockfile

### `locked_packages`

**Type**: `(string | { [1]: string, version: string })[]`
**Default**: `{}`

List of packages to manage with mason-lock. Each entry can be:

- **String format**: `"package-name"` - Package will use lockfile version or install latest
- **Table format**: `{ "package-name", version = "x.y.z" }` - Package is pinned to specific version

**Example**:

```lua
locked_packages = {
  "shfmt",  -- unpinned: uses lockfile version or latest
  { "tree-sitter-cli", version = "v0.25.10" },  -- pinned
}
```

### `silent`

**Type**: `boolean`
**Default**: `false`

When enabled, suppresses fidget.nvim progress notifications for automatic lockfile writes (triggered by package install/uninstall events). User commands (`:MasonLock`, `:MasonLockRestore`) will still show progress notifications. Errors are always displayed regardless of this setting.

## Usage

### Setting Up Automatic Installation

Mason can be configured like so using mason-lock's `locked_packages`, packages will be automatically installed on Neovim startup if they're missing, and mason-lock will handle ensuring that pinned or locked versions are used:

```lua
{
  "mason.nvim",
  dependencies = {
    {
      "cosmicbuffalo/mason-lock.nvim",
      opts = {
        lockfile_scope = "locked_packages",
        locked_packages = {
          "stylua",
          "shfmt",
          { "tree-sitter-cli", version = "v0.25.10" },
        },
      },
    },
  },
  config = function()
    require("mason").setup()
    local ml = require("mason-lock")
    local mr = require("mason-registry")

    -- Auto-install packages from locked_packages
    mr.refresh(function()
      for _, tool in ipairs(ml.locked_packages) do
        local tool_name = type(tool) == "table" and tool[1] or tool
        local p = mr.get_package(tool_name)
        if not p:is_installed() and not p:is_installing() then
          p:install()
        end
      end
    end)
  end,
}
```


### Lockfile Updates

The lockfile is automatically updated when:
- A package is installed
- A package is updated
- A package is uninstalled

The lockfile will only include packages listed in `locked_packages` when the `lockfile_scope` is set to the default setting. To see all mason-installed packages in the lockfile, set `lockfile_scope` to `"all"`.

### Manual Commands

#### `:MasonLock`

Manually write current package versions to the lockfile.

#### `:MasonLockRestore`

Re-install all packages with versions specified in the lockfile

## Example Lockfile

```json
{
  "bash-language-server": "5.6.0",
  "gopls": "v0.15.0",
  "lua-language-server": "3.15.0",
  "shfmt": "v3.12.0",
  "stylua": "v2.3.1",
  "tree-sitter-cli": "v0.25.10"
}
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT
