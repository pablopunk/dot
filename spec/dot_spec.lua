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
  local bin_dir
  local command_log_file

  -- Function to check if a path is a symbolic link
  local function is_link(path)
    local attr = lfs.symlinkattributes(path)
    return attr and attr.mode == "link"
  end

  -- Function to create a fake command that logs when it's called
  local function create_command(name, exit_code, output)
    exit_code = exit_code or 0
    output = output or ""
    
    local cmd_path = pl_path.join(bin_dir, name)
    local script_content = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: %s $@" >> %q
echo %q
exit %d
]], name, command_log_file, output, exit_code)
    
    pl_file.write(cmd_path, script_content)
    os.execute(string.format("chmod +x %q", cmd_path))
    return cmd_path
  end

  -- Function to create a command that creates a marker file when run
  local function create_marker_command(name, marker_path)
    local cmd_path = pl_path.join(bin_dir, name)
    local script_content = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: %s $@" >> %q
touch %q
echo "Package %s installed successfully"
exit 0
]], name, command_log_file, marker_path, name)
    
    pl_file.write(cmd_path, script_content)
    os.execute(string.format("chmod +x %q", cmd_path))
    return cmd_path
  end

  -- Function to check if a command was executed
  local function was_command_executed(command_name)
    if not pl_path.isfile(command_log_file) then
      return false
    end
    local log_content = pl_file.read(command_log_file)
    return log_content:find("COMMAND_EXECUTED: " .. command_name, 1, true) ~= nil
  end

  -- Function to get command execution count
  local function get_command_execution_count(command_name)
    if not pl_path.isfile(command_log_file) then
      return 0
    end
    local log_content = pl_file.read(command_log_file)
    local count = 0
    for line in log_content:gmatch("[^\n]+") do
      if line:find("COMMAND_EXECUTED: " .. command_name, 1, true) then
        count = count + 1
      end
    end
    return count
  end

  -- Function to run dot.lua with given arguments
  local function run_dot(args)
    args = args or ""
    -- Put our bin_dir first, but keep essential system paths for lua and basic tools
    local cmd = string.format("cd %q && HOME=%q PATH=%q:/usr/bin:/bin lua %q %s", dotfiles_dir, home_dir, bin_dir, dot_executable, args)
    return os.execute(cmd)
  end

  -- Function to set up a module with given name and content
  local function setup_module(name, content)
    local module_dir = pl_path.join(modules_dir, name)
    pl_dir.makepath(module_dir)
    local dot_lua = pl_path.join(module_dir, "dot.lua")
    pl_file.write(dot_lua, content)
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
    bin_dir = pl_path.join(tmp_dir, "bin")
    command_log_file = pl_path.join(tmp_dir, "command_log.txt")

    -- Create necessary directories
    pl_dir.makepath(dotfiles_dir)
    pl_dir.makepath(home_dir)
    pl_dir.makepath(modules_dir)
    pl_dir.makepath(profiles_dir)
    pl_dir.makepath(bin_dir)

    -- Copy dot.lua to dotfiles_dir
    os.execute(string.format("cp %q %q", "./dot.lua", dot_executable))
    -- Ensure dot.lua is executable
    os.execute(string.format("chmod +x %q", dot_executable))
    
    -- Initialize command log file
    pl_file.write(command_log_file, "")
    
    -- Create a smart which command that checks our bin_dir first
    local which_script = string.format([[#!/bin/bash
if [ -f "%s/$1" ]; then
  echo "%s/$1"
  exit 0
else
  exit 1
fi
]], bin_dir, bin_dir)
    pl_file.write(pl_path.join(bin_dir, "which"), which_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "which")))
    
    -- Create essential shell commands that lua might need
    create_command("uname", 0, "Linux")
    create_command("mktemp", 0, tmp_dir .. "/tmpfile")
    create_command("test", 0, "")
    -- Create a functional bash command that can execute scripts
    local bash_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: bash $@" >> %q
/bin/bash "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "bash"), bash_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "bash")))
    
    -- Create commands that actually do filesystem operations
    local mkdir_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: mkdir $@" >> %q
/bin/mkdir "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "mkdir"), mkdir_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "mkdir")))
    
    local ln_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: ln $@" >> %q
/bin/ln "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "ln"), ln_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "ln")))
    
    local echo_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: echo $@" >> %q
/bin/echo "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "echo"), echo_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "echo")))
    
    local touch_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: touch $@" >> %q
/usr/bin/touch "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "touch"), touch_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "touch")))
    
    local cp_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: cp $@" >> %q
/bin/cp "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "cp"), cp_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "cp")))
    
    local rm_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: rm $@" >> %q
/bin/rm "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "rm"), rm_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "rm")))
    
    local mv_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: mv $@" >> %q
/bin/mv "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "mv"), mv_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "mv")))
    
    local find_script = string.format([[#!/bin/bash
echo "COMMAND_EXECUTED: find $@" >> %q
/usr/bin/find "$@"
]], command_log_file)
    pl_file.write(pl_path.join(bin_dir, "find"), find_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "find")))
  end)

  after_each(function()
    -- Remove the temporary directory
    if tmp_dir and path_exists(tmp_dir) then
      pl_dir.rmtree(tmp_dir)
    end
  end)

  it("should install all modules using real commands", function()
    -- Create fake package managers
    create_command("apt", 0, "Package neovim installed successfully")
    create_command("brew", 0, "Package zsh installed successfully")

    -- Set up 'neovim' module that only uses apt
    setup_module(
      "neovim",
      [[
return {
  install = {
    apt = "apt install -y neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Set up 'zsh' module that only uses brew
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

    -- Create config directories and files
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(modules_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")

    -- Run dot.lua without arguments to install all modules
    assert.is_true(run_dot())

    -- Check if commands were actually executed
    assert.is_true(was_command_executed("apt"), "apt command should have been executed")
    assert.is_true(was_command_executed("brew"), "brew command should have been executed")

    -- Check if symlinks are created
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_true(is_link(zshrc), "Expected symlink for zshrc")
  end)

  it("should use the first available package manager", function()
    -- Create both apt and brew commands
    create_command("apt", 0, "Package installed via apt")
    create_command("brew", 0, "Package installed via brew")

    -- Set up module with multiple package managers
    setup_module(
      "test_priority",
      [[
return {
  install = {
    nonexistent = "nonexistent install test-package",
    apt = "apt install -y test-package",
    brew = "brew install test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_priority", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_priority", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_priority")

    -- Check that one of the available commands was executed (since pairs order is not guaranteed)
    local apt_executed = was_command_executed("apt")
    local brew_executed = was_command_executed("brew")
    local nonexistent_executed = was_command_executed("nonexistent")
    
    assert.is_false(nonexistent_executed, "nonexistent should NOT have been executed")
    assert.is_true(apt_executed or brew_executed, "either apt or brew should have been executed")
    assert.is_false(apt_executed and brew_executed, "only one package manager should be executed")
  end)

  it("should use fallback commands when preferred is not available", function()
    -- Only create brew command (not apt)
    create_command("brew", 0, "Package installed via brew")

    -- Set up module that prefers apt but falls back to brew
    setup_module(
      "test_fallback",
      [[
return {
  install = {
    apt = "apt install -y test-package",
    brew = "brew install test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_fallback", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_fallback", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_fallback")

    -- Check that brew was used as fallback
    assert.is_false(was_command_executed("apt"), "apt should NOT have been executed (doesn't exist)")
    assert.is_true(was_command_executed("brew"), "brew should have been executed as fallback")
  end)

  it("should handle custom package managers", function()
    -- Create a custom package manager
    create_command("pacman", 0, "Package installed via pacman")

    -- Set up module with custom package manager
    setup_module(
      "test_custom",
      [[
return {
  install = {
    pacman = "pacman -S test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_custom", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_custom", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_custom")

    -- Check that pacman was executed
    assert.is_true(was_command_executed("pacman"), "pacman should have been executed")
  end)

  it("should handle bash commands", function()
    -- Set up module with bash installation that calls touch (which we can track)
    setup_module(
      "test_bash",
      string.format([[
return {
  install = {
    bash = "touch %s/bash_install_marker.txt",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]], home_dir)
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_bash", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_bash", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_bash")

    -- Check that touch was executed (since the bash command actually calls touch)
    assert.is_true(was_command_executed("touch"), "touch should have been executed as part of the bash command")
    
    -- Check that the marker file was created (this proves the command worked)
    local marker_file = pl_path.join(home_dir, "bash_install_marker.txt")
    assert.is_true(path_exists(marker_file), "Bash command should have created marker file")
  end)

  it("should handle command failures gracefully", function()
    -- Create a command that fails
    create_command("failing_cmd", 1, "Installation failed")

    -- Set up module with failing command
    setup_module(
      "test_failure",
      [[
return {
  install = {
    failing_cmd = "failing_cmd install test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_failure", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_failure", "config", "test.conf"), "test config")

    -- Run dot.lua (should complete despite install failure)
    assert.is_true(run_dot "test_failure")

    -- Check that the failing command was attempted
    assert.is_true(was_command_executed("failing_cmd"), "failing_cmd should have been executed")

    -- Links should still be created despite install failure
    local test_config = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(test_config), "Expected symlink despite install failure")
  end)

  it("should run postinstall hooks when installation happens", function()
    -- Create package manager
    local marker_file = pl_path.join(home_dir, "package_installed.marker")
    create_marker_command("apt", marker_file)

    -- Set up module with postinstall hook
    setup_module(
      "test_hooks",
      string.format([[
return {
  install = {
    apt = "apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  },
  postinstall = "touch %s/postinstall_executed.marker",
}
]], home_dir)
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_hooks", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_hooks", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_hooks")

    -- Check that install happened
    assert.is_true(was_command_executed("apt"), "apt should have been executed")
    assert.is_true(path_exists(marker_file), "Package should have been installed")

    -- Check that postinstall hook ran
    local postinstall_marker = pl_path.join(home_dir, "postinstall_executed.marker")
    assert.is_true(path_exists(postinstall_marker), "postinstall hook should have executed")
  end)

  it("should not run postinstall when no installation happens", function()
    -- Set up module without any install commands
    setup_module(
      "test_no_install",
      string.format([[
return {
  link = {
    ["./config"] = "$HOME/.config/test",
  },
  postinstall = "touch %s/postinstall_executed.marker",
}
]], home_dir)
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_no_install", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_no_install", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_no_install")

    -- Check that no postinstall hook ran
    local postinstall_marker = pl_path.join(home_dir, "postinstall_executed.marker")
    assert.is_false(path_exists(postinstall_marker), "postinstall hook should NOT have executed")
  end)

  it("should run install commands on every run (realistic behavior)", function()
    -- Create package manager that succeeds
    create_command("apt", 0, "Package installed successfully")

    -- Set up module
    setup_module(
      "test_repeated",
      [[
return {
  install = {
    apt = "apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "test_repeated", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_repeated", "config", "test.conf"), "test config")

    -- Run dot.lua twice
    assert.is_true(run_dot "test_repeated")
    assert.is_true(run_dot "test_repeated")

    -- Check that apt was executed both times (realistic behavior - package managers handle idempotency)
    assert.are.equal(2, get_command_execution_count("apt"), "apt should be executed on every run")
  end)

  it("should handle profiles correctly", function()
    -- Create package managers
    create_command("apt", 0, "Package installed via apt")
    create_command("brew", 0, "Package installed via brew")

    -- Set up multiple modules
    setup_module(
      "neovim",
      [[
return {
  install = {
    apt = "apt install -y neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

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

    -- Create work profile that only includes neovim
    setup_profile(
      "work",
      [[
return {
  modules = {
    "neovim"
  }
}
]]
    )

    -- Create configs
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(modules_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")

    -- Run with work profile
    assert.is_true(run_dot "work")

    -- Check that only apt was executed (neovim), not brew (zsh)
    assert.is_true(was_command_executed("apt"), "apt should have been executed for neovim")
    assert.is_false(was_command_executed("brew"), "brew should NOT have been executed (zsh not in profile)")

    -- Check that only neovim symlink was created
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_false(path_exists(zshrc), "zshrc should not exist (not in profile)")
  end)

  it("should save and use last profile", function()
    -- Create package manager
    create_command("apt", 0, "Package installed via apt")

    -- Set up module
    setup_module(
      "neovim",
      [[
return {
  install = {
    apt = "apt install -y neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Create test profile
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

    -- Create config
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")

    -- Run with profile to save it
    assert.is_true(run_dot "test_profile")

    -- Clear command log
    pl_file.write(command_log_file, "")

    -- Run without arguments - should use saved profile
    assert.is_true(run_dot())

    -- Check that the profile was used (apt command executed again)
    assert.is_true(was_command_executed("apt"), "apt should have been executed using saved profile")

    -- Check that .dot file was created with correct profile
    local dot_file_path = pl_path.join(dotfiles_dir, ".dot")
    assert.is_true(pl_path.isfile(dot_file_path), ".dot file should exist")
    local content = pl_file.read(dot_file_path)
    assert.are.equal("test_profile", content:match("^%s*(.-)%s*$"), "Profile name should be saved correctly")
  end)
end)
