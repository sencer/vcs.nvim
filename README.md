# vcs.nvim

A generic, extensible Version Control System (VCS) utility for Neovim. It automatically detects active VCS repositories and loads modified/untracked files into buffers on startup.

It is designed to be VCS-agnostic, providing a backbone that allows registering custom providers.

## Features

- **Auto-detection**: Automatically detects active VCS for the current working directory.
- **Async Loading**: Asynchronously queries the VCS for modified files and loads them.
- **Safety**: Checks for Vim swap files asynchronously before loading to prevent blocking dialogs.
- **Extensible**: Easy to register new VCS providers.

## Default Providers

- **Git**: Detects `.git` and uses `git status --porcelain`.
- **Hg**: Detects `.hg` and uses `hg status`.

## Installation

Add it to your Neovim package path. For example, if using Vim packages:

```bash
git submodule add git@github.com:sencer/vcs.nvim.git nvim/pack/sencer/start/vcs.nvim
```

## Usage

By default, the plugin will automatically attempt to load modified files if you start Neovim with no arguments in a recognized repository.

### API

#### Register a new provider

You can register custom providers (e.g. for custom or proprietary VCS):

```lua
local vcs = require("vcs")

local my_vcs = {
  detect = function(dir)
    -- Return true if this VCS is active for 'dir'
    return vim.fn.finddir(".myvcs", dir .. ";") ~= ""
  end,
  get_modified_files = function(dir, callback)
    -- Run command asynchronously and call callback with a list of absolute paths
    local async = require("sencer.async")
    async.run_shell({
      command = "myvcs status -n",
      on_exit = function(obj)
        if obj.code == 0 then
          local files = {}
          for _, line in ipairs(vim.split(obj.stdout or "", "\n")) do
            if line ~= "" then
              table.insert(files, dir .. "/" .. line)
            end
          end
          callback(files)
        else
          callback({})
        end
      end
    })
  end
}

vcs.register("my_vcs", my_vcs)
```

#### Manually trigger loading

```lua
require("vcs").load_modified_files(vim.fn.getcwd())
```

## Dependencies

- `sencer/async.nvim`: Used for asynchronous command execution.
