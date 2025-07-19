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

  -- Function to detect current OS
  local function detect_os()
    local handle = io.popen "uname"
    local os_name = handle:read "*a"
    handle:close()
    os_name = os_name:gsub("%s+$", "") -- Remove trailing whitespace
    return os_name
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
    local which_script = string.format(
      [[#!/bin/sh
if [ -f "%s/$1" ]; then
  echo "%s/$1"
  exit 0
else
  exit 1
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

    -- Create filesystem operation commands with unique names
    local function find_command(cmd_name)
      -- Try to find the actual command location
      local common_paths = { "/bin/" .. cmd_name, "/usr/bin/" .. cmd_name }
      for _, path in ipairs(common_paths) do
        local check = os.execute(string.format("test -x %q", path))
        if check == 0 then
          return path
        end
      end
      return cmd_name -- fallback to just the command name
    end

    local mkdir_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: mkdir $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "mkdir"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_mkdir"), mkdir_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_mkdir")))

    local ln_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: ln $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "ln"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_ln"), ln_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_ln")))

    local echo_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: echo $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "echo"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_echo"), echo_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_echo")))

    local touch_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: touch $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "touch"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_touch"), touch_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_touch")))

    local cp_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: cp $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "cp"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_cp"), cp_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_cp")))

    local rm_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: rm $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "rm"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_rm"), rm_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_rm")))

    local mv_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: mv $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "mv"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_mv"), mv_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_mv")))

    local find_script = string.format(
      [[#!/bin/sh
echo "COMMAND_EXECUTED: find $@" >> %q
%s "$@"
]],
      command_log_file,
      find_command "find"
    )
    pl_file.write(pl_path.join(bin_dir, "fake_find"), find_script)
    os.execute(string.format("chmod +x %q", pl_path.join(bin_dir, "fake_find")))
  end)

  after_each(function()
    -- Remove the temporary directory
    if tmp_dir and path_exists(tmp_dir) then
      pl_dir.rmtree(tmp_dir)
    end
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
    pl_dir.makepath(pl_path.join(modules_dir, "neovim", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim", "config", "init.vim"), "set number")
    pl_file.write(pl_path.join(modules_dir, "zsh", "zshrc"), "export ZSH=~/.oh-my-zsh")

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
    pl_dir.makepath(pl_path.join(modules_dir, "test_priority", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_priority", "config", "test.conf"), "test config")

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
    pl_dir.makepath(pl_path.join(modules_dir, "test_fallback", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_fallback", "config", "test.conf"), "test config")

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
    pl_dir.makepath(pl_path.join(modules_dir, "test_custom", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_custom", "config", "test.conf"), "test config")

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
    pl_dir.makepath(pl_path.join(modules_dir, "test_bash", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_bash", "config", "test.conf"), "test config")

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
    pl_dir.makepath(pl_path.join(modules_dir, "test_failure", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_failure", "config", "test.conf"), "test config")

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
    pl_dir.makepath(pl_path.join(modules_dir, "test_hooks", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_hooks", "config", "test.conf"), "test config")

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
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module
    setup_module(
      "test_repeated",
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
    pl_dir.makepath(pl_path.join(modules_dir, "test_repeated", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_repeated", "config", "test.conf"), "test config")

    -- Run dot.lua twice
    assert.is_true(run_dot "test_repeated")
    assert.is_true(run_dot "test_repeated")

    -- Check that apt was executed both times (realistic behavior - package managers handle idempotency)
    assert.are.equal(2, get_command_execution_count "fake_apt", "fake_apt should be executed on every run")
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
    assert.is_true(was_command_executed "fake_apt", "fake_apt should have been executed using saved profile")

    -- Check that .dot file was created with correct profile
    local dot_file_path = pl_path.join(dotfiles_dir, ".dot")
    assert.is_true(pl_path.isfile(dot_file_path), ".dot file should exist")
    local content = pl_file.read(dot_file_path)
    assert.are.equal("test_profile", content:match "^%s*(.-)%s*$", "Profile name should be saved correctly")
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
    pl_dir.makepath(pl_path.join(modules_dir, "test_force", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_force", "config", "test.conf"), "test config")

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
    pl_file.write(pl_path.join(modules_dir, "test_unlink", "config"), "test config")

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
      local source_content = pl_file.read(pl_path.join(modules_dir, "test_unlink", "config"))
      assert.are.equal(source_content, content, "File content should have been copied from source")
    end
  end)

  it("should handle purge mode", function()
    -- Create package manager
    create_command("fake_apt", 0, "Package installed successfully")

    -- Set up module with postpurge hook
    setup_module(
      "test_purge",
      string.format(
        [[
return {
  install = {
    fake_apt = "fake_apt install -y test-package",
  },
  link = {
    ["./config"] = "$HOME/.config/test",
  },
  postpurge = "touch %s/postpurge_executed.marker",
}
]],
        home_dir
      )
    )

    -- Create config
    pl_file.write(pl_path.join(modules_dir, "test_purge", "config"), "test config")

    -- First run to create symlink
    assert.is_true(run_dot "test_purge")

    -- Verify symlink exists
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should exist after first run")

    -- Run with purge mode and hooks to force postpurge hook execution
    assert.is_true(run_dot "--purge --hooks test_purge")

    -- Check that symlink was removed
    assert.is_false(path_exists(config_path), "Symlink should have been removed")

    -- Check that postpurge hook ran (using --hooks to force execution)
    local postpurge_marker = pl_path.join(home_dir, "postpurge_executed.marker")
    assert.is_true(path_exists(postpurge_marker), "postpurge hook should have executed")
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
    pl_dir.makepath(pl_path.join(modules_dir, "test_postlink", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_postlink", "config", "test.conf"), "test config")

    -- Run dot.lua
    assert.is_true(run_dot "test_postlink")

    -- Check that postlink hook ran
    local postlink_marker = pl_path.join(home_dir, "postlink_executed.marker")
    assert.is_true(path_exists(postlink_marker), "postlink hook should have executed")

    -- Verify symlink was created
    local config_path = pl_path.join(home_dir, ".config", "test")
    assert.is_true(is_link(config_path), "Symlink should have been created")
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
    pl_dir.makepath(pl_path.join(modules_dir, "test_macos_only", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_macos_only", "config", "test.conf"), "test config")

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
    pl_dir.makepath(pl_path.join(modules_dir, "neovim_config", "config"))
    pl_file.write(pl_path.join(modules_dir, "neovim_config", "config", "init.vim"), "set number")

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

    -- Verify profile was saved
    local dot_file_path = pl_path.join(dotfiles_dir, ".dot")
    assert.is_true(pl_path.isfile(dot_file_path), ".dot file should exist")

    -- Remove the profile
    assert.is_true(run_dot "--remove-profile")

    -- Check that .dot file was removed
    assert.is_false(path_exists(dot_file_path), ".dot file should have been removed")
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
      pl_dir.makepath(pl_path.join(modules_dir, "test_defaults", "defaults"))

      -- Run dot.lua with defaults export
      assert.is_true(run_dot "-e test_defaults")

      -- Check that defaults export was executed
      assert.is_true(was_command_executed "defaults", "defaults export should have been executed")

      -- Check that defaults file was created (in the correct location based on dot.lua path construction)
      local defaults_file = pl_path.join(dotfiles_dir, "defaults", "test.xml")
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
      local defaults_file = pl_path.join(dotfiles_dir, "defaults", "test.xml")
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
    pl_dir.makepath(pl_path.join(modules_dir, "test_multi_pm", "config"))
    pl_file.write(pl_path.join(modules_dir, "test_multi_pm", "config", "test.conf"), "test config")

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
end)
