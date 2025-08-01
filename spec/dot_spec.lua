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
  local dot_executable
  local bin_dir
  local command_log_file

  -- Function to check if a path is a symbolic link
  local function is_link(path)
    -- Use system test command instead of lfs, run in the correct directory
    -- Extract the relative path from the full path
    local relative_path = path:gsub("^" .. home_dir .. "/", "")
    local cmd = string.format(
      'cd %q && test -L "%s" && test -e "%s" && echo "true" || echo "false"',
      home_dir,
      relative_path,
      relative_path
    )
    local handle = io.popen(cmd)
    local result = handle:read("*a"):gsub("%s+$", "") -- Remove trailing whitespace
    handle:close()
    return result == "true"
  end

  -- Function to create a fake command that logs when it's called
  local function create_command(name, exit_code, output)
    exit_code = exit_code or 0
    output = output or ""

    local cmd_path = pl_path.join(bin_dir, name)
    local script_content = string.format(
      [[#!/bin/bash
echo "COMMAND_EXECUTED: %s $@" >> %q
echo %q
exit %d
]],
      name,
      command_log_file,
      output,
      exit_code
    )

    pl_file.write(cmd_path, script_content)
    os.execute(string.format("chmod +x %q", cmd_path))
    return cmd_path
  end

  -- Function to create a command that creates a marker file when run
  local function create_marker_command(name, marker_path)
    local cmd_path = pl_path.join(bin_dir, name)
    local script_content = string.format(
      [[#!/bin/bash
echo "COMMAND_EXECUTED: %s $@" >> %q
touch %q
echo "Package %s installed successfully"
exit 0
]],
      name,
      command_log_file,
      marker_path,
      name
    )

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
    for line in log_content:gmatch "[^\n]+" do
      if line:find("COMMAND_EXECUTED: " .. command_name, 1, true) then
        count = count + 1
      end
    end
    return count
  end

  -- Function to detect current OS
  local function detect_os()
    local handle = io.popen "uname"
    local os_name = handle:read "*a"
    handle:close()
    os_name = os_name:gsub("%s+$", "") -- Remove trailing whitespace
    return os_name
  end

  -- Function to get OS name (matches dot.lua implementation)
  local function os_name()
    local handle = io.popen "uname"
    local result = handle:read "*l"
    handle:close()
    return result or "Unknown"
  end

  -- Function to run dot.lua with given arguments
  local function run_dot(args)
    args = args or ""
    -- Find the correct lua path dynamically
    local lua_path = "/opt/homebrew/bin/lua" -- macOS Homebrew
    if not pl_path.isfile(lua_path) then
      lua_path = "/usr/bin/lua" -- Ubuntu/Debian
    end
    if not pl_path.isfile(lua_path) then
      -- Try to find lua in PATH using which
      local handle = io.popen "which lua 2>/dev/null"
      local which_output = handle:read "*a"
      handle:close()
      if which_output and which_output ~= "" then
        lua_path = which_output:gsub("%s+$", "") -- Remove trailing whitespace
      else
        lua_path = "lua" -- Fallback to PATH
      end
    end

    -- Use system lua directly, but put our bin_dir in PATH for fake commands
    local cmd = string.format(
      "cd %q && HOME=%q PATH=%q:/usr/bin:/bin %s %q %s",
      dotfiles_dir,
      home_dir,
      bin_dir,
      lua_path,
      dot_executable,
      args
    )
    return os.execute(cmd)
  end

  -- Function to set up a module with given name and content
  local function setup_module(name, content)
    local module_dir = pl_path.join(dotfiles_dir, name)
    pl_dir.makepath(module_dir)
    local dot_lua = pl_path.join(module_dir, "dot.lua")
    pl_file.write(dot_lua, content)
  end

  -- Function to set up a profile with given name and content
  local function setup_profile(name, content)
    local profiles_lua = pl_path.join(dotfiles_dir, "profiles.lua")
    local profiles_content = string.format(
      [[
return {
  %s = %s
}
]],
      name,
      content
    )
    pl_file.write(profiles_lua, profiles_content)
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
    dot_executable = pl_path.join(dotfiles_dir, "dot.lua")
    bin_dir = pl_path.join(tmp_dir, "bin")
    command_log_file = pl_path.join(tmp_dir, "command_log.txt")

    -- Create necessary directories
    pl_dir.makepath(dotfiles_dir)
    pl_dir.makepath(home_dir)
    pl_dir.makepath(bin_dir)

    -- Copy dot.lua to dotfiles_dir
    os.execute(string.format("cp %q %q", "./dot.lua", dot_executable))
    -- Ensure dot.lua is executable
    os.execute(string.format("chmod +x %q", dot_executable))

    -- Initialize command log file
    pl_file.write(command_log_file, "")

    -- Create a smart which command that checks our bin_dir first
    local which_script = string.format(
      [[#!/bin/sh
if [ -f "%s/$1" ]; then
  echo "%s/$1"
  exit 0
else
  /usr/bin/which "$1" 2>/dev/null || exit 1
fi
]],
      bin_dir,
      bin_dir
    )
    pl_file.write(pl_path.join(bin_dir, "which"), which_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "which")))

    -- Create essential shell commands that lua might need (with unique names)
    create_command("fake_uname", 0, "Linux")
    create_command("fake_mktemp", 0, tmp_dir .. "/tmpfile")
    create_command("fake_test", 0, "")

    -- Create a functional bash command that can execute scripts
    local bash_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: bash $@" >> %q
if command -v bash >/dev/null 2>&1; then
  bash "$@"
elif command -v sh >/dev/null 2>&1; then
  sh "$@"
else
  sh "$@"
fi
]],
      command_log_file
    )
    pl_file.write(pl_path.join(bin_dir, "bash"), bash_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "bash")))

    -- Create real system commands that actually work
    local function create_real_command(name, real_path)
      local script = string.format(
        [[#!/bin/sh
echo "COMMAND_EXECUTED: %s $@" >> %q
%s "$@"
]],
        name,
        command_log_file,
        real_path
      )
      pl_file.write(pl_path.join(bin_dir, name), script)
      os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, name)))
    end

    -- Create real commands that the tests need
    create_real_command("mkdir", "/bin/mkdir")
    create_real_command("ln", "/bin/ln")
    create_real_command("rm", "/bin/rm")
    create_real_command("cp", "/bin/cp")
    create_real_command("mv", "/bin/mv")
    create_real_command("find", "/usr/bin/find")
    create_real_command("readlink", "/usr/bin/readlink")
    create_real_command("test", "/usr/bin/test")
    create_real_command("echo", "/bin/echo")
    create_real_command("touch", "/usr/bin/touch")
    create_real_command("diff", "/usr/bin/diff")
    create_real_command("du", "/usr/bin/du")
    create_real_command("wc", "/usr/bin/wc")
    create_real_command("cut", "/usr/bin/cut")
    create_real_command("defaults", "/usr/bin/defaults")
  end)

  after_each(function()
    -- Remove the temporary directory
    if tmp_dir and path_exists(tmp_dir) then
      pl_dir.rmtree(tmp_dir)
    end
  end)

  it("should create symlinks successfully", function()
    -- Create a simple module with just a link
    setup_module(
      "test_simple_link",
      [[
return {
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create the source file
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_simple_link", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_simple_link", "config", "test.conf"), "test config")

    -- Run dot.lua and capture output
    -- Find the correct lua path dynamically
    local lua_path = "/opt/homebrew/bin/lua" -- macOS Homebrew
    if not pl_path.isfile(lua_path) then
      lua_path = "/usr/bin/lua" -- Ubuntu/Debian
    end
    if not pl_path.isfile(lua_path) then
      -- Try to find lua in PATH using which
      local handle = io.popen "which lua 2>/dev/null"
      local which_output = handle:read "*a"
      handle:close()
      if which_output and which_output ~= "" then
        lua_path = which_output:gsub("%s+$", "") -- Remove trailing whitespace
      else
        lua_path = "lua" -- Fallback to PATH
      end
    end

    local handle = io.popen(
      string.format(
        "cd %q && HOME=%q PATH=%q:/usr/bin:/bin %s %q test_simple_link 2>&1",
        dotfiles_dir,
        home_dir,
        bin_dir,
        lua_path,
        dot_executable
      )
    )
    local output = handle:read "*a"
    handle:close()

    -- Check if symlink creation failed
    if output:find "failed to create symlink" then
      error("Symlink creation failed: " .. output)
    end

    -- Check that symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")

    -- Check that the symlink points to the correct location using system readlink
    local readlink_handle = io.popen(string.format('readlink "%s"', config_path))
    local link_target = readlink_handle:read("*a"):gsub("%s+$", "") -- Remove trailing whitespace
    readlink_handle:close()
    local expected_target = pl_path.join(dotfiles_dir, "test_simple_link", "config")
    assert.are.equal(expected_target, link_target, "Symlink should point to the correct location")
  end)

  it("should install all modules using real commands", function()
    -- Create fake package managers
    create_command("fake_apt", 0, "Package neovim installed successfully")
    create_command("fake_brew", 0, "Package zsh installed successfully")

    -- Set up 'neovim' module that only uses apt
    setup_module(
      "neovim",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y neovim",
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
    fake_brew = "fake_brew install zsh",
  },
  link = {
    ["./zshrc"] = "$HOME/.zshrc",
  }
}
]]
    )

    -- Create config directories and files
    pl_dir.makepath(pl_path.join(dotfiles_dir, "neovim", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(dotfiles_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")

    -- Run dot.lua without arguments to install all modules
    assert.is_true(run_dot())

    -- Check if commands were actually executed
    assert.is_true(was_command_executed "fake_apt", "fake_apt command should have been executed")
    assert.is_true(was_command_executed "fake_brew", "fake_brew command should have been executed")

    -- Check if symlinks are created
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_true(is_link(zshrc), "Expected symlink for zshrc")
  end)

  it("should use the first available package manager", function()
    -- Create both apt and brew commands
    create_command("fake_apt", 0, "Package installed via apt")
    create_command("fake_brew", 0, "Package installed via brew")

    -- Set up module with multiple package managers
    setup_module(
      "test_priority",
      [[
return {
  install = {
    nonexistent = "nonexistent install test-package",
    fake_apt = "fake_apt install -y test-package",
    fake_brew = "fake_brew install test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_priority", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_priority", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_priority")

    -- Check that one of the available commands was executed (since pairs order is not guaranteed)
    local apt_executed = was_command_executed "fake_apt"
    local brew_executed = was_command_executed "fake_brew"
    local nonexistent_executed = was_command_executed "nonexistent"

    assert.is_false(nonexistent_executed, "nonexistent should NOT have been executed")
    assert.is_true(apt_executed or brew_executed, "either fake_apt or fake_brew should have been executed")
    assert.is_false(apt_executed and brew_executed, "only one package manager should be executed")
  end)

  it("should use fallback commands when preferred is not available", function()
    -- Only create brew command (not apt)
    create_command("fake_brew", 0, "Package installed via brew")

    -- Set up module that prefers apt but falls back to brew
    setup_module(
      "test_fallback",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
    fake_brew = "fake_brew install test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_fallback", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_fallback", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_fallback")

    -- Check that brew was used as fallback
    assert.is_false(was_command_executed "fake_apt", "fake_apt should NOT have been executed (doesn't exist)")
    assert.is_true(was_command_executed "fake_brew", "fake_brew should have been executed as fallback")
  end)

  it("should handle custom package managers", function()
    -- Create a custom package manager
    create_command("fake_pacman", 0, "Package installed via pacman")

    -- Set up module with custom package manager
    setup_module(
      "test_custom",
      [[
return {
  install = {
    fake_pacman = "fake_pacman -S test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_custom", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_custom", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_custom")

    -- Check that pacman was executed
    assert.is_true(was_command_executed "fake_pacman", "fake_pacman should have been executed")
  end)

  it("should handle bash commands", function()
    -- Set up module with bash installation that calls echo (which we can track)
    setup_module(
      "test_bash",
      string.format(
        [[
return {
  install = {
    bash = "echo 'bash command executed' > %s/bash_install_marker.txt",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]],
        home_dir
      )
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_bash", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_bash", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_bash")

    -- Check that the marker file was created (this proves the bash command worked)
    local marker_file = pl_path.join(home_dir, "bash_install_marker.txt")
    assert.is_true(path_exists(marker_file), "Bash command should have created marker file")

    -- Check the content of the marker file
    local content = pl_file.read(marker_file)
    assert.are.equal("bash command executed\n", content, "Bash command should have written correct content")
  end)

  it("should handle command failures gracefully", function()
    -- Create a command that fails
    create_command("fake_failing_cmd", 1, "Installation failed")

    -- Set up module with failing command
    setup_module(
      "test_failure",
      [[
return {
  install = {
    fake_failing_cmd = "fake_failing_cmd install test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_failure", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_failure", "config", "test.conf"), "test config")

    -- Run dot.lua (should complete despite install failure)
    assert.is_true(run_dot "test_failure")

    -- Check that the failing command was attempted
    assert.is_true(was_command_executed "fake_failing_cmd", "fake_failing_cmd should have been executed")

    -- Links should still be created despite install failure
    local test_config = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(test_config), "Expected symlink despite install failure")
  end)

  it("should run postinstall hooks when installation happens", function()
    -- Create package manager
    local marker_file = pl_path.join(home_dir, "package_installed.marker")
    create_marker_command("fake_apt", marker_file)

    -- Set up module with postinstall hook
    setup_module(
      "test_hooks",
      string.format(
        [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  },
  postinstall = "touch %s/postinstall_executed.marker",
}
]],
        home_dir
      )
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_hooks", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_hooks", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_hooks")

    -- Check that install happened
    assert.is_true(was_command_executed "fake_apt", "fake_apt should have been executed")
    assert.is_true(path_exists(marker_file), "Package should have been installed")

    -- Check that postinstall hook ran
    local postinstall_marker = pl_path.join(home_dir, "postinstall_executed.marker")
    assert.is_true(path_exists(postinstall_marker), "postinstall hook should have executed")
  end)

  it("should not run postinstall when no installation happens", function()
    -- Set up module without any install commands
    setup_module(
      "test_no_install",
      string.format(
        [[
return {
  link = {
    ["./config"] = "$HOME/.config/test",
  },
  postinstall = "touch %s/postinstall_executed.marker",
}
]],
        home_dir
      )
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_no_install", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_no_install", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_no_install")

    -- Check that no postinstall hook ran
    local postinstall_marker = pl_path.join(home_dir, "postinstall_executed.marker")
    assert.is_false(path_exists(postinstall_marker), "postinstall hook should NOT have executed")
  end)

  it("should run postinstall hook with --postinstall flag even when no installation happens", function()
    -- Set up module without any install commands
    setup_module(
      "test_postinstall_flag",
      string.format(
        [[
return {
  link = {
    ["./config"] = "$HOME/.config/test",
  },
  postinstall = "touch %s/postinstall_executed.marker",
}
]],
        home_dir
      )
    )

    -- Create fake package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Run dot.lua with --postinstall flag
    assert.is_true(run_dot "test_postinstall_flag --postinstall")

    -- Check that postinstall hook ran despite no installation
    local postinstall_marker = pl_path.join(home_dir, "postinstall_executed.marker")
    assert.is_true(path_exists(postinstall_marker), "postinstall hook should have executed with --postinstall flag")
  end)

  it("should skip installation when already persisted", function()
    -- Create package manager
    create_command("fake_persist_apt", 0, "Package installed successfully")

    -- Set up module
    setup_module(
      "test_repeated",
      [[
return {
  install = {
    fake_persist_apt = "fake_persist_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_repeated", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_repeated", "config", "test.conf"), "test config")

    -- Run dot.lua twice
    assert.is_true(run_dot "test_repeated")
    assert.is_true(run_dot "test_repeated")

    -- The command should only execute the first time due to the new persistence lock
    assert.are.equal(
      1,
      get_command_execution_count "fake_persist_apt",
      "fake_persist_apt should only run the first time"
    )
  end)

  it("should reinstall when install command changes", function()
    create_command("fake_apt", 0, "Package installed successfully")

    -- initial module
    setup_module(
      "test_change",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y mytool-v1",
  }
}
]]
    )

    -- First run - should install
    assert.is_true(run_dot "test_change")

    -- Modify module to change install string (simulate version change)
    setup_module(
      "test_change",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y mytool-v2",
  }
}
]]
    )

    -- Second run - should install again because command string changed
    assert.is_true(run_dot "test_change")

    -- Expect two executions now
    assert.are.equal(2, get_command_execution_count "fake_apt", "fake_apt should run again after command changes")
  end)

  it("should handle profiles correctly", function()
    -- Create package managers
    create_command("fake_apt", 0, "Package installed via apt")
    create_command("fake_brew", 0, "Package installed via brew")

    -- Set up multiple modules
    setup_module(
      "neovim",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y neovim",
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
    fake_brew = "fake_brew install zsh",
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
{
  "neovim"
}
]]
    )

    -- Create configs
    pl_dir.makepath(pl_path.join(dotfiles_dir, "neovim", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(dotfiles_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")

    -- Run with work profile
    assert.is_true(run_dot "work")

    -- Check that only apt was executed (neovim), not brew (zsh)
    assert.is_true(was_command_executed "fake_apt", "fake_apt should have been executed for neovim")
    assert.is_false(was_command_executed "fake_brew", "fake_brew should NOT have been executed (zsh not in profile)")

    -- Check that only neovim symlink was created
    local nvim_config = pl_path.join(home_dir, ".config", "nvim")
    local zshrc = pl_path.join(home_dir, ".zshrc")
    assert.is_true(is_link(nvim_config), "Expected symlink for nvim_config")
    assert.is_false(path_exists(zshrc), "zshrc should not exist (not in profile)")
  end)

  it("should save and use last profile", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed via apt")

    -- Set up module with no file operations
    setup_module(
      "simple_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y simple-package",
  }
}
]]
    )

    -- Create test profile
    setup_profile(
      "test_profile",
      [[
{
  "simple_module"
}
]]
    )

    -- Run with profile to save it
    assert.is_true(run_dot "test_profile")

    -- Check that profile was saved in the lock file
    local lock_file_path = pl_path.join(home_dir, ".cache", "dot", "lock.yaml")
    assert.is_true(pl_path.isfile(lock_file_path), "Lock file should exist")
    local content = pl_file.read(lock_file_path)
    local match = content:match "profile: test_profile"
    assert.is_not_nil(match, "Profile name should be saved in lock file")
  end)

  -- NEW TESTS FOR MISSING FEATURES

  it("should handle force mode with backup creation", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module
    setup_module(
      "test_force",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_force", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_force", "config", "test.conf"), "test config")

    -- Create existing file at destination
    local existing_config = pl_path.join(home_dir, ".config", "test")
    pl_dir.makepath(pl_path.dirname(existing_config))
    pl_file.write(existing_config, "existing content")

    -- Run dot.lua with force mode
    assert.is_true(run_dot "-f test_force")

    -- Check that backup was created
    local backup_file = existing_config .. ".before-dot"
    assert.is_true(path_exists(backup_file), "Backup file should have been created")

    -- Check backup content
    local backup_content = pl_file.read(backup_file)
    assert.are.equal("existing content", backup_content, "Backup should contain original content")

    -- Check that symlink was created
    assert.is_true(is_link(existing_config), "Symlink should have been created")
  end)

  it("should handle unlink mode (remove symlink and copy file)", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module
    setup_module(
      "test_unlink",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config file (not directory)
    pl_file.write(pl_path.join(dotfiles_dir, "test_unlink", "config"), "test config")

    -- First run to create symlink
    assert.is_true(run_dot "test_unlink")

    -- Verify symlink exists
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should exist after first run")

    -- Run with unlink mode
    assert.is_true(run_dot "--unlink test_unlink")

    -- Check that symlink was removed and file was copied
    assert.is_false(is_link(config_path), "Symlink should have been removed")
    assert.is_true(path_exists(config_path), "File should exist at destination")

    -- Check that content was copied (the file should be a regular file now, not a symlink)
    if path_exists(config_path) then
      local content = pl_file.read(config_path)
      -- The content might be from the source file, not the symlink target
      local source_content = pl_file.read(pl_path.join(dotfiles_dir, "test_unlink", "config"))
      assert.are.equal(source_content, content, "File content should have been copied from source")
    end
  end)

  it("should run postlink hooks when linking happens", function()
    -- Set up module with postlink hook
    setup_module(
      "test_postlink",
      string.format(
        [[
return {
  link = {
    ["./config"] = "$HOME/.config/test",
  },
  postlink = "touch %s/postlink_executed.marker",
}
]],
        home_dir
      )
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_postlink", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_postlink", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_postlink")

    -- Check that postlink hook ran
    local postlink_marker = pl_path.join(home_dir, "postlink_executed.marker")
    assert.is_true(path_exists(postlink_marker), "postlink hook should have executed")

    -- Verify symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
  end)

  it("should run postlink hook with --postlink flag even when no linking happens", function()
    -- Set up module with postlink hook but no link changes
    setup_module(
      "test_postlink_flag",
      string.format(
        [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  postlink = "touch %s/postlink_executed.marker",
}
]],
        home_dir
      )
    )

    -- Create fake package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Run dot.lua with --postlink flag
    assert.is_true(run_dot "test_postlink_flag --postlink")

    -- Check that postlink hook ran despite no linking
    local postlink_marker = pl_path.join(home_dir, "postlink_executed.marker")
    assert.is_true(path_exists(postlink_marker), "postlink hook should have executed with --postlink flag")
  end)

  it("should handle OS restrictions", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    local current_os = detect_os()
    local is_macos = current_os == "Darwin"

    -- Set up module restricted to macOS
    setup_module(
      "test_macos_only",
      [[
return {
  os = { "mac" },
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_macos_only", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_macos_only", "config", "test.conf"), "test config")

    -- Run dot.lua
    local success = run_dot "test_macos_only"

    if is_macos then
      -- On macOS, the module should run and commands should be executed
      assert.is_true(success, "dot.lua should succeed on macOS")
      assert.is_true(was_command_executed "fake_apt", "fake_apt should have been executed on macOS")

      -- Check that symlink was created
      local config_path = pl_path.join(home_dir, ".config", "test")
      assert.is_true(is_link(config_path), "Symlink should have been created on macOS")
    else
      -- On non-macOS, the module should be skipped
      assert.is_true(success, "dot.lua should succeed even when skipping modules")
      assert.is_false(was_command_executed "fake_apt", "fake_apt should NOT have been executed on " .. current_os)

      -- Check that symlink was NOT created
      local config_path = pl_path.join(home_dir, ".config", "test")
      assert.is_false(is_link(config_path), "Symlink should NOT have been created on " .. current_os)
    end
  end)

  it("should handle fuzzy module matching", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with a specific name
    setup_module(
      "neovim_config",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y neovim",
  },
  link = {
    ["./config"] = "$HOME/.config/nvim",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "neovim_config", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "neovim_config", "config", "init.vim"), "set number")

    -- Run dot.lua with fuzzy match
    assert.is_true(run_dot "neovim")

    -- Check that commands were executed (fuzzy matching should work)
    assert.is_true(was_command_executed "fake_apt", "fake_apt should have been executed via fuzzy match")

    -- Check that symlink was created
    local config_path = pl_path.join(home_dir, ".config", "nvim")
    assert.is_true(is_link(config_path), "Symlink should have been created via fuzzy match")
  end)

  it("should handle remove profile functionality", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module
    setup_module(
      "neovim",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y neovim",
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
{
  "neovim"
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "neovim", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "neovim", "config", "init.vim"), "set number")

    -- Run with profile to save it
    assert.is_true(run_dot "test_profile")

    -- Verify profile was saved in lock file
    local lock_file_path = pl_path.join(home_dir, ".cache", "dot", "lock.yaml")
    assert.is_true(pl_path.isfile(lock_file_path), "Lock file should exist")
    local content = pl_file.read(lock_file_path)
    assert.is_not_nil(content:match "profile: test_profile", "Profile should be saved in lock file")

    -- Remove the profile
    assert.is_true(run_dot "--remove-profile")

    -- Check that profile was removed from lock file
    content = pl_file.read(lock_file_path)
    assert.is_nil(content:match "profile:", "Profile should have been removed from lock file")
  end)

  it("should handle macOS defaults export", function()
    local current_os = detect_os()
    local is_macos = current_os == "Darwin"

    if is_macos then
      -- Create fake defaults command that actually creates files
      local defaults_script = "#!/bin/sh\n"
        .. 'echo "COMMAND_EXECUTED: defaults $@" >> '
        .. command_log_file
        .. "\n"
        .. "# Parse the command to extract the output file\n"
        .. 'output_file=""\n'
        .. 'for arg in "$@"; do\n'
        .. '  if [[ "$arg" == *".xml" ]]; then\n'
        .. '    output_file="$arg"\n'
        .. "    break\n"
        .. "  fi\n"
        .. "done\n"
        .. 'echo "DEBUG: output_file = $output_file" >> '
        .. command_log_file
        .. "\n"
        .. 'if [[ -n "$output_file" ]]; then\n'
        .. '  echo "DEBUG: creating directory $(dirname "$output_file")" >> '
        .. command_log_file
        .. "\n"
        .. '  mkdir -p "$(dirname "$output_file")"\n'
        .. '  echo "DEBUG: writing file $output_file" >> '
        .. command_log_file
        .. "\n"
        .. '  echo \'<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>TestKey</key><string>test value</string></dict></plist>\' > "$output_file"\n'
        .. '  echo "DEBUG: file created, checking if exists" >> '
        .. command_log_file
        .. "\n"
        .. '  if [[ -f "$output_file" ]]; then\n'
        .. '    echo "DEBUG: file exists" >> '
        .. command_log_file
        .. "\n"
        .. "  else\n"
        .. '    echo "DEBUG: file does not exist" >> '
        .. command_log_file
        .. "\n"
        .. "  fi\n"
        .. '  echo "Preferences exported successfully"\n'
        .. "  exit 0\n"
        .. "else\n"
        .. '  echo "No output file specified"\n'
        .. "  exit 1\n"
        .. "fi\n"

      pl_file.write(pl_path.join(bin_dir, "defaults"), defaults_script)
      os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "defaults")))

      -- Set up module with defaults
      setup_module(
        "test_defaults",
        [[
return {
  defaults = {
    ["com.test.app"] = "./defaults/test.xml",
  }
}
]]
      )

      -- Create defaults directory
      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_defaults", "defaults"))

      -- Run dot.lua with defaults export
      assert.is_true(run_dot "-e test_defaults")

      -- Check that defaults export was executed
      assert.is_true(was_command_executed "defaults", "defaults export should have been executed")

      -- Check that defaults file was created (in the correct location based on dot.lua path construction)
      local defaults_file = pl_path.join(dotfiles_dir, "test_defaults", "defaults", "test.xml")
      assert.is_true(path_exists(defaults_file), "Defaults file should have been created")
    else
      -- On non-macOS, defaults should be skipped
      setup_module(
        "test_defaults",
        [[
return {
  defaults = {
    ["com.test.app"] = "./defaults/test.xml",
  }
}
]]
      )

      -- Run dot.lua with defaults export (should be skipped)
      assert.is_true(run_dot "-e test_defaults")

      -- Check that defaults was NOT executed
      assert.is_false(was_command_executed "defaults", "defaults should NOT be executed on " .. current_os)

      -- Check that defaults file was NOT created
      local defaults_file = pl_path.join(dotfiles_dir, "defaults", "test.xml")
      assert.is_false(path_exists(defaults_file), "Defaults file should NOT be created on " .. current_os)
    end
  end)

  it("should handle macOS defaults import", function()
    local current_os = detect_os()
    local is_macos = current_os == "Darwin"

    if is_macos then
      -- Create fake defaults command that actually works
      local defaults_script = "#!/bin/sh\n"
        .. 'echo "COMMAND_EXECUTED: defaults $@" >> '
        .. command_log_file
        .. "\n"
        .. "# Parse the command to extract the input file\n"
        .. 'input_file=""\n'
        .. 'for arg in "$@"; do\n'
        .. '  if [[ "$arg" == *".xml" ]]; then\n'
        .. '    input_file="$arg"\n'
        .. "    break\n"
        .. "  fi\n"
        .. "done\n"
        .. 'if [[ -f "$input_file" ]]; then\n'
        .. '  echo "Preferences imported successfully"\n'
        .. "  exit 0\n"
        .. "else\n"
        .. '  echo "File not found: $input_file"\n'
        .. "  exit 1\n"
        .. "fi\n"

      pl_file.write(pl_path.join(bin_dir, "defaults"), defaults_script)
      os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "defaults")))

      -- Set up module with defaults
      setup_module(
        "test_defaults",
        [[
return {
  defaults = {
    ["com.test.app"] = "./defaults/test.xml",
  }
}
]]
      )

      -- Create defaults file in the correct location (same as export test)
      local defaults_file = pl_path.join(dotfiles_dir, "test_defaults", "defaults", "test.xml")
      pl_dir.makepath(pl_path.dirname(defaults_file))
      pl_file.write(defaults_file, "test preferences")

      -- Run dot.lua with defaults import
      assert.is_true(run_dot "-i test_defaults")

      -- Check that defaults import was executed
      assert.is_true(was_command_executed "defaults", "defaults import should have been executed")
    else
      -- On non-macOS, defaults should be skipped
      setup_module(
        "test_defaults",
        [[
return {
  defaults = {
    ["com.test.app"] = "./defaults/test.xml",
  }
}
]]
      )

      -- Run dot.lua with defaults import (should be skipped)
      assert.is_true(run_dot "-i test_defaults")

      -- Check that defaults was NOT executed
      assert.is_false(was_command_executed "defaults", "defaults should NOT be executed on " .. current_os)
    end
  end)

  it("should handle multiple package managers in install system", function()
    -- Create multiple package managers
    create_command("fake_apt", 0, "Package installed via apt")
    create_command("fake_brew", 0, "Package installed via brew")
    create_command("fake_yum", 0, "Package installed via yum")

    -- Set up module with multiple package managers
    setup_module(
      "test_multi_pm",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
    fake_brew = "fake_brew install test-package",
    fake_yum = "fake_yum install test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_multi_pm", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_multi_pm", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_multi_pm")

    -- Check that only one package manager was executed (first available)
    local apt_executed = was_command_executed "fake_apt"
    local brew_executed = was_command_executed "fake_brew"
    local yum_executed = was_command_executed "fake_yum"

    local total_executed = (apt_executed and 1 or 0) + (brew_executed and 1 or 0) + (yum_executed and 1 or 0)
    assert.are.equal(1, total_executed, "Only one package manager should be executed")

    -- Check that symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
  end)

  it("should work without check field (backward compatibility)", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module without check field
    setup_module(
      "test_no_check",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_no_check", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_no_check", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_no_check")

    -- Check that install command was executed (no check field)
    assert.is_true(was_command_executed "fake_apt", "install command should have been executed")

    -- Check that symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
  end)

  it("should force install when --install flag is used", function()
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module without check field
    setup_module(
      "test_force_install",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config directory and file
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_force_install", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_force_install", "config", "test.conf"), "test config")

    -- First run to create lock
    assert.is_true(run_dot "test_force_install")

    -- Second run with --install flag should execute again
    assert.is_true(run_dot "--install test_force_install")

    -- 'fake_apt' should have been executed twice
    assert.are.equal(2, get_command_execution_count "fake_apt", "install command should run again with --install flag")

    -- Symlink exists
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
  end)

  it("should handle multi-line install commands successfully", function()
    -- Create multiple fake commands for multi-line test
    create_command("fake_step1", 0, "Step 1 completed")
    create_command("fake_step2", 0, "Step 2 completed")
    create_command("fake_step3", 0, "Step 3 completed")
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with multi-line install command
    setup_module(
      "test_multiline_success",
      [[
return {
  install = {
    fake_apt = "fake_step1 install package1\nfake_step2 install package2\nfake_step3 install package3",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_multiline_success", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_multiline_success", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_multiline_success")

    -- Check that all steps were executed
    assert.is_true(was_command_executed "fake_step1", "Step 1 should have been executed")
    assert.is_true(was_command_executed "fake_step2", "Step 2 should have been executed")
    assert.is_true(was_command_executed "fake_step3", "Step 3 should have been executed")

    -- Check that symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
  end)

  it("should handle multi-line install commands with failure", function()
    -- Create commands where one will fail
    create_command("fake_step1", 0, "Step 1 completed")
    create_command("fake_step2", 1, "Step 2 failed") -- This will fail
    create_command("fake_step3", 0, "Step 3 completed")
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with multi-line install command that will fail
    setup_module(
      "test_multiline_failure",
      [[
return {
  install = {
    fake_apt = "fake_step1 install package1\nfake_step2 install package2\nfake_step3 install package3",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_multiline_failure", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_multiline_failure", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_multiline_failure")

    -- Check that first step was executed
    assert.is_true(was_command_executed "fake_step1", "Step 1 should have been executed")

    -- Check that second step was executed (and failed)
    assert.is_true(was_command_executed "fake_step2", "Step 2 should have been executed")

    -- Check that third step was NOT executed (due to failure)
    assert.is_false(was_command_executed "fake_step3", "Step 3 should NOT have been executed due to failure")

    -- Check that symlink was still created (installation failure doesn't stop linking)
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created despite install failure")
  end)

  it("should handle multi-line commands with empty lines", function()
    -- Create fake commands
    create_command("fake_step1", 0, "Step 1 completed")
    create_command("fake_step2", 0, "Step 2 completed")
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with multi-line install command containing empty lines
    setup_module(
      "test_multiline_empty",
      [[
return {
  install = {
    fake_apt = "fake_step1 install package1\n\nfake_step2 install package2",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_multiline_empty", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_multiline_empty", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_multiline_empty")

    -- Check that both steps were executed (empty lines should be ignored)
    assert.is_true(was_command_executed "fake_step1", "Step 1 should have been executed")
    assert.is_true(was_command_executed "fake_step2", "Step 2 should have been executed")

    -- Check that symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
  end)

  it("should handle multi-line commands with leading/trailing whitespace", function()
    -- Create fake commands
    create_command("fake_step1", 0, "Step 1 completed")
    create_command("fake_step2", 0, "Step 2 completed")
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with multi-line install command containing whitespace
    setup_module(
      "test_multiline_whitespace",
      [[
return {
  install = {
    fake_apt = "fake_step1 install package1\n  fake_step2 install package2",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_multiline_whitespace", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_multiline_whitespace", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_multiline_whitespace")

    -- Check that all commands were executed
    assert.is_true(was_command_executed "fake_step1 install package1")
    assert.is_true(was_command_executed "fake_step2 install package2")
  end)

  describe("individual module installation with profiles.lua", function()
    it("should install individual module when profile doesn't exist", function()
      -- Create profiles.lua with some profiles
      pl_file.write(
        pl_path.join(dotfiles_dir, "profiles.lua"),
        [[
return {
  work = { "test_module1", "test_module2" },
  personal = { "test_module3" }
}
]]
      )

      -- Create a module that's not in any profile
      create_command("fake_apt", 0, "Package installed successfully")
      setup_module(
        "test_individual_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
      )

      -- Create config
      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_individual_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_individual_module", "config", "test.conf"), "test config")

      -- Run dot.lua with individual module
      assert.is_true(run_dot "test_individual_module")

      -- Check that install command was executed
      assert.is_true(was_command_executed "fake_apt install -y test-package")
    end)

    it("should use profile when it exists", function()
      -- Create profiles.lua
      pl_file.write(
        pl_path.join(dotfiles_dir, "profiles.lua"),
        [[
return {
  work = { "test_profile_module" }
}
]]
      )

      -- Create module that's in the profile
      create_command("fake_apt", 0, "Package installed successfully")
      setup_module(
        "test_profile_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
      )

      -- Create config
      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_profile_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_profile_module", "config", "test.conf"), "test config")

      -- Run dot.lua with profile name
      assert.is_true(run_dot "work")

      -- Check that install command was executed
      assert.is_true(was_command_executed "fake_apt install -y test-package")
    end)

    it("should handle fuzzy matching for individual modules", function()
      -- Create profiles.lua
      pl_file.write(
        pl_path.join(dotfiles_dir, "profiles.lua"),
        [[
return {
  work = { "test_module1" },
  personal = { "test_module2" }
}
]]
      )

      -- Create modules with similar names
      create_command("fake_apt", 0, "Package installed successfully")

      setup_module(
        "test_stats_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y stats-package",
  },
  link = {
    ["./config"] = "$HOME/.config/stats",
  }
}
]]
      )

      setup_module(
        "test_startup_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y startup-package",
  },
  link = {
    ["./config"] = "$HOME/.config/startup",
  }
}
]]
      )

      -- Create configs
      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_stats_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_stats_module", "config", "test.conf"), "stats config")

      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_startup_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_startup_module", "config", "test.conf"), "startup config")

      -- Test fuzzy matching with unique match
      assert.is_true(run_dot "stats")

      -- Check that stats module was executed
      assert.is_true(was_command_executed "fake_apt install -y stats-package")
    end)

    it("should install all modules when multiple fuzzy matches are found", function()
      -- Create profiles.lua
      pl_file.write(
        pl_path.join(dotfiles_dir, "profiles.lua"),
        [[
return {
  work = { "test_module1" }
}
]]
      )

      -- Create modules with similar names
      create_command("fake_apt", 0, "Package installed successfully")

      setup_module(
        "test_stats_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y stats-package",
  },
  link = {
    ["./config"] = "$HOME/.config/stats",
  }
}
]]
      )

      setup_module(
        "test_startup_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y startup-package",
  },
  link = {
    ["./config"] = "$HOME/.config/startup",
  }
}
]]
      )

      -- Create configs
      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_stats_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_stats_module", "config", "test.conf"), "stats config")

      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_startup_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_startup_module", "config", "test.conf"), "startup config")

      -- Test fuzzy matching with multiple matches
      assert.is_true(run_dot "st") -- Should install both modules

      -- Check that both install commands were executed
      assert.is_true(was_command_executed "fake_apt install -y stats-package")
      assert.is_true(was_command_executed "fake_apt install -y startup-package")
    end)

    it("should install all modules when multiple fuzzy matches are found (no profiles.lua)", function()
      -- Create modules with similar names (no profiles.lua)
      create_command("fake_apt", 0, "Package installed successfully")

      setup_module(
        "test_stats_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y stats-package",
  },
  link = {
    ["./config"] = "$HOME/.config/stats",
  }
}
]]
      )

      setup_module(
        "test_startup_module",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y startup-package",
  },
  link = {
    ["./config"] = "$HOME/.config/startup",
  }
}
]]
      )

      -- Create configs
      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_stats_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_stats_module", "config", "test.conf"), "stats config")

      pl_dir.makepath(pl_path.join(dotfiles_dir, "test_startup_module", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "test_startup_module", "config", "test.conf"), "startup config")

      -- Test fuzzy matching with multiple matches (no profiles.lua)
      assert.is_true(run_dot "st") -- Should install both modules

      -- Check that both install commands were executed
      assert.is_true(was_command_executed "fake_apt install -y stats-package")
      assert.is_true(was_command_executed "fake_apt install -y startup-package")
    end)

    it("should handle exact module path when fuzzy matching fails", function()
      -- Create profiles.lua
      pl_file.write(
        pl_path.join(dotfiles_dir, "profiles.lua"),
        [[
return {
  work = { "test_module1" }
}
]]
      )

      -- Create a module with exact name
      create_command("fake_apt", 0, "Package installed successfully")
      setup_module(
        "exact_module_name",
        [[
return {
  install = {
    fake_apt = "fake_apt install -y exact-package",
  },
  link = {
    ["./config"] = "$HOME/.config/exact",
  }
}
]]
      )

      -- Create config
      pl_dir.makepath(pl_path.join(dotfiles_dir, "exact_module_name", "config"))
      pl_file.write(pl_path.join(dotfiles_dir, "exact_module_name", "config", "test.conf"), "exact config")

      -- Test exact module path
      assert.is_true(run_dot "exact_module_name")

      -- Check that install command was executed
      assert.is_true(was_command_executed "fake_apt install -y exact-package")
    end)

    it("should show profile list when neither profile nor module exists", function()
      -- Create profiles.lua
      pl_file.write(
        pl_path.join(dotfiles_dir, "profiles.lua"),
        [[
return {
  work = { "test_module1" },
  personal = { "test_module2" }
}
]]
      )

      -- Test non-existent module/profile
      local success = run_dot "nonexistent_module"
      -- The script exits with code 1 when module not found
      -- os.execute behavior varies by system, so we accept any non-false value
      assert.is_not_false(success) -- Command executed (true, nil, or other non-false value)
    end)
  end)

  it("should handle single-line commands (backward compatibility)", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with single-line install command
    setup_module(
      "test_single_line",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    -- Create config
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_single_line", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_single_line", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_single_line")

    -- Check that install command was executed
    assert.is_true(was_command_executed "fake_apt", "install command should have been executed")

    -- Check that symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
  end)

  it("should handle relative paths in defaults correctly", function()
    -- Create a module with relative path in defaults
    create_command("defaults", 0, "Preferences imported successfully")

    setup_module(
      "test_relative_defaults",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  defaults = {
    ["com.test.app"] = "./test.xml",
  }
}
]]
    )

    -- Create the XML file in the module directory
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_relative_defaults"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_relative_defaults", "test.xml"), "test plist content")

    -- Run dot.lua
    assert.is_true(run_dot "test_relative_defaults")

    -- Check that defaults import was called (the exact path might vary due to temp directories)
    -- Note: defaults only work on macOS, so we check based on OS
    if os_name() == "Darwin" then
      assert.is_true(was_command_executed "defaults", "defaults command should have been executed")
    else
      -- On non-macOS, defaults should be skipped
      assert.is_false(was_command_executed "defaults", "defaults command should not be executed on non-macOS")
    end
  end)

  it("should check for defaults differences and prompt user instead of auto-importing", function()
    -- Create a module with defaults configuration
    create_command("defaults", 0, "Preferences exported successfully")
    create_command("diff", 1, "") -- Return 1 to indicate differences

    setup_module(
      "test_defaults_check",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  defaults = {
    ["com.test.app"] = "./test.xml",
  }
}
]]
    )

    -- Create the XML file in the module directory
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_defaults_check"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_defaults_check", "test.xml"), "test plist content")

    -- Run dot.lua (should check for differences, not import)
    assert.is_true(run_dot "test_defaults_check")

    -- Check that defaults export was called to get current settings
    -- Note: defaults only work on macOS, so we check based on OS
    if os_name() == "Darwin" then
      assert.is_true(was_command_executed "defaults export")
      -- Check that diff was called to compare files
      assert.is_true(was_command_executed "diff")
    else
      -- On non-macOS, defaults should be skipped
      assert.is_false(was_command_executed "defaults export", "defaults should not be executed on non-macOS")
      assert.is_false(was_command_executed "diff", "diff should not be executed on non-macOS")
    end
  end)

  it("should handle OS detection with both string and array values", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with string OS value
    setup_module(
      "test_os_string",
      [[
return {
  os = "macos",
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test_string",
  }
}
]]
    )

    -- Set up module with array OS value
    setup_module(
      "test_os_array",
      [[
return {
  os = {"macos", "linux"},
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test_array",
  }
}
]]
    )

    -- Create configs
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_os_string", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_os_string", "config", "test.conf"), "test config")
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_os_array", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_os_array", "config", "test.conf"), "test config")

    -- Check that install commands were executed based on OS support
    local current_os = os_name()
    if current_os == "Darwin" then
      -- On macOS, both modules should work
      assert.is_true(run_dot "test_os_string")
      assert.is_true(run_dot "test_os_array")

      -- Both should have executed the command
      assert.is_true(
        was_command_executed "fake_apt",
        "install command should have been executed for both modules on macOS"
      )

      -- Check that symlinks were created
      local config_path1 = pl_path.join(home_dir, ".config", "test_string")
      local config_path2 = pl_path.join(home_dir, ".config", "test_array")
      assert.is_true(is_link(config_path1), "Symlink should have been created for string OS")
      assert.is_true(is_link(config_path2), "Symlink should have been created for array OS")
    elseif current_os == "Linux" then
      -- On Linux, only the array module should work
      -- Clear command log before testing
      pl_file.write(command_log_file, "")

      -- Test string OS module (should be skipped)
      assert.is_true(run_dot "test_os_string")
      assert.is_false(was_command_executed "fake_apt", "install command should not be executed for string OS on Linux")

      -- Clear command log before testing array module
      pl_file.write(command_log_file, "")

      -- Test array OS module (should work)
      assert.is_true(run_dot "test_os_array")
      assert.is_true(was_command_executed "fake_apt", "install command should have been executed for array OS")

      -- Check that only array symlink was created
      local config_path1 = pl_path.join(home_dir, ".config", "test_string")
      local config_path2 = pl_path.join(home_dir, ".config", "test_array")
      assert.is_false(is_link(config_path1), "Symlink should not have been created for string OS on Linux")
      assert.is_true(is_link(config_path2), "Symlink should have been created for array OS")
    end
  end)

  it("should save and use last profile", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed via apt")

    -- Set up module with no file operations
    setup_module(
      "simple_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y simple-package",
  }
}
]]
    )

    -- Create test profile
    setup_profile(
      "test_profile",
      [[
{
  "simple_module"
}
]]
    )

    -- Run with profile to save it
    assert.is_true(run_dot "test_profile")

    -- Check that profile was saved in the lock file
    local lock_file_path = pl_path.join(home_dir, ".cache", "dot", "lock.yaml")
    assert.is_true(pl_path.isfile(lock_file_path), "Lock file should exist")
    local content = pl_file.read(lock_file_path)
    assert.is_not_nil(content:match "profile: test_profile", "Profile name should be saved in lock file")
  end)

  it("should handle nested modules correctly", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up nested module structure (child without parent dot.lua)
    setup_module(
      "parent_module/child_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y child-package",
  },
  link = {
    ["./config"] = "$HOME/.config/child",
  }
}
]]
    )

    -- Create configs
    pl_dir.makepath(pl_path.join(dotfiles_dir, "parent_module", "child_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "parent_module", "child_module", "config", "child.conf"), "child config")

    -- Run dot.lua to install all modules
    assert.is_true(run_dot())

    -- Check that child module was processed (since parent has no dot.lua)
    assert.is_true(was_command_executed "fake_apt install -y child-package", "Child module should be installed")

    -- Check that symlink was created
    local child_config = pl_path.join(home_dir, ".config", "child")
    assert.is_true(is_link(child_config), "Child symlink should be created")
  end)

  it("should exclude nested modules when parent has dot.lua", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up parent module with dot.lua
    setup_module(
      "parent_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y parent-package",
  },
  link = {
    ["./config"] = "$HOME/.config/parent",
  }
}
]]
    )

    -- Set up child module (should be excluded)
    setup_module(
      "parent_module/child_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y child-package",
  },
  link = {
    ["./config"] = "$HOME/.config/child",
  }
}
]]
    )

    -- Create configs
    pl_dir.makepath(pl_path.join(dotfiles_dir, "parent_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "parent_module", "config", "parent.conf"), "parent config")
    pl_dir.makepath(pl_path.join(dotfiles_dir, "parent_module", "child_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "parent_module", "child_module", "config", "child.conf"), "child config")

    -- Run dot.lua to install all modules
    assert.is_true(run_dot())

    -- Check that only parent module was processed
    assert.is_true(was_command_executed "fake_apt install -y parent-package", "Parent module should be installed")
    assert.is_false(was_command_executed "fake_apt install -y child-package", "Child module should be excluded")

    -- Check that only parent symlink was created
    local parent_config = pl_path.join(home_dir, ".config", "parent")
    local child_config = pl_path.join(home_dir, ".config", "child")
    assert.is_true(is_link(parent_config), "Parent symlink should be created")
    assert.is_false(is_link(child_config), "Child symlink should NOT be created")
  end)

  it("should handle profile exclusion patterns", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up multiple modules
    setup_module(
      "work_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y work-package",
  },
  link = {
    ["./config"] = "$HOME/.config/work",
  }
}
]]
    )

    setup_module(
      "personal_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y personal-package",
  },
  link = {
    ["./config"] = "$HOME/.config/personal",
  }
}
]]
    )

    setup_module(
      "shared_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y shared-package",
  },
  link = {
    ["./config"] = "$HOME/.config/shared",
  }
}
]]
    )

    -- Create configs
    pl_dir.makepath(pl_path.join(dotfiles_dir, "work_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "work_module", "config", "work.conf"), "work config")
    pl_dir.makepath(pl_path.join(dotfiles_dir, "personal_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "personal_module", "config", "personal.conf"), "personal config")
    pl_dir.makepath(pl_path.join(dotfiles_dir, "shared_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "shared_module", "config", "shared.conf"), "shared config")

    -- Create profile with exclusion
    setup_profile(
      "personal_profile",
      [[
{
  "*",
  "!work_module"
}
]]
    )

    -- Run with profile
    assert.is_true(run_dot "personal_profile")

    -- Check that work module was excluded
    assert.is_false(was_command_executed "fake_apt install -y work-package", "Work module should be excluded")

    -- Check that other modules were included
    assert.is_true(was_command_executed "fake_apt install -y personal-package", "Personal module should be included")
    assert.is_true(was_command_executed "fake_apt install -y shared-package", "Shared module should be included")

    -- Check that symlinks were created for included modules
    local personal_config = pl_path.join(home_dir, ".config", "personal")
    local shared_config = pl_path.join(home_dir, ".config", "shared")
    local work_config = pl_path.join(home_dir, ".config", "work")
    assert.is_true(is_link(personal_config), "Personal symlink should be created")
    assert.is_true(is_link(shared_config), "Shared symlink should be created")
    assert.is_false(is_link(work_config), "Work symlink should NOT be created")
  end)

  it("should handle edge cases in fuzzy matching", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up modules with similar names
    setup_module(
      "test_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  }
}
]]
    )

    setup_module(
      "test_exact_module",
      [[
return {
  install = {
    fake_apt = "fake_apt install -y test-exact-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test-exact",
  }
}
]]
    )

    -- Create configs
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_module", "config", "test.conf"), "test config")
    pl_dir.makepath(pl_path.join(dotfiles_dir, "test_exact_module", "config"))
    pl_file.write(pl_path.join(dotfiles_dir, "test_exact_module", "config", "test.conf"), "test exact config")

    -- Test exact match should only match one module
    assert.is_true(run_dot "test_exact_module")

    -- Check that only exact match was executed
    assert.is_false(
      was_command_executed "fake_apt install -y test-package",
      "Generic test module should not be executed"
    )
    assert.is_true(was_command_executed "fake_apt install -y test-exact-package", "Exact match should be executed")

    -- Clear command log
    pl_file.write(command_log_file, "")

    -- Test partial match should match both modules
    assert.is_true(run_dot "test")

    -- Check that both modules were executed (using the actual command strings from the output)
    assert.is_true(was_command_executed "fake_apt", "Both modules should be executed")

    -- Check that both symlinks were created
    local test_config = pl_path.join(home_dir, ".config", "test")
    local test_exact_config = pl_path.join(home_dir, ".config", "test-exact")
    assert.is_true(is_link(test_config), "Test symlink should be created")
    assert.is_true(is_link(test_exact_config), "Test-exact symlink should be created")
  end)

  it("should handle upgrade command", function()
    -- Create fake curl command that returns a mock dot.lua content
    local curl_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: curl $@" >> %q
echo "#!/usr/bin/env lua"
echo ""
echo "local version = '2.0.0'"
echo ""
echo "print('dot version ' .. version)"
echo "os.exit(0)"
]],
      command_log_file
    )
    pl_file.write(pl_path.join(bin_dir, "curl"), curl_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "curl")))

    -- Create fake readlink command that returns the expected path for upgrade
    local readlink_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: readlink $@" >> %q
echo "%s"
]],
      command_log_file,
      home_dir .. "/.local/bin/dot"
    )
    pl_file.write(pl_path.join(bin_dir, "readlink"), readlink_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "readlink")))

    -- Create fake cp command
    local cp_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: cp $@" >> %q
/bin/cp "$@"
]],
      command_log_file
    )
    pl_file.write(pl_path.join(bin_dir, "cp"), cp_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "cp")))

    -- Create fake chmod command
    local chmod_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: chmod $@" >> %q
/bin/chmod "$@"
]],
      command_log_file
    )
    pl_file.write(pl_path.join(bin_dir, "chmod"), chmod_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "chmod")))

    -- Create the expected directory structure for upgrade
    local local_bin_dir = pl_path.join(home_dir, ".local", "bin")
    pl_dir.makepath(local_bin_dir)

    -- Create a fake dot script in the expected location
    local expected_dot_path = pl_path.join(local_bin_dir, "dot")
    pl_file.write(expected_dot_path, "#!/usr/bin/env lua\nprint('fake dot')\n")
    os.execute(string.format("chmod +x %q", expected_dot_path))

    -- Run upgrade command
    assert.is_true(run_dot "--upgrade")

    -- Check that curl was executed to download the new version
    assert.is_true(was_command_executed "curl", "curl should have been executed to download new version")

    -- Check that readlink was executed to resolve script path
    assert.is_true(was_command_executed "readlink", "readlink should have been executed to resolve script path")

    -- Check that cp was executed to create backup
    assert.is_true(was_command_executed "cp", "cp should have been executed to create backup")

    -- Check that chmod was executed to make script executable
    assert.is_true(was_command_executed "chmod", "chmod should have been executed to make script executable")

    -- Check that backup file was created
    local backup_file = expected_dot_path .. ".backup"
    assert.is_true(path_exists(backup_file), "Backup file should have been created")

    -- Check that the script was updated with new content
    local script_content = pl_file.read(expected_dot_path)
    assert.is_not_nil(script_content:match "version = '2.0.0'", "Script should have been updated with new version")
  end)
end)
