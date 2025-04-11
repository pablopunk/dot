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
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
  }
}
]]
    )

    -- Set up 'zsh' module
    setup_module(
      "zsh",
      [[
return {
  brew = { "zsh" },
  config = {
    source = "./zshrc",
    output = "~/.zshrc",
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
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
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
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
  }
}
]]
    )

    -- Set up 'zsh' module
    setup_module(
      "zsh",
      [[
return {
  brew = { "zsh" },
  config = {
    source = "./zshrc",
    output = "~/.zshrc",
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
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
  }
}
]]
    )

    -- Set up 'zsh' module
    setup_module(
      "zsh",
      [[
return {
  brew = { "zsh" },
  config = {
    source = "./zshrc",
    output = "~/.zshrc",
  }
}
]]
    )

    -- Set up 'apps/work' module
    setup_module(
      "apps/work",
      [[
return {
  brew = { "work-app" },
  config = {
    source = "./config",
    output = "~/.config/work-app",
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
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      string.format(
        [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
  }
}
]],
        home_dir,
        home_dir
      )
    ) -- Ensure absolute paths if needed

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
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
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
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
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

  it("should run hooks", function()
    -- Set up 'dummy_app' module with hooks using absolute paths
    setup_module(
      "dummy_app",
      string.format(
        [[
return {
  brew = { },
  config = {
    source = "./config",
    output = "~/.config/dummy_app",
  },
  post_install = "touch %s/.hooks_post_install_ran",
  post_purge = "touch %s/.hooks_post_purge_ran",
}
]],
        home_dir,
        home_dir
      )
    )

    -- Create module config
    pl_dir.makepath(pl_path.join(modules_dir, "dummy_app", "config"))
    pl_file.write(pl_path.join(modules_dir, "dummy_app", "config", "config.txt"), "dummy config")

    -- Run dot.lua to install 'dummy_app'
    assert.is_true(run_dot "dummy_app")

    -- Check if post_install hook ran
    local hook_install = pl_path.join(home_dir, ".hooks_post_install_ran")
    print("Checking for hook_install at:", hook_install)
    assert.is_true(path_exists(hook_install), "Post-install hook did not run")

    -- Run dot.lua with --purge option for 'dummy_app'
    assert.is_true(run_dot "--purge dummy_app")

    -- Check if post_purge hook ran
    local hook_purge = pl_path.join(home_dir, ".hooks_post_purge_ran")
    print("Checking for hook_purge at:", hook_purge)
    assert.is_true(path_exists(hook_purge), "Post-purge hook did not run")
  end)

  it("should handle multiple configs in a module", function()
    -- Set up 'multi_config' module with multiple configs
    setup_module(
      "multi_config",
      [[
return {
  brew = { },
  config = {
    {
      source = "./config/settings.json",
      output = "~/settings.json",
    },
    {
      source = "./config/keybindings.json",
      output = "~/keybindings.json",
    }
  }
}
]]
    )

    -- Create config files
    pl_dir.makepath(pl_path.join(modules_dir, "multi_config", "config"))
    pl_file.write(pl_path.join(modules_dir, "multi_config", "config", "settings.json"), [[{ "setting": "value" }]])
    pl_file.write(pl_path.join(modules_dir, "multi_config", "config", "keybindings.json"), [[{ "key": "binding" }]])

    -- Run dot.lua to install 'multi_config'
    assert.is_true(run_dot "multi_config")

    -- Check if symlinks are created
    local settings = pl_path.join(home_dir, "settings.json")
    local keybindings = pl_path.join(home_dir, "keybindings.json")
    assert.is_true(is_link(settings), "Expected symlink for settings.json")
    assert.is_true(is_link(keybindings), "Expected symlink for keybindings.json")
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

  it("should handle wget configuration", function()
    -- Set up 'wget_test' module with wget configuration
    setup_module(
      "wget_test",
      [[
return {
  wget = {
    url = "https://example.com/test.bin",
    output = "]] .. pl_path.join(home_dir, "test_output") .. [[",
  }
}
]]
    )

    -- Run dot.lua for 'wget_test' module with mock-wget
    assert.is_true(run_dot "wget_test --mock-wget")

    -- Check if the mock download and unzip operations were performed
    local test_output = pl_path.join(home_dir, "test_output")
    assert.is_true(path_exists(test_output), "Expected test_output to exist after mock wget operation")
  end)

  it("should handle defaults export and import", function()
    -- Set up 'defaults_test' module with defaults configuration
    setup_module(
      "defaults_test",
      [[
return {
  defaults = {
    {
      plist = "./defaults/SwiftShift.plist",
      app = "com.pablopunk.SwiftShift",
    }
  }
}
]]
    )

    -- Create module directory
    pl_dir.makepath(pl_path.join(modules_dir, "defaults_test", "defaults"))

    -- Run dot.lua with --defaults-export and --mock-defaults options
    assert.is_true(run_dot "defaults_test --defaults-export --mock-defaults")

    -- Check if the plist file was created
    local plist_path = pl_path.join(modules_dir, "defaults_test", "defaults", "SwiftShift.plist")
    assert.is_true(pl_path.isfile(plist_path), "Expected plist file to be created")

    -- Verify the content of the plist file
    local content = pl_file.read(plist_path)
    assert.are.equal("mocked preferences", content)

    -- Run dot.lua with --defaults-import and --mock-defaults options
    assert.is_true(run_dot "defaults_test --defaults-import --mock-defaults")
    -- Check if the import was successful (mocked, so no actual change)
    -- This is mainly to ensure no errors occur during the import process
  end)

  it("should handle XML format for defaults export and import", function()
    -- Set up a module with XML format for defaults
    setup_module(
      "defaults_xml_test",
      [[
return {
  defaults = {
    {
      plist = "./defaults/SwiftShift.xml",
      app = "com.pablopunk.SwiftShift",
    }
  }
}
]]
    )

    -- Create module directory
    pl_dir.makepath(pl_path.join(modules_dir, "defaults_xml_test", "defaults"))

    -- Run dot.lua with --defaults-export and --mock-defaults options
    assert.is_true(run_dot "defaults_xml_test --defaults-export --mock-defaults")

    -- Check if the XML file was created
    local xml_path = pl_path.join(modules_dir, "defaults_xml_test", "defaults", "SwiftShift.xml")
    assert.is_true(pl_path.isfile(xml_path), "Expected XML file to be created")

    -- Verify the content of the XML file
    local content = pl_file.read(xml_path)
    assert.is_true(content:match "<plist" ~= nil, "Expected XML content in the file")
    assert.is_true(content:match "<!DOCTYPE plist" ~= nil, "Expected DOCTYPE in XML content")
    assert.is_true(content:match "<dict" ~= nil, "Expected dict element in XML content")

    -- Run dot.lua with --defaults-import and --mock-defaults options
    assert.is_true(run_dot "defaults_xml_test --defaults-import --mock-defaults")
    -- Check if the import was successful (mocked, so no actual change)
    -- This is mainly to ensure no errors occur during the import process
  end)

  it("should save the last used profile", function()
    -- Set up 'neovim' module
    setup_module(
      "neovim",
      [[
return {
  brew = { "neovim" },
  config = {
    source = "./config",
    output = "~/.config/nvim",
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

  it("should respect OS-specific modules", function()
    -- Set up a module that only works on the current OS
    local current_os = io.popen("uname"):read("*l") -- Get the current OS
    local is_macos = current_os == "Darwin"
    local is_linux = current_os == "Linux"
    
    -- Set up 'os_specific' module for the current OS
    setup_module(
      "os_specific_current",
      [[
return {
  os = { "]] .. (is_macos and "mac" or "linux") .. [[" },
  config = {
    source = "./config",
    output = "~/.config/os_specific_current",
  }
}
]]
    )
    
    -- Set up a module for the other OS
    setup_module(
      "os_specific_other",
      [[
return {
  os = { "]] .. (is_macos and "linux" or "mac") .. [[" },
  config = {
    source = "./config",
    output = "~/.config/os_specific_other",
  }
}
]]
    )
    
    -- Set up a module that works on multiple OSes
    setup_module(
      "os_specific_multi",
      [[
return {
  os = { "mac", "linux" },
  config = {
    source = "./config",
    output = "~/.config/os_specific_multi",
  }
}
]]
    )
    
    -- Create config directories and files
    pl_dir.makepath(pl_path.join(modules_dir, "os_specific_current", "config"))
    pl_file.write(pl_path.join(modules_dir, "os_specific_current", "config", "config.txt"), "current os config")
    
    pl_dir.makepath(pl_path.join(modules_dir, "os_specific_other", "config"))
    pl_file.write(pl_path.join(modules_dir, "os_specific_other", "config", "config.txt"), "other os config")
    
    pl_dir.makepath(pl_path.join(modules_dir, "os_specific_multi", "config"))
    pl_file.write(pl_path.join(modules_dir, "os_specific_multi", "config", "config.txt"), "multi os config")
    
    -- Run dot.lua without arguments to install all modules
    assert.is_true(run_dot())
    
    -- Check if the current OS module is installed and the other OS module is skipped
    local current_config = pl_path.join(home_dir, ".config", "os_specific_current")
    local other_config = pl_path.join(home_dir, ".config", "os_specific_other")
    local multi_config = pl_path.join(home_dir, ".config", "os_specific_multi")
    
    assert.is_true(is_link(current_config), "Expected symlink for current OS module")
    assert.is_false(path_exists(other_config), "Did not expect symlink for other OS module")
    assert.is_true(is_link(multi_config), "Expected symlink for multi-OS module")
  end)
end)
