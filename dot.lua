#!/usr/bin/env lua

local version = "0.6.0"

local MOCK_BREW = false
local MOCK_WGET = false
local MOCK_DEFAULTS = false

-- Parse command-line arguments
local function parse_args()
  local force_mode = false
  local purge_mode = false
  local unlink_mode = false
  local mock_brew = false
  local mock_wget = false
  local hooks_mode = false
  local mock_defaults = false
  local defaults_export = false
  local defaults_import = false
  local remove_profile = false
  local args = {}

  local i = 1
  while i <= #arg do
    if arg[i] == "-f" then
      force_mode = true
    elseif arg[i] == "--version" or arg[i] == "-v" then
      print("dot version " .. version)
      os.exit(0)
    elseif arg[i] == "--purge" then
      purge_mode = true
    elseif arg[i] == "--unlink" then
      unlink_mode = true
    elseif arg[i] == "--mock-brew" then
      mock_brew = true
    elseif arg[i] == "--mock-wget" then
      mock_wget = true
    elseif arg[i] == "--mock-defaults" then
      mock_defaults = true
    elseif arg[i] == "--defaults-export" then
      defaults_export = true
    elseif arg[i] == "--defaults-import" then
      defaults_import = true
    elseif arg[i] == "--hooks" then
      hooks_mode = true
    elseif arg[i] == "--remove-profile" then
      remove_profile = true
    elseif arg[i] == "-h" then
      print [[
Usage: dot [options] [module/profile]

Options:
  -f                Force mode: replace existing configurations, backing them up to <config>.before-dot
  --version         Display the version of dot
  --purge           Purge mode: uninstall dependencies and remove configurations
  --unlink          Unlink mode: remove symlinks but keep the config files in their destination
  --mock-brew       Mock brew operations (for testing purposes)
  --mock-wget       Mock wget operations (for testing purposes)
  --mock-defaults   Mock defaults operations (for testing purposes)
  --defaults-export Save app preferences to a plist file
  --defaults-import Import app preferences from a plist file
  --hooks           Run hooks even if dependencies haven't changed
  --remove-profile  Remove the last used profile
  -h                Display this help message
]]
      os.exit(0)
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
    mock_wget = mock_wget,
    mock_defaults = mock_defaults,
    defaults_export = defaults_export,
    defaults_import = defaults_import,
    hooks_mode = hooks_mode,
    remove_profile = remove_profile,
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
  cyan = "\27[36m",
}

local function print_section(message)
  print(colors.bold .. colors.blue .. "[" .. message .. "]" .. colors.reset)
end

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
    color, symbol = colors.reset, ">"
  end

  print(color .. symbol .. " " .. message .. colors.reset)
end

local installed_brew_packages = {}

-- Execute an OS command and return exit code and output
local function execute(cmd)
  -- Special handling for macOS-specific commands when mocking is enabled
  if MOCK_DEFAULTS then
    -- Handle defaults export command
    if cmd:match "^defaults export" then
      local app = cmd:match 'defaults export "([^"]+)"'
      local output_file = cmd:match 'defaults export "[^"]+" "([^"]+)"'

      -- Also match plutil command pattern that often follows defaults export
      if not output_file and cmd:match "plutil" then
        output_file = cmd:match 'plutil .-o "([^"]+)"'
      end

      if output_file then
        -- Ensure the parent directory exists
        local parent_dir = output_file:match "(.+)/[^/]*$"
        if parent_dir then
          -- Create parent directory directly instead of calling ensure_parent_directory
          os.execute('mkdir -p "' .. parent_dir .. '"')
        end

        local file = io.open(output_file, "w")
        if file then
          if output_file:match "%.xml$" or cmd:match "xml1" then
            -- XML format
            file:write [[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>MockedKey</key>
  <string>mocked preferences</string>
</dict>
</plist>]]
          else
            -- Binary or other format
            file:write "mocked preferences"
          end
          file:close()
          return 0, ""
        end
      end
      return 0, ""
    end

    -- Handle defaults import command
    if cmd:match "^defaults import" then
      return 0, ""
    end

    -- Handle plutil command on its own
    if cmd:match "^plutil" then
      -- If there's an output file specified
      local output_file = cmd:match '-o "([^"]+)"' or cmd:match "-o ([^ ]+)"
      if output_file and output_file ~= "-" then
        -- Ensure the parent directory exists
        local parent_dir = output_file:match "(.+)/[^/]*$"
        if parent_dir then
          -- Create parent directory directly instead of calling ensure_parent_directory
          os.execute('mkdir -p "' .. parent_dir .. '"')
        end

        local file = io.open(output_file, "w")
        if file then
          if output_file:match "%.xml$" or cmd:match "xml1" then
            -- XML format
            file:write [[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>MockedKey</key>
  <string>mocked preferences</string>
</dict>
</plist>]]
          else
            -- Binary format
            file:write "mocked binary plist"
          end
          file:close()
        end
      end
      return 0, ""
    end
  end

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
      print_message("error", "Failed to get list of installed brew packages")
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

-- Process wget dependencies
local function process_wget(config)
  if not config.wget then
    return false
  end

  local wget_entries = type(config.wget) == "table" and config.wget[1] and config.wget or { config.wget }
  local dependencies_changed = false

  for _, wget_entry in ipairs(wget_entries) do
    local url = wget_entry.url
    local output = expand_path(wget_entry.output)
    local is_zip = wget_entry.zip == true

    -- Check if the output already exists
    if is_file(output) or is_dir(output) then
      -- print_message("info", "wget → dependency already exists at " .. output)
    else
      dependencies_changed = true
      -- Create a temporary directory for downloading
      local temp_dir = "/tmp/dot_wget_temp"
      local mkdir_cmd = string.format('mkdir -p "%s"', temp_dir)
      local exit_code, mkdir_output = execute(mkdir_cmd)
      if exit_code ~= 0 then
        print_message("error", "wget → failed to create temporary directory: " .. mkdir_output)
        return false
      end

      -- Extract the file name from the output path
      local file_name = output:match "^.+/(.+)$"
      if not file_name then
        print_message("error", "wget → failed to extract file name from output path")
        return false
      end

      -- Mock wget if MOCK_WGET is true
      if MOCK_WGET then
        print_message("info", "wget → mock download to " .. temp_dir .. "/" .. file_name)
        local mock_file_path = temp_dir .. "/" .. file_name
        -- Simulate the presence of files in the temp directory
        local touch_cmd = string.format('touch "%s"', mock_file_path)
        execute(touch_cmd)
      else
        -- Download the file using wget to the temporary directory
        local temp_file = temp_dir .. "/" .. file_name .. (is_zip and ".zip" or "")
        local download_cmd = string.format('wget -O "%s" "%s"', temp_file, url)
        exit_code, download_output = execute(download_cmd)
        if exit_code ~= 0 then
          print_message("error", "wget → failed to download: " .. download_output)
          return false
        end
        print_message("success", "wget →  to " .. temp_file)

        -- If the file is a zip, unzip it
        if is_zip then
          local unzip_cmd = string.format('unzip -o "%s" -d "%s"', temp_file, temp_dir)
          exit_code, unzip_output = execute(unzip_cmd)
          if exit_code ~= 0 then
            print_message("error", "wget → failed to unzip: " .. unzip_output)
            return false
          end

          -- Remove the zip file
          local remove_cmd = string.format('rm "%s"', temp_file)
          exit_code, remove_output = execute(remove_cmd)
          if exit_code ~= 0 then
            print_message("error", "wget → failed to remove zip file: " .. remove_output)
            return false
          end
        end
      end

      -- Move the contents to the output directory
      local move_cmd = string.format('mv "%s" "%s"', temp_dir .. "/" .. file_name, output)
      local exit_code, move_output = execute(move_cmd)
      if exit_code ~= 0 then
        print_message("error", "wget → failed to move files to output: " .. move_output)
        return false
      end
      print_message("success", "wget → installed file at " .. output)

      -- Clean up the temporary directory
      local cleanup_cmd = string.format('rm -rf "%s"', temp_dir)
      execute(cleanup_cmd)
    end
  end

  return dependencies_changed
end

-- Compare two files and return true if they are the same, otherwise print differences
local function files_are_equal(file1, file2)
  -- Use diff with unified format (-U1) to show 1 line of context before and after each change
  local cmd = string.format('diff -U1 "%s" "%s"', file1, file2)
  local exit_code, output = execute(cmd)
  if exit_code == 0 then
    return true
  else
    return false, output
  end
end

function os_name()
  local osname
  -- ask LuaJIT first
  if jit then
    return jit.os
  end

  -- Unix, Linux variants
  local fh, err = assert(io.popen("uname -o 2>/dev/null || uname -s", "r"))
  if fh then
    osname = fh:read()
    fh:close()
  end

  return osname or "Windows"
end

local OS_NAME = os_name()

local function is_macos()
  return OS_NAME == "Darwin"
end

local function is_linux()
  return OS_NAME == "Linux" or OS_NAME == "GNU/Linux"
end

-- Format and display differences between plist files
local function format_plist_diff(diff_output)
  if not diff_output then
    return
  end

  local indent = "  "
  print ""

  -- Use a simpler approach by directly parsing the formatted diff lines
  local lines = {}
  for line in diff_output:gmatch "[^\r\n]+" do
    table.insert(lines, line)
  end

  local settings_found = 0

  for i = 1, #lines - 2 do
    -- Look for patterns that indicate a key and changed values
    if lines[i]:match "<key>([^<]+)</key>" and lines[i + 1]:match "^%-" and lines[i + 2]:match "^%+" then

      local key = lines[i]:match "<key>([^<]+)</key>"
      local app_line = lines[i + 1]
      local saved_line = lines[i + 2]

      -- Extract values
      local app_value = app_line:gsub("^%- +", "")
      local saved_value = saved_line:gsub("^%+ +", "")

      -- Extract content from XML tags
      local app_content = app_value:match "<[^>]+>([^<]*)</" or app_value:match "<([^/]+)/>" or app_value
      local saved_content = saved_value:match "<[^>]+>([^<]*)</" or saved_value:match "<([^/]+)/>" or saved_value

      print(colors.cyan .. indent .. key .. ":" .. colors.reset)
      print(colors.red .. indent .. "App: " .. app_content .. colors.reset)
      print(colors.green .. indent .. "Dotfiles: " .. saved_content .. colors.reset)

      settings_found = settings_found + 1
    end
  end

  if settings_found == 0 then
    -- If parsing failed, show the standard diff
    print_message("info", "Differences between current app preferences and saved dotfiles:")
    for line in diff_output:gmatch "[^\r\n]+" do
      if line:match "^@@" then
        print(colors.blue .. indent .. line .. colors.reset)
      elseif line:match "^%-%-%-" or line:match "^%+%+%+" then
        -- Skip file headers
      elseif line:match "^%-" and not line:match "^%-%-%-" then
        print(colors.red .. indent .. line .. colors.reset)
      elseif line:match "^%+" and not line:match "^%+%+%+" then
        print(colors.green .. indent .. line .. colors.reset)
      else
        print(colors.cyan .. indent .. line .. colors.reset)
      end
    end
  end

  return settings_found > 0
end

-- Process defaults configurations
local function process_defaults(config, module_dir, options)
  if not config.defaults then
    return false
  end

  -- Only run on macOS unless mocking is enabled
  -- When mocking, we'll create the necessary files regardless of OS
  if not is_macos() and not MOCK_DEFAULTS then
    return false
  end

  local defaults_entries = type(config.defaults) == "table" and config.defaults[1] and config.defaults
    or { config.defaults }
  local defaults_changed = false

  for _, defaults_entry in ipairs(defaults_entries) do
    local plist = defaults_entry.plist
    local app = defaults_entry.app

    if plist and app then
      -- Resolve plist path relative to the module directory
      local resolved_plist = os.getenv "PWD" .. "/" .. module_dir:gsub("^./", "") .. "/" .. plist:gsub("^./", "")
      local tmp_file = os.tmpname()

      -- Export current preferences to a temporary file in XML format for better readability
      local export_cmd
      if plist:match "%.xml$" then
        -- Use XML format for better readability
        export_cmd = string.format('defaults export "%s" - | plutil -convert xml1 -o "%s" -', app, tmp_file)
      else
        -- Default to binary plist
        export_cmd = string.format('defaults export "%s" "%s"', app, tmp_file)
      end

      local exit_code, export_output = execute(export_cmd)
      if exit_code ~= 0 then
        print_message("error", "defaults → could not export preferences for app `" .. app .. "`: " .. export_output)
        os.remove(tmp_file)
        return false
      end

      -- Check if resolved_plist exists
      if not is_file(resolved_plist) then
        -- If resolved_plist does not exist, export current preferences to it
        local move_cmd = string.format('mv "%s" "%s"', tmp_file, resolved_plist)
        local exit_code, move_output = execute(move_cmd)
        if exit_code == 0 then
          print_message(
            "success",
            "exported current preferences for `" .. app .. "` to dotfiles as `" .. resolved_plist .. "` did not exist"
          )
        else
          print_message("error", "defaults → failed to export preferences: " .. move_output)
        end
      else
        -- Compare the exported preferences with the module's plist
        if not options.defaults_export and not options.defaults_import then
          local files_equal, diff_output = files_are_equal(tmp_file, resolved_plist)
          if files_equal then
            -- print_message("info", "defaults → preferences for `" .. app .. "` are already up-to-date")
          else
            local module_dir_relative = module_dir:gsub("^modules/", "")
            print_message(
              "warning",
              "preferences for `" .. app .. "` differ between the app and the dotfiles. Choose which one matters using:"
            )
            print_message("log", "dot --defaults-export " .. module_dir_relative .. " # choose app preferences")
            print_message("log", "dot --defaults-import " .. module_dir_relative .. " # choose dotfiles preferences")

            -- Display a formatted diff
            format_plist_diff(diff_output)
          end
        end

        -- Handle --defaults-export option
        if options.defaults_export then
          local move_cmd = string.format('mv "%s" "%s"', tmp_file, resolved_plist)
          local exit_code, move_output = execute(move_cmd)
          if exit_code == 0 then
            print_message("success", "defaults → exported current preferences for `" .. app .. "` to dotfiles")
          else
            print_message("error", "defaults → failed to export preferences: " .. move_output)
          end
        end

        -- Handle --defaults-import option
        if options.defaults_import then
          -- Import the preferences from the plist file
          local import_cmd
          if plist:match "%.xml$" then
            -- For XML, convert back to binary format for import
            import_cmd =
              string.format('plutil -convert binary1 -o - "%s" | defaults import "%s" -', resolved_plist, app)
          else
            import_cmd = string.format('defaults import "%s" "%s"', app, resolved_plist)
          end
          
          local exit_code, import_output = execute(import_cmd)
          if exit_code == 0 then
            print_message("success", "defaults → imported preferences for `" .. app .. "` from dotfiles")
            defaults_changed = true
          else
            print_message("error", "defaults → could not import preferences: " .. import_output)
          end
        end
      end

      os.remove(tmp_file)
    else
      print_message("error", "defaults → missing plist or app in entry")
    end
  end

  return defaults_changed
end

-- Process each module by installing/uninstalling dependencies and managing symlinks
local function process_module(module_name, options)
  print_section(module_name)

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

  -- Check if the module has OS restrictions
  if config.os then
    local current_os = OS_NAME:lower()
    local os_supported = false
    
    for _, os_name in ipairs(config.os) do
      local normalized_os = os_name:lower()
      
      if (normalized_os == "mac" or normalized_os == "macos" or normalized_os == "darwin") and is_macos() then
        os_supported = true
        break
      elseif normalized_os == "linux" and is_linux() then
        os_supported = true
        break
      elseif normalized_os == "windows" and OS_NAME:lower():match("windows") then
        os_supported = true
        break
      end
    end
    
    if not os_supported then
      print_message("info", "Skipping module: not supported on " .. OS_NAME)
      return
    end
  end

  local dependencies_changed = false
  if process_wget(config) then
    dependencies_changed = true
  end

  if process_brew_dependencies(config, options.purge_mode) then
    dependencies_changed = true
  end

  if process_defaults(config, module_dir, options) then
    dependencies_changed = true
  end

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
      print_message("error", "Error loading profile: " .. load_err)
      return
    end

    local success, profile = pcall(profile_func)
    if not success or not profile or not profile.modules then
      print_message("error", "Error executing profile or invalid profile structure")
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
      print_message("error", "Module not found: " .. tool_name)
    end
  end
end

local function save_last_profile(profile_name)
  local file_path = ".git/dot"
  if not is_dir ".git" then
    file_path = ".dot"
  end
  local file = io.open(file_path, "w")
  if file then
    file:write(profile_name)
    file:close()
  end
end

local function get_last_profile()
  local file_path = ".git/dot"
  if not is_dir ".git" then
    file_path = ".dot"
  end
  local file = io.open(file_path, "r")
  if file then
    local profile_name = file:read "*a"
    file:close()
    return profile_name:match "^%s*(.-)%s*$" -- Trim whitespace
  end
  return nil
end

local function remove_last_profile()
  local file_path = ".git/dot"
  if not is_dir ".git" then
    file_path = ".dot"
  end
  if is_file(file_path) then
    local success, err = os.remove(file_path)
    if not success then
      print_message("error", "Failed to remove profile: " .. err)
      return false
    end
    return true
  end
  return true
end

-- Main function
local function main()
  local options = parse_args()

  if options.mock_brew then
    MOCK_BREW = true
  end

  if options.mock_wget then
    MOCK_WGET = true
  end

  if options.mock_defaults then
    MOCK_DEFAULTS = true
  end

  get_installed_brew_packages()

  if options.remove_profile then
    remove_last_profile()
    print_message("info", "Profile removed.")
    return
  end

  local tool_name = options.args[1]

  if not tool_name then
    tool_name = get_last_profile()
    if tool_name then
      print_section("using profile " .. tool_name)
      print_message("log", "dot <another-profile> # use another profile")
      print_message("log", "dot --remove-profile  # remove the current profile")
    end
  else
    local profile_path = os.getenv "PWD" .. "/profiles/" .. tool_name .. ".lua"
    if is_file(profile_path) then
      save_last_profile(tool_name)
    end
  end

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
