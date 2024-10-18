#!/usr/bin/env lua

local version = "0.2.0"

local MOCK_BREW = false

-- Parse command-line arguments
local function parse_args()
  local force_mode = false
  local purge_mode = false
  local unlink_mode = false
  local mock_brew = false
  local hooks_mode = false
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
    elseif arg[i] == "--mock-brew" then
      mock_brew = true
    elseif arg[i] == "--hooks" then
      hooks_mode = true
    else
      table.insert(args, arg[i])
    end
    i = i + 1
  end

  return {
    force_mode = force_mode,
    purge_mode = purge_mode,
    unlink_mode = unlink_mode,
    mock_brew = mock_brew,
    hooks_mode = hooks_mode,
    args = args,
  }
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

-- Filesystem utility functions
local function is_dir(path)
  local cmd = string.format('test -d "%s" 2>/dev/null && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

local function is_file(path)
  local cmd = string.format('test -f "%s" 2>/dev/null && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

local function is_symlink(path)
  local cmd = string.format('test -L "%s" 2>/dev/null && echo "true" || echo "false"', path)
  local exit_code, output = execute(cmd)
  return output:match "true" ~= nil
end

local function get_file_size(path)
  local cmd = is_dir(path) and string.format('du -sk "%s" 2>/dev/null | cut -f1', path)
    or string.format('wc -c < "%s" 2>/dev/null', path)
  local exit_code, output = execute(cmd)
  local size = tonumber(output) or 0
  if is_dir(path) then
    size = size * 1024 -- Convert KB to bytes
  end
  return size
end

local function get_file_info(path)
  local info = {
    is_dir = is_dir(path),
    is_file = is_file(path),
    is_symlink = is_symlink(path),
  }
  if info.is_dir or info.is_file then
    info.size = get_file_size(path)
    return info
  else
    return nil
  end
end

local function is_symlink_correct(source, output)
  local cmd = string.format('readlink "%s"', output)
  local exit_code, link_target = execute(cmd)
  if exit_code == 0 then
    local source_info = get_file_info(source)
    local target_info = get_file_info(link_target)
    return source_info
      and target_info
      and source_info.is_file == target_info.is_file
      and source_info.is_dir == target_info.is_dir
      and source_info.size == target_info.size
  end
  return false
end

-- Brew utility functions
local function get_installed_brew_packages()
  if MOCK_BREW then
    installed_brew_packages = {
      neovim = true,
      zsh = true,
    }
    return
  end

  local function add_packages(cmd)
    local exit_code, output = execute(cmd)
    if exit_code == 0 then
      for package in output:gmatch "[^\r\n]+" do
        installed_brew_packages[package] = true
      end
    else
      print(colors.red .. "Warning: Failed to get list of installed brew packages" .. colors.reset)
    end
  end
  add_packages "brew list --formula"
  add_packages "brew list --cask"
end

local function is_brew_package_installed(package_name)
  package_name = package_name:gsub("^.*/", "")
  return installed_brew_packages[package_name] == true
end

-- File operation functions
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

local function create_backup(path)
  local backup_path = path .. ".before-dot"
  local i = 1
  while is_file(backup_path) or is_dir(backup_path) do
    backup_path = path .. ".before-dot." .. i
    i = i + 1
  end
  local cmd = string.format('mv "%s" "%s"', path, backup_path)
  local exit_code, error_output = execute(cmd)
  if exit_code ~= 0 then
    return false, "Failed to create backup: " .. error_output
  end
  return true, backup_path
end

local function delete_path(path)
  local cmd = string.format('rm -rf "%s"', path)
  local exit_code, error_output = execute(cmd)
  if exit_code ~= 0 then
    return false, "Failed to delete " .. path .. ": " .. error_output
  end
  return true
end

local function copy_path(source, destination)
  local cmd = string.format('cp -R "%s" "%s"', source, destination)
  local exit_code, error_output = execute(cmd)
  if exit_code ~= 0 then
    return false, "Failed to copy " .. source .. " to " .. destination .. ": " .. error_output
  end
  return true
end

-- Check if an item exists in a table
local function table_string_find(tbl, item)
  for _, v in ipairs(tbl) do
    if v == item then
      return true
    end
  end
  return false
end

-- Get all modules recursively
local function get_all_modules()
  local modules = {}
  local modules_dir = "modules"
  -- Find all init.lua files within modules directory
  local cmd = string.format('find "%s" -type f -name "init.lua"', modules_dir)
  local exit_code, output = execute(cmd)
  if exit_code == 0 then
    for file in output:gmatch "[^\n]+" do
      -- Extract the module path relative to modules_dir
      local module_path = file:match("^" .. modules_dir .. "/(.+)/init.lua$")
      local parent = module_path:match "^(.+)/[^/]+$"
      if not table_string_find(modules, parent) then
        -- Remove trailing /init.lua from the path
        module_path = module_path:gsub("/init.lua$", "")
        table.insert(modules, module_path)
      end
    end
  end
  return modules
end

local function str_split(str, delimiter)
  local result = {}
  for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
    table.insert(result, match)
  end
  return result
end

local function str_trim(str)
  return str:gsub("^%s*(.-)%s*$", "%1")
end

local function table_remove_empty(tbl)
  local new_tbl = {}
  for _, v in ipairs(tbl) do
    local v_trim = str_trim(v)
    if v_trim ~= "" then
      table.insert(new_tbl, v)
    end
  end
  return new_tbl
end

local function run_hook(hook_script, hook_type)
  print_message("info", "Running " .. hook_type .. " hook")
  local hook_lines = str_split(hook_script, "\n")
  hook_lines = table_remove_empty(hook_lines)
  for _, line in ipairs(hook_lines) do
    local exit_code, output = execute(line)
    if exit_code ~= 0 then
      print_message("error", hook_type .. " → failed: " .. output)
      return
    end
  end
  print_message("success", hook_type .. " → completed successfully")
end

local function process_brew_dependencies(config, purge_mode)
  local dependencies_changed = false
  if not config.brew then
    return dependencies_changed
  end

  if MOCK_BREW then
    -- When mocking brew, just print what would happen
    for _, brew_entry in ipairs(config.brew) do
      local package_name = type(brew_entry) == "string" and brew_entry or brew_entry.name
      if purge_mode then
        print_message("info", "MOCK: Would uninstall " .. package_name)
      else
        print_message("info", "MOCK: Would install " .. package_name)
      end
    end
    return true -- Simulate that dependencies changed
  end

  if purge_mode then
    -- Uninstall dependencies
    for _, brew_entry in ipairs(config.brew) do
      local package_name = type(brew_entry) == "string" and brew_entry or brew_entry.name

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
      local package_name = type(brew_entry) == "string" and brew_entry or brew_entry.name
      local install_options = type(brew_entry) == "table" and brew_entry.options or ""
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
        -- print_message("success", "dependencies → `" .. package_name .. "` already installed")
      end
    end
    if all_deps_installed then
      print_message("success", "all dependencies installed")
    end
  end
  return dependencies_changed
end

local function handle_config_symlink(config, module_dir, options)
  if not config.config then
    return
  end

  local configs = type(config.config) == "table" and config.config[1] and config.config or { config.config }
  local all_configs_linked = true

  for _, cfg in ipairs(configs) do
    local source = os.getenv "PWD" .. "/" .. module_dir:gsub("^./", "") .. "/" .. cfg.source:gsub("^./", "")
    local output = expand_path(cfg.output)
    local attr = get_file_info(output)

    if options.purge_mode then
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
    elseif options.unlink_mode then
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
        -- print_message("success", "config → symlink correct for " .. output)
      else
        all_configs_linked = false
        if attr then
          if options.force_mode then
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

        local cmd = string.format('ln -sf "%s" "%s"', source, output)
        local exit_code, error_output = execute(cmd)
        if exit_code ~= 0 then
          print_message("error", "config → failed to create symlink: " .. error_output)
        else
          print_message("success", "config → symlink created for " .. output)
        end
      end
    end
  end

  if all_configs_linked and not options.unlink_mode and not options.purge_mode then
    print_message("success", "all configurations are linked")
  elseif all_configs_linked and options.purge_mode then
    print_message("success", "all configurations are removed")
  elseif all_configs_linked and options.unlink_mode then
    print_message("success", "all configurations are unlinked")
  end
end

-- Process each module by installing/uninstalling dependencies and managing symlinks
local function process_module(module_name, options)
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

  local dependencies_changed = process_brew_dependencies(config, options.purge_mode)

  handle_config_symlink(config, module_dir, options)

  -- Run post_install or post_purge hooks
  if dependencies_changed or options.hooks_mode then
    if options.purge_mode and config.post_purge then
      run_hook(config.post_purge, "post-purge")
    elseif not options.purge_mode and config.post_install then
      run_hook(config.post_install, "post-install")
    end
  end

  print "" -- Add a blank line between modules
end

-- Check if a module should be excluded
local function should_exclude(module_name, exclusions)
  for _, exclusion in ipairs(exclusions) do
    if module_name == exclusion or module_name:match("^" .. exclusion .. "/") then
      return true
    end
  end
  return false
end

-- Process a single tool or profile
local function process_tool(tool_name, options)
  local profile_path = os.getenv "PWD" .. "/profiles/" .. tool_name .. ".lua"

  if is_file(profile_path) then
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
    local exclusions = {}

    for _, module_name in ipairs(profile.modules) do
      if module_name:sub(1, 1) == "!" then
        table.insert(exclusions, module_name:sub(2))
      elseif module_name == "*" then
        local all_modules = get_all_modules()
        for _, module in ipairs(all_modules) do
          modules_to_process[module] = true
        end
      else
        modules_to_process[module_name] = true
      end
    end

    for module_name in pairs(modules_to_process) do
      if not should_exclude(module_name, exclusions) then
        process_module(module_name, options)
      end
    end
  else
    -- Process the single tool module
    local module_path = "modules/" .. tool_name .. "/init.lua"
    if is_file(module_path) then
      process_module(tool_name, options)
    else
      print(colors.red .. "Module not found: " .. tool_name .. colors.reset)
    end
  end
end

-- Main function
local function main()
  local options = parse_args()

  if options.mock_brew then
    MOCK_BREW = true
  end

  get_installed_brew_packages()

  local tool_name = options.args[1]
  if tool_name then
    process_tool(tool_name, options)
  else
    local modules_dir = "modules"
    if not is_dir(modules_dir) then
      print_message("error", "modules directory not found")
      return
    end

    local modules = get_all_modules()
    if #modules == 0 then
      print_message("error", "no modules found")
      return
    end

    for _, module_name in ipairs(modules) do
      process_module(module_name, options)
    end
  end
end

main()
