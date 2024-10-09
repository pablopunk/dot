#!/usr/bin/env lua

-- Parse command-line arguments
local force_mode = false
local version = "0.0.3"

for i, arg in ipairs(arg) do
  if arg == "-f" then
    force_mode = true
  elseif arg == "--version" then
    print("nos version " .. version)
    os.exit(0)
  end
end

-- ANSI color codes
local colors = {
  reset = "\27[0m",
  bold = "\27[1m",
  green = "\27[32m",
  yellow = "\27[33m",
  red = "\27[31m",
  blue = "\27[34m",
  magenta = "\27[35m",
}

-- Unified print function
local function print_message(message_type, message)
  local color, symbol
  if message_type == "success" then
    color, symbol = colors.green, "✓"
  elseif message_type == "error" then
    color, symbol = colors.red, "✗"
  elseif message_type == "warning" then
    color, symbol = colors.yellow, "!"
  elseif message_type == "info" then
    color, symbol = colors.blue, "•"
  else
    color, symbol = colors.reset, "-"
  end

  local prefix = "  "
  print(prefix .. color .. symbol .. " " .. message .. colors.reset)
end

local installed_brew_packages = {}

-- Execute an os command and return exit code
local function execute(cmd)
  local handle = io.popen(cmd .. " 2>&1; echo $?")
  local result = handle:read "*a"
  handle:close()
  local lines = {}
  for line in result:gmatch "[^\r\n]+" do
    table.insert(lines, line)
  end
  local exit_code = tonumber(lines[#lines])
  table.remove(lines)
  return exit_code, table.concat(lines, "\n")
end

-- Expands '~' to the user's home directory in the given path
local function expand_path(path)
  if path:sub(1, 1) == "~" then
    return os.getenv "HOME" .. path:sub(2)
  else
    return path
  end
end

-- Simple function to check if a path is a directory
local function is_dir(path)
  local cmd = string.format('test -d "%s" && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

-- Simple function to check if a path is a file
local function is_file(path)
  local cmd = string.format('test -f "%s" && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

-- Function to get basic file information
local function get_file_info(path)
  local info = {}
  info.is_dir = is_dir(path)
  info.is_file = is_file(path)

  -- Get file size (works for both files and directories on Linux and macOS)
  local cmd
  if info.is_dir then
    cmd = string.format('du -sk "%s" | cut -f1', path)
  else
    cmd = string.format('wc -c < "%s"', path)
  end
  local exit_code, output = execute(cmd)
  info.size = tonumber(output) or 0

  -- Convert KB to bytes for directories
  if info.is_dir then
    info.size = info.size * 1024
  end

  return info
end

-- Checks if the symlink at 'output' points to 'source'
local function is_symlink_correct(source, output)
  local cmd = string.format('readlink "%s"', output)
  local exit_code, link_target = execute(cmd)
  if exit_code == 0 then
    local source_info = get_file_info(source)
    local target_info = get_file_info(link_target)
    return source_info.is_file == target_info.is_file
      and source_info.is_dir == target_info.is_dir
      and source_info.size == target_info.size
  end
  return false
end

-- Gets all installed brew packages
local function get_installed_brew_packages()
  local exit_code, formula = execute "brew list --formula"
  if exit_code == 0 then
    for package in formula:gmatch "[^\r\n]+" do
      installed_brew_packages[package] = true
    end
  else
    print(colors.red .. "Warning: Failed to get list of installed brew packages" .. colors.reset)
  end
  local exit_code, cask = execute "brew list --cask"
  if exit_code == 0 then
    for package in cask:gmatch "[^\r\n]+" do
      installed_brew_packages[package] = true
    end
  else
    print(colors.red .. "Warning: Failed to get list of installed brew casks" .. colors.reset)
  end
end

-- Checks if a Homebrew package is already installed
local function is_brew_package_installed(package_name)
  local package_name = package_name:gsub("^.*/", "")
  return installed_brew_packages[package_name] == true
end

-- Creates the parent directory of a given path if it doesn't exist
local function ensure_parent_directory(path)
  local parent = path:match "(.+)/[^/]*$"
  if parent then
    local cmd = string.format('mkdir -p "%s"', parent)
    local exit_code, _ = execute(cmd)
    if exit_code ~= 0 then
      return false, "Failed to create parent directory"
    end
  end
  return true
end

-- Creates a backup of an existing file or directory
local function create_backup(path)
  local backup_path = path .. ".before-nos"
  local i = 1
  while is_file(backup_path) or is_dir(backup_path) do
    backup_path = path .. ".before-nos." .. i
    i = i + 1
  end
  local cmd = string.format('mv "%s" "%s"', path, backup_path)
  local exit_code, error_output = execute(cmd)
  if exit_code ~= 0 then
    return false, "Failed to create backup: " .. error_output
  end
  return true, backup_path
end

-- Processes each module by installing dependencies and creating symlinks
local function process_module(module_name)
  print(colors.bold .. colors.blue .. "[" .. module_name .. "]" .. colors.reset)

  local module_dir = "modules/" .. module_name
  local init_file = module_dir .. "/init.lua"

  -- Load the init.lua file
  local config_func, load_err = loadfile(init_file)
  if not config_func then
    print_message("error", "Error loading configuration: " .. load_err)
    return
  end

  local success, config = pcall(config_func)
  if not success or not config then
    print_message("error", "Error executing configuration: " .. tostring(config))
    return
  end

  local dependencies_installed = false

  -- Process brew dependencies
  if config.brew then
    local all_deps_installed = true
    for _, brew_entry in ipairs(config.brew) do
      local package_name, install_options
      if type(brew_entry) == "string" then
        package_name = brew_entry
        install_options = ""
      else
        package_name = brew_entry.name
        install_options = brew_entry.options or ""
      end

      if not is_brew_package_installed(package_name) then
        all_deps_installed = false
        dependencies_installed = true
        local cmd = "brew install " .. package_name .. " " .. install_options
        local exit_code, output = execute(cmd)
        if exit_code ~= 0 then
          print_message("error", "dependencies → could not install `" .. package_name .. "`: " .. output)
        else
          print_message("success", "dependencies → installed `" .. package_name .. "`")
          installed_brew_packages[package_name] = true
        end
      else
        print_message("success", "dependencies → `" .. package_name .. "` already installed")
      end
    end
    if all_deps_installed then
      print_message("success", "all dependencies installed")
    end
  end

  -- Check symlink configuration
  if config.config then
    local source = os.getenv "PWD" .. "/" .. module_dir:gsub("^./", "") .. "/" .. config.config.source:gsub("^./", "")
    local output = expand_path(config.config.output)
    if is_symlink_correct(source, output) then
      print_message("success", "config → symlink correct")
    else
      local attr = get_file_info(output)
      if attr then
        if force_mode then
          local success, result = create_backup(output)
          if success then
            print_message("warning", "config → existing config backed up to " .. result)
          else
            print_message("error", "config → " .. result)
            return
          end
        else
          print_message("error", "config → file already exists at " .. output .. ". Use -f to force.")
          return
        end
      end

      -- Ensure parent directory exists
      local success, err = ensure_parent_directory(output)
      if not success then
        print_message("error", "config → " .. err)
        return
      end

      local cmd = string.format('ln -s%s "%s" "%s"', force_mode and "f" or "", source, output)
      local exit_code, error_output = execute(cmd)
      if exit_code ~= 0 then
        print_message("error", "config → failed to create symlink: " .. error_output)
      else
        print_message("success", "config → symlink created")
      end
    end
  end

  -- Run post_install hook if dependencies were installed
  if dependencies_installed and config.post_install then
    print_message("info", "Running post-install hook")
    local exit_code, output = execute(config.post_install)
    if exit_code ~= 0 then
      print_message("error", "post-install → failed: " .. output)
    else
      print_message("success", "post-install → completed successfully")
    end
  end

  print "" -- Add a blank line between modules
end

local function table_string_find(table, item)
  for _, v in ipairs(table) do
    if v == item then
      return true
    end
  end
  return false
end

-- Recursively search for init.lua files
local function find_init_files(dir)
  local init_files = {}
  local cmd = string.format('find "%s" -type f -name "init.lua"', dir)
  local exit_code, output = execute(cmd)
  if exit_code == 0 then
    for file in output:gmatch "[^\n]+" do
      local dir = file:match "(.+)/init%.lua"
      local parent_dir = dir:match "(.+)/[^/]*$"
      local parent_in_array = table_string_find(init_files, parent_dir)
      if dir and not parent_in_array then
        table.insert(init_files, dir)
      end
    end
  end

  return init_files
end

-- New function to get all direct child modules
local function get_direct_child_modules()
  local modules = {}
  local modules_dir = "modules"
  local cmd = string.format('find "%s" -maxdepth 1 -type d', modules_dir)
  local exit_code, output = execute(cmd)
  if exit_code == 0 then
    for dir in output:gmatch "[^\n]+" do
      if dir ~= modules_dir then
        local module_name = dir:match("^" .. modules_dir .. "/(.+)$")
        if module_name and is_file(dir .. "/init.lua") then
          table.insert(modules, module_name)
        end
      end
    end
  end
  return modules
end

-- Modified function to process a single tool
local function process_tool(tool_name)
  local profile_path = os.getenv "PWD" .. "/profiles/" .. tool_name .. ".lua"
  local profile_attr = get_file_info(profile_path)

  if profile_attr and profile_attr.is_file then
    -- Load and process the profile
    local profile_func, load_err = loadfile(profile_path)
    if not profile_func then
      print(colors.red .. "Error loading profile: " .. load_err .. colors.reset)
      return
    end

    local success, profile = pcall(profile_func)
    if not success or not profile or not profile.modules then
      print(colors.red .. "Error executing profile or invalid profile structure" .. colors.reset)
      return
    end

    local modules_to_process = {}
    for _, module_name in ipairs(profile.modules) do
      if module_name == "*" then
        local direct_children = get_direct_child_modules()
        for _, child in ipairs(direct_children) do
          if not modules_to_process[child] then
            table.insert(modules_to_process, child)
            modules_to_process[child] = true
          end
        end
      else
        if not modules_to_process[module_name] then
          table.insert(modules_to_process, module_name)
          modules_to_process[module_name] = true
        end
      end
    end

    for _, module_name in ipairs(modules_to_process) do
      process_module(module_name)
    end
  else
    -- Process the single tool module
    local module_path = "modules/" .. tool_name .. "/init.lua"
    if is_file(module_path) then
      process_module(tool_name)
    else
      print(colors.red .. "Module not found: " .. tool_name .. colors.reset)
    end
  end
end

-- Main function to iterate over modules and process them
local function main()
  get_installed_brew_packages()

  local tool_name = arg[1]
  if tool_name then
    process_tool(tool_name)
  else
    local modules_dir = "modules"
    if not is_dir(modules_dir) then
      print_message("error", "modules directory not found")
      return
    end

    local init_files = find_init_files(modules_dir)
    if #init_files == 0 then
      print_message("error", "no modules found")
      return
    end

    for _, module_dir in ipairs(init_files) do
      local module_name = module_dir:gsub("^" .. modules_dir .. "/", "")
      process_module(module_name)
    end
  end
end

main()
