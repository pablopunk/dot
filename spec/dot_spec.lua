local lfs = require "lfs"
local pl_dir = require "pl.dir"
local pl_file = require "pl.file"
local pl_path = require "pl.path"

local function path_exists(path)
  local result = pl_path.exists(path)
  return result and result == path
end

describe("dot.lua", function()
  local tmp_dir
  local dotfiles_dir
  local home_dir
  local modules_dir
  local profiles_dir
  local dot_executable

  -- Function to check if a path is a symbolic link
  local function is_link(path)
    local attr = lfs.symlinkattributes(path)
    return attr and attr.mode == "link"
  end

  -- Function to run dot.lua with given arguments
  local function run_dot(args)
    args = args or ""
    local cmd = string.format("cd %q && HOME=%q lua %q %s --mock-brew", dotfiles_dir, home_dir, dot_executable, args)
    return os.execute(cmd)
  end

  -- Function to set up a module with given name and content
  local function setup_module(name, content)
    local module_dir = pl_path.join(modules_dir, name)
    pl_dir.makepath(module_dir)
    local init_lua = pl_path.join(module_dir, "init.lua")
    pl_file.write(init_lua, content)
  end

  -- Function to set up a profile with given name and content
  local function setup_profile(name, content)
    local profile_lua = pl_path.join(profiles_dir, name .. ".lua")
    pl_file.write(profile_lua, content)
  end

  before_each(function()
    -- Create a unique temporary directory using mktemp -d
    local handle = io.popen "mktemp -d"
    tmp_dir = handle:read "*a"
    handle:close()
    tmp_dir = tmp_dir:gsub("%s+$", "") -- Remove any trailing whitespace

    -- Define directory paths
    dotfiles_dir = pl_path.join(tmp_dir, "dotfiles")
    home_dir = pl_path.join(tmp_dir, "home")
    modules_dir = pl_path.join(dotfiles_dir, "modules")
    profiles_dir = pl_path.join(dotfiles_dir, "profiles")
    dot_executable = pl_path.join(dotfiles_dir, "dot.lua")

    -- Create necessary directories
    pl_dir.makepath(dotfiles_dir)
    pl_dir.makepath(home_dir)
    pl_dir.makepath(modules_dir)
    pl_dir.makepath(profiles_dir)

    -- Copy dot.lua to dotfiles_dir
    os.execute(string.format("cp %q %q", "./dot.lua", dot_executable))
    -- Ensure dot.lua is executable
    os.execute(string.format("chmod +x %q", dot_executable))
  end)

  after_each(function()
    -- Remove the temporary directory
    if tmp_dir and path_exists(tmp_dir) then
      pl_dir.rmtree(tmp_dir)
    end
  end)

  it("should install all modules", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
    apt = "sudo apt install -y neovim",
    dnf = "sudo dnf install -y neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Set up 'zsh' module with new structure
    setup_module(
      "zsh",
      [[
return {
  install = {
    brew = "brew install zsh",
    apt = "sudo apt install -y zsh",
    bash = "curl -fsSL https://z.sh | bash -s",
  },
  link = {
    ["./zshrc"] = "$HOME/.zshrc",
  }
}
]]
    )

    -- Create config directories and files
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(modules_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")

    -- Run dot.lua without arguments to install all modules
    assert.is_true(run_dot())

    -- Check if symlinks are created
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_true(is_link(zshrc), "Expected symlink for zshrc")
  end)

  it("should install a specific module", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
    apt = "sudo apt install -y neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Create config directories and files
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")

    -- Run dot.lua for 'neovim' module
    assert.is_true(run_dot "neovim")

    -- Check if symlink is created for nvim and no symlink for zshrc
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_false(path_exists(zshrc), "Did not expect symlink for zshrc")
  end)

  it("should install a profile", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
    apt = "sudo apt install -y neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Set up 'zsh' module with new structure
    setup_module(
      "zsh",
      [[
return {
  install = {
    brew = "brew install zsh",
    apt = "sudo apt install -y zsh",
  },
  link = {
    ["./zshrc"] = "$HOME/.zshrc",
  }
}
]]
    )

    -- Create 'work' profile
    setup_profile(
      "work",
      [[
return {
  modules = {
    "*"
  }
}
]]
    )

    -- Create config directories and files
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(modules_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")

    -- Run dot.lua with 'work' profile
    assert.is_true(run_dot "work")

    -- Check if symlinks are created for both modules
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_true(is_link(zshrc), "Expected symlink for zshrc")
  end)

  it("should handle exclusions in profiles", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Set up 'zsh' module with new structure
    setup_module(
      "zsh",
      [[
return {
  install = {
    brew = "brew install zsh",
  },
  link = {
    ["./zshrc"] = "$HOME/.zshrc",
  }
}
]]
    )

    -- Set up 'apps/work' module with new structure
    setup_module(
      "apps/work",
      [[
return {
  install = {
    brew = "brew install work-app",
  },
  link = {
    ["./config"] = "$HOME/.config/work-app",
  }
}
]]
    )

    -- Create 'personal' profile with exclusion
    setup_profile(
      "personal",
      [[
return {
  modules = {
    "*",
    "!apps/work"
  }
}
]]
    )

    -- Create config directories and files
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(modules_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")
    pl_dir.makepath(pl_path.join(modules_dir, "apps", "work", "config"))
    pl_file.write(pl_path.join(modules_dir, "apps", "work", "config", "settings.json"), '{"key": "value"}')

    -- Run dot.lua with 'personal' profile
    assert.is_true(run_dot "personal")

    -- Check if symlinks are created for neovim and zsh, but not for apps/work
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    local work_app_config = pl_path.join(home_dir, ".config", "work-app")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_true(is_link(zshrc), "Expected symlink for zshrc")
    assert.is_false(path_exists(work_app_config), "Did not expect symlink for work-app config")
  end)

  it("should replace existing configs in force mode", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Create existing config
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    pl_dir.makepath(pl_path.join(home_dir, ".config"))
    pl_dir.makepath(nvim_config)
    pl_file.write(pl_path.join(nvim_config, "init.vim"), "old config")

    -- Create module config
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")

    -- Run dot.lua with force flag
    assert.is_true(run_dot "-f neovim")

    -- Check if symlink is created
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")

    -- Check if backup exists
    local backup_exists = false
    for file in lfs.dir(pl_path.join(home_dir, ".config")) do
      if file:match "^nvim.before%-dot" then
        backup_exists = true
        break
      end
    end
    assert.is_true(backup_exists, "Backup file not found")
  end)

  it("should unlink configs with --unlink", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Create module config
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")

    -- Run dot.lua to install 'neovim'
    assert.is_true(run_dot "neovim")

    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")

    -- Run dot.lua with --unlink option for 'neovim'
    assert.is_true(run_dot "--unlink neovim")

    -- Check if symlink is removed and config is copied
    assert.is_false(is_link(nvim_config), "Expected symlink for nvim_config to be removed")
    assert.is_true(path_exists(nvim_config), "Expected nvim_config to exist as a regular directory")

    -- Verify the content of init.vim
    local init_vim_path = pl_path.join(nvim_config, "init.vim")
    assert.is_true(pl_path.isfile(init_vim_path), "init.vim does not exist after unlinking")
    local content = pl_file.read(init_vim_path)
    assert.are.equal("set number", content)
  end)

  it("should purge modules with --purge", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Create module config
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")

    -- Run dot.lua to install 'neovim'
    assert.is_true(run_dot "neovim")

    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")

    -- Run dot.lua with --purge option for 'neovim'
    assert.is_true(run_dot "--purge neovim")

    -- Check if symlink is removed
    assert.is_false(path_exists(nvim_config), "Expected nvim_config to be removed after purge")
  end)

  it("should run new hook system", function()
    -- Set up 'dummy_app' module with new hooks using absolute paths
    setup_module(
      "dummy_app",
      string.format(
        [[
return {
  install = {
    bash = "touch %s/.install_ran",
  },
  link = {
    ["./config"] = "$HOME/.config/dummy_app",
  },
  postinstall = "touch %s/.hooks_postinstall_ran",
  postlink = "touch %s/.hooks_postlink_ran",
}
]],
        home_dir,
        home_dir,
        home_dir
      )
    )

    -- Create module config
    pl_dir.makepath(pl_path.join(modules_dir, "dummy_app", "config"))
    pl_file.write(pl_path.join(modules_dir, "dummy_app", "config", "config.txt"), "dummy config")

    -- Run dot.lua to install 'dummy_app'
    assert.is_true(run_dot "dummy_app")

    -- Check if postinstall hook ran (should run because install happened)
    local hook_postinstall = pl_path.join(home_dir, ".hooks_postinstall_ran")
    assert.is_true(path_exists(hook_postinstall), "Post-install hook did not run")

    -- Check if postlink hook ran (should run because link happened)
    local hook_postlink = pl_path.join(home_dir, ".hooks_postlink_ran")
    assert.is_true(path_exists(hook_postlink), "Post-link hook did not run")

    -- Check if install command ran
    local install_ran = pl_path.join(home_dir, ".install_ran")
    assert.is_true(path_exists(install_ran), "Install command did not run")
  end)

  it("should handle multiple links in a module", function()
    -- Set up 'multi_link' module with multiple links
    setup_module(
      "multi_link",
      [[
return {
  link = {
    ["./config/settings.json"] = "$HOME/settings.json",
    ["./config/keybindings.json"] = "$HOME/keybindings.json",
  }
}
]]
    )

    -- Create config files
    pl_dir.makepath(pl_path.join(modules_dir, "multi_link", "config"))
    pl_file.write(pl_path.join(modules_dir, "multi_link", "config", "settings.json"), [[{ "setting": "value" }]])
    pl_file.write(pl_path.join(modules_dir, "multi_link", "config", "keybindings.json"), [[{ "key": "binding" }]])

    -- Run dot.lua to install 'multi_link'
    assert.is_true(run_dot "multi_link")

    -- Check if symlinks are created
    local settings = pl_path.join(home_dir, "settings.json")
    local keybindings = pl_path.join(home_dir, "keybindings.json")
    assert.is_true(is_link(settings), "Expected symlink for settings.json")
    assert.is_true(is_link(keybindings), "Expected symlink for keybindings.json")
  end)

  it("should support directory linking", function()
    -- Set up module that links entire directories
    setup_module(
      "dir_link",
      [[
return {
  link = {
    ["./zshrc.d"] = "$HOME/.zshrc.d",
    ["./config"] = "$HOME/.config/myapp",
  }
}
]]
    )

    -- Create directory structures
    pl_dir.makepath(pl_path.join(modules_dir, "dir_link", "zshrc.d"))
    pl_file.write(pl_path.join(modules_dir, "dir_link", "zshrc.d", "aliases.zsh"), "alias ll='ls -la'")
    pl_file.write(pl_path.join(modules_dir, "dir_link", "zshrc.d", "exports.zsh"), "export EDITOR=nvim")
    
    pl_dir.makepath(pl_path.join(modules_dir, "dir_link", "config"))
    pl_file.write(pl_path.join(modules_dir, "dir_link", "config", "config.json"), '{"theme": "dark"}')

    -- Run dot.lua to install 'dir_link'
    assert.is_true(run_dot "dir_link")

    -- Check if directory symlinks are created
    local zshrc_d = pl_path.join(home_dir, ".zshrc.d")
    local config_dir = pl_path.join(home_dir, ".config", "myapp")
    assert.is_true(is_link(zshrc_d), "Expected symlink for .zshrc.d directory")
    assert.is_true(is_link(config_dir), "Expected symlink for config directory")
  end)

  it("should display help message with -h option", function()
    -- Run dot.lua with -h option
    local cmd = string.format("cd %q && HOME=%q lua %q -h", dotfiles_dir, home_dir, dot_executable)
    local handle = io.popen(cmd)
    local output = handle:read("*a")
    handle:close()

    -- Check if the output contains the expected start of the help message
    local expected_start = "Usage: dot"
    assert.is_true(output:find(expected_start, 1, true) ~= nil, "Help message not displayed correctly")
  end)

  it("should handle OS-specific modules", function()
    -- Set up a module that only works on the current OS
    local current_os = io.popen("uname"):read("*l") -- Get the current OS
    local is_macos = current_os == "Darwin"
    local is_linux = current_os == "Linux"
    
    -- Set up 'os_specific' module for the current OS
    setup_module(
      "os_specific_current",
      [[
return {
  os = { "]] .. (is_macos and "darwin" or "linux") .. [[" },
  link = {
    ["./config"] = "$HOME/.config/os_specific_current",
  }
}
]]
    )
    
    -- Set up a module for the other OS
    setup_module(
      "os_specific_other",
      [[
return {
  os = { "]] .. (is_macos and "linux" or "darwin") .. [[" },
  link = {
    ["./config"] = "$HOME/.config/os_specific_other",
  }
}
]]
    )
    
    -- Create config directories and files
    pl_dir.makepath(pl_path.join(modules_dir, "os_specific_current", "config"))
    pl_file.write(pl_path.join(modules_dir, "os_specific_current", "config", "config.txt"), "current os config")
    
    pl_dir.makepath(pl_path.join(modules_dir, "os_specific_other", "config"))
    pl_file.write(pl_path.join(modules_dir, "os_specific_other", "config", "config.txt"), "other os config")
    
    -- Run dot.lua without arguments to install all modules
    assert.is_true(run_dot())
    
    -- Check if the current OS module is installed and the other OS module is skipped
    local current_config = pl_path.join(home_dir, ".config", "os_specific_current")
    local other_config = pl_path.join(home_dir, ".config", "os_specific_other")
    
    assert.is_true(is_link(current_config), "Expected symlink for current OS module")
    assert.is_false(path_exists(other_config), "Did not expect symlink for other OS module")
  end)

  it("should support fuzzy module matching", function()
    -- Set up nested module structure
    setup_module(
      "ricing/hyprland",
      [[
return {
  install = {
    apt = "sudo apt install -y hyprland",
  },
  link = {
    ["./config"] = "$HOME/.config/hypr",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "ricing", "hyprland", "config"))
    pl_file.write(pl_path.join(modules_dir, "ricing", "hyprland", "config", "hyprland.conf"), "# Hyprland config")

    -- Test fuzzy matching: 'hypr' should match 'ricing/hyprland'
    assert.is_true(run_dot "hypr")

    -- Check if symlink is created
    local hypr_config = pl_path.join(home_dir, ".config", "hypr")
    assert.is_true(is_link(hypr_config), "Expected symlink for hypr config via fuzzy match")
  end)

  it("should handle command detection for install", function()
    -- Set up module with multiple install options
    setup_module(
      "test_detection",
      [[
return {
  install = {
    nonexistent_cmd = "nonexistent_cmd install test",
    bash = "echo 'bash install worked' > ]] .. home_dir .. [[/install_result.txt",
  },
  link = {
    ["./config"] = "$HOME/.config/test_detection",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_detection", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_detection", "config", "test.conf"), "test config")

    -- Run dot.lua - should use bash since nonexistent_cmd doesn't exist
    assert.is_true(run_dot "test_detection")

    -- Check if bash command was executed
    local install_result = pl_path.join(home_dir, "install_result.txt")
    assert.is_true(path_exists(install_result), "Expected bash install command to run")
    
    local content = pl_file.read(install_result)
    assert.are.equal("bash install worked", content:match("^%s*(.-)%s*$"))
  end)

  it("should run postinstall only when install happens", function()
    -- Set up module with install that does nothing the second time
    setup_module(
      "install_once",
      string.format(
        [[
return {
  install = {
    bash = "test ! -f %s/.already_installed && touch %s/.already_installed || exit 0",
  },
  link = {
    ["./config"] = "$HOME/.config/install_once",
  },
  postinstall = "touch %s/.postinstall_ran",
}
]],
        home_dir, home_dir, home_dir
      )
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "install_once", "config"))
    pl_file.write(pl_path.join(modules_dir, "install_once", "config", "test.conf"), "test config")

    -- First run - should run postinstall
    assert.is_true(run_dot "install_once")
    
    local postinstall_marker = pl_path.join(home_dir, ".postinstall_ran")
    assert.is_true(path_exists(postinstall_marker), "Expected postinstall to run on first install")

    -- Remove postinstall marker
    os.remove(postinstall_marker)

    -- Second run - should NOT run postinstall since install already happened
    assert.is_true(run_dot "install_once")
    assert.is_false(path_exists(postinstall_marker), "Did not expect postinstall to run on second install")
  end)

  it("should save the last used profile", function()
    -- Set up 'neovim' module with new structure
    setup_module(
      "neovim",
      [[
return {
  install = {
    brew = "brew install neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Create config directories and files for 'neovim'
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")

    -- Set up a dummy profile
    setup_profile(
      "test_profile",
      [[
return {
  modules = {
    "neovim"
  }
}
]]
    )

    -- Run dot.lua with the 'test_profile' profile
    assert.is_true(run_dot "test_profile")

    -- Check if the .dot file contains the correct profile name
    local dot_file_path = pl_path.join(dotfiles_dir, ".dot")
    assert.is_true(pl_path.isfile(dot_file_path), ".dot file not found")

    local content = pl_file.read(dot_file_path)
    assert.are.equal("test_profile", content:match("^%s*(.-)%s*$"), "Profile name in .dot file is incorrect")
  end)
end)
