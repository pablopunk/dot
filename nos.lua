#!/usr/bin/env lua

-- Parse command-line arguments
local force_mode = false
local purge_mode = false
local unlink_mode = false
local version = "0.0.3"
local args = {}

local i = 1
while i <= #arg do
  if arg[i] == "-f" then
    force_mode = true
  elseif arg[i] == "--version" then
    print("nos version " .. version)
    os.exit(0)
  elseif arg[i] == "--purge" then
    purge_mode = true
  elseif arg[i] == "--unlink" then
    unlink_mode = true
  else
    table.insert(args, arg[i])
  end
  i = i + 1
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

-- Execute an OS command and return exit code and output
local function execute(cmd)
  local handle = io.popen(cmd .. " ; echo $?")
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

-- Expand '~' to the user's home directory in the given path
local function expand_path(path)
  if path:sub(1, 1) == "~" then
    return os.getenv "HOME" .. path:sub(2)
  else
    return path
  end
end

-- Check if a path is a directory
local function is_dir(path)
  local cmd = string.format('test -d "%s" 2>/dev/null && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

-- Check if a path is a file
local function is_file(path)
  local cmd = string.format('test -f "%s" 2>/dev/null && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

-- Check if a path is a symlink
local function is_symlink(path)
  local cmd = string.format('test -L "%s" 2>/dev/null && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

-- Get basic file information
local function get_file_info(path)
  local info = {}
  info.is_dir = is_dir(path)
  info.is_file = is_file(path)
  info.is_symlink = is_symlink(path)

  -- Get file size
  local cmd
  if info.is_dir then
    cmd = string.format('du -sk "%s" 2>/dev/null | cut -f1', path)
  elseif info.is_file then
    cmd = string.format('wc -c < "%s" 2>/dev/null', path)
  else
    return nil
  end

  local exit_code, output = execute(cmd)
  info.size = tonumber(output) or 0

  -- Convert KB to bytes for directories
  if info.is_dir then
    info.size = info.size * 1024
  end

  return info
end

-- Check if the symlink at 'output' points to 'source'
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

-- Get all installed brew packages
local function get_installed_brew_packages()
  local exit_code, formula = execute "brew list --formula"
  if exit_code == 0 then
    for package in formula:gmatch "[^\r\n]+" do
      installed_brew_packages[package] = true
    end
  else
    print(colors.red .. "Warning: Failed to get list of installed brew packages" .. colors.reset)
  end
  exit_code, cask = execute "brew list --cask"
  if exit_code == 0 then
    for package in cask:gmatch "[^\r\n]+" do
      installed_brew_packages[package] = true
    end
  else
    print(colors.red .. "Warning: Failed to get list of installed brew casks" .. colors.reset)
  end
end

-- Check if a Homebrew package is installed
local function is_brew_package_installed(package_name)
  local package_name = package_name:gsub("^.*/", "")
  return installed_brew_packages[package_name] == true
end

-- Create the parent directory of a given path if it doesn't exist
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

-- Create a backup of an existing file or directory
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

-- Delete a file, directory, or symlink
local function delete_path(path)
  local cmd = string.format('rm -rf "%s"', path)
  local exit_code, error_output = execute(cmd)
  if exit_code ~= 0 then
    return false, "Failed to delete " .. path .. ": " .. error_output
  end
  return true
end

-- Copy a file or directory
local function copy_path(source, destination)
  local cmd = string.format('cp -R "%s" "%s"', source, destination)
  local exit_code, error_output = execute(cmd)
  if exit_code ~= 0 then
    return false, "Failed to copy " .. source .. " to " .. destination .. ": " .. error_output
  end
  return true
end

-- Process each module by installing/uninstalling dependencies and managing symlinks
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

  local dependencies_changed = false

  -- Process brew dependencies
  if config.brew then
    if purge_mode then
      -- Uninstall dependencies
      for _, brew_entry in ipairs(config.brew) do
        local package_name
        if type(brew_entry) == "string" then
          package_name = brew_entry
        else
          package_name = brew_entry.name
        end

        if is_brew_package_installed(package_name) then
          local cmd = "brew uninstall " .. package_name
          local exit_code, output = execute(cmd)
          if exit_code ~= 0 then
            print_message("error", "dependencies → could not uninstall `" .. package_name .. "`: " .. output)
          else
            print_message("success", "dependencies → uninstalled `" .. package_name .. "`")
            installed_brew_packages[package_name] = nil
            dependencies_changed = true
          end
        else
          print_message("info", "dependencies → `" .. package_name .. "` is not installed")
        end
      end
    else
      -- Install dependencies
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
          dependencies_changed = true
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
  end

  -- Manage config symlink
  if config.config then
    local source = os.getenv "PWD" .. "/" .. module_dir:gsub("^./", "") .. "/" .. config.config.source:gsub("^./", "")
    local output = expand_path(config.config.output)
    local attr = get_file_info(output)

    if purge_mode then
      -- Remove symlink or config file/directory
      if attr then
        local success, err = delete_path(output)
        if success then
          print_message("success", "config → removed " .. output)
        else
          print_message("error", "config → " .. err)
        end
      else
        print_message("info", "config → " .. output .. " does not exist")
      end
    elseif unlink_mode then
      -- Remove symlink and copy source to output
      if attr and attr.is_symlink then
        local success, err = delete_path(output)
        if success then
          print_message("success", "config → symlink removed")

          -- Ensure parent directory exists
          local success, err = ensure_parent_directory(output)
          if not success then
            print_message("error", "config → " .. err)
            return
          end

          -- Copy source to output
          local success, err = copy_path(source, output)
          if success then
            print_message("success", "config → copied " .. source .. " to " .. output)
          else
            print_message("error", "config → " .. err)
          end
        else
          print_message("error", "config → failed to remove symlink: " .. err)
        end
      else
        print_message("info", "config → " .. output .. " is not a symlink or does not exist")
      end
    else
      -- Normal installation: create symlink
      if is_symlink_correct(source, output) then
        print_message("success", "config → symlink correct")
      else
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

        local cmd = string.format('ln -s "%s" "%s"', source, output)
        local exit_code, error_output = execute(cmd)
        if exit_code ~= 0 then
          print_message("error", "config → failed to create symlink: " .. error_output)
        else
          print_message("success", "config → symlink created")
        end
      end
    end
  end

  -- Run post_install or post_purge hooks
  if dependencies_changed then
    if purge_mode and config.post_purge then
      print_message("info", "Running post-purge hook")
      local exit_code, output = execute(config.post_purge)
      if exit_code ~= 0 then
        print_message("error", "post-purge → failed: " .. output)
      else
        print_message("success", "post-purge → completed successfully")
      end
    elseif not purge_mode and config.post_install then
      print_message("info", "Running post-install hook")
      local exit_code, output = execute(config.post_install)
      if exit_code ~= 0 then
        print_message("error", "post-install → failed: " .. output)
      else
        print_message("success", "post-install → completed successfully")
      end
    end
  end

  print "" -- Add a blank line between modules
end

-- Check if an item exists in a table
local function table_string_find(table, item)
  for _, v in ipairs(table) do
    if v == item then
      return true
    end
  end
  return false
end

-- Get all direct child modules
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

-- Process a single tool or profile
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

-- Main function
local function main()
  get_installed_brew_packages()

  local tool_name = args[1]
  if tool_name then
    process_tool(tool_name)
  else
    local modules_dir = "modules"
    if not is_dir(modules_dir) then
      print_message("error", "modules directory not found")
      return
    end

    local modules = get_direct_child_modules()
    if #modules == 0 then
      print_message("error", "no modules found")
      return
    end

    for _, module_name in ipairs(modules) do
      process_module(module_name)
    end
  end
end

main()
