#!/usr/bin/env lua

local version = "1.0.0"

-- Parse command-line arguments
local function parse_args()
  local force_mode = false
  local unlink_mode = false
  local postinstall_mode = false
  local postlink_mode = false
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
    elseif arg[i] == "--unlink" then
      unlink_mode = true
    elseif arg[i] == "--defaults-export" then
      defaults_export = true
    elseif arg[i] == "-e" then
      defaults_export = true
    elseif arg[i] == "--defaults-import" then
      defaults_import = true
    elseif arg[i] == "-i" then
      defaults_import = true
    elseif arg[i] == "--postinstall" then
      postinstall_mode = true
    elseif arg[i] == "--postlink" then
      postlink_mode = true
    elseif arg[i] == "--remove-profile" then
      remove_profile = true
    elseif arg[i] == "-h" then
      print [[
Usage: dot [options] [module/profile]

Options:
  -f                Force mode: replace existing configurations, backing them up to <config>.before-dot
  --version         Display the version of dot

  --unlink          Unlink mode: remove symlinks but keep the config files in their destination
  -e                ↙ Short for --defaults-export
  --defaults-export Save app preferences to a plist file
  -i                ↙ Short for --defaults-import
  --defaults-import Import app preferences from a plist file
  --postinstall     Run postinstall hooks even if dependencies haven't changed
  --postlink        Run postlink hooks even if symlinks haven't changed
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

    unlink_mode = unlink_mode,
    defaults_export = defaults_export,
    defaults_import = defaults_import,
    postinstall_mode = postinstall_mode,
    postlink_mode = postlink_mode,
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
  elseif message_type == "log" then
    color, symbol = colors.cyan, ">"
  else
    color, symbol = colors.reset, ">"
  end

  print(color .. symbol .. " " .. message .. colors.reset)
end

-- Execute an OS command and return exit code and output
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
  local output = table.concat(lines, "\n")

  -- Show output transparently if there's any (but filter out debug info and brew output)
  if
    output ~= ""
    and not cmd:match "^test "
    and not cmd:match "^which "
    and not cmd:match "^wc "
    and not cmd:match "^du "
    and not cmd:match "brew "
    and not cmd:match "Warning:"
    and not cmd:match "==>"
    and not cmd:match "🍺"
    and not cmd:match "Error:"
    and not cmd:match "chown:"
    and not cmd:match "installer:"
    and not cmd:match "sudo:"
    and not cmd:match "Please enter"
  then
    print(output)
  end

  return exit_code, output
end

-- Expand '~' to the user's home directory in the given path
local function expand_path(path)
  if path:sub(1, 1) == "~" then
    return os.getenv "HOME" .. path:sub(2)
  elseif path:sub(1, 5) == "$HOME" then
    return os.getenv "HOME" .. path:sub(6)
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
    -- Just check if the symlink points to the source
    return link_target == source
  end
  return false
end

-- Check if a command exists
local function command_exists(cmd)
  local exit_code, _ = execute(string.format('which "%s" >/dev/null 2>&1', cmd))
  return exit_code == 0
end

-- OS detection functions
local function os_name()
  local handle = io.popen "uname"
  local result = handle:read "*l"
  handle:close()
  return result or "Unknown"
end

local OS_NAME = os_name()

local function is_macos()
  return OS_NAME == "Darwin"
end

local function is_linux()
  return OS_NAME == "Linux" or OS_NAME == "GNU/Linux"
end

-- File operation functions
local function ensure_parent_directory(path)
  local parent = path:match "(.+)/[^/]*$"
  if parent then
    local cmd = string.format('mkdir -p "%s"', parent)
    local exit_code, output = execute(cmd)
    if exit_code ~= 0 then
      return false, "Failed to create parent directory: " .. output
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
  -- Find all dot.lua files in any subdirectory
  local cmd = 'find . -type f -name "dot.lua" -not -path "./dot.lua"'
  local exit_code, output = execute(cmd)
  if exit_code == 0 then
    -- First pass: collect all dot.lua files
    local all_init_files = {}
    for file in output:gmatch "[^\n]+" do
      table.insert(all_init_files, file)
    end

    -- Sort dot.lua files by path length (shortest first) to ensure parent modules are processed first
    table.sort(all_init_files, function(a, b)
      return #a < #b
    end)

    -- Track which directories already have a parent module
    local has_parent_module = {}

    for _, file in ipairs(all_init_files) do
      -- Extract the module path relative to current directory (remove ./ prefix)
      local module_path = file:match "^%./(.+)/dot%.lua$"
      if module_path then
        local is_nested = false

        -- Check if any parent directory already has dot.lua
        local path_parts = {}
        for part in module_path:gmatch "[^/]+" do
          table.insert(path_parts, part)
        end

        -- Build paths from root to check for parent modules
        local current_path = ""
        for i = 1, #path_parts - 1 do
          if current_path ~= "" then
            current_path = current_path .. "/"
          end
          current_path = current_path .. path_parts[i]

          if has_parent_module[current_path] then
            is_nested = true
            break
          end
        end

        if not is_nested then
          -- This is a top-level module or one without parent modules
          local module_name = module_path
          table.insert(modules, module_name)

          -- Mark this path as having a module
          has_parent_module[module_name] = true
        end
      end
    end
  end
  return modules
end

-- Fuzzy find modules
local function find_modules_fuzzy(query)
  local all_modules = get_all_modules()
  local matches = {}

  -- First, try exact match
  for _, module in ipairs(all_modules) do
    if module == query then
      return { module }
    end
  end

  -- Then try partial matches
  for _, module in ipairs(all_modules) do
    if module:find(query, 1, true) then
      table.insert(matches, module)
    end
  end

  -- If no direct substring matches, try fuzzy matching
  if #matches == 0 then
    for _, module in ipairs(all_modules) do
      local module_parts = {}
      for part in module:gmatch "[^/]+" do
        table.insert(module_parts, part)
      end

      -- Check if query matches any part of the module path
      for _, part in ipairs(module_parts) do
        if part:find(query, 1, true) then
          table.insert(matches, module)
          break
        end
      end
    end
  end

  return matches
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
      return false
    end
  end
  print_message("success", hook_type .. " → completed successfully")
  return true
end

-- Process new install system
local function process_install(config)
  if not config.install then
    return false
  end

  local install_happened = false

  -- Check if tool is already installed (if check field is provided)
  if config.check then
    local exit_code, _ = execute(config.check .. " >/dev/null 2>&1")
    if exit_code == 0 then
      print_message("info", "install → already installed")
      return false
    end
  end

  -- Find the first available command and run it
  for cmd_name, cmd_line in pairs(config.install) do
    if command_exists(cmd_name) then
      print_message("info", "install → using " .. cmd_name)

      -- Handle multi-line commands
      local cmd_lines = str_split(cmd_line, "\n")
      cmd_lines = table_remove_empty(cmd_lines)

      local all_succeeded = true
      for _, line in ipairs(cmd_lines) do
        local trimmed_line = str_trim(line)
        if trimmed_line ~= "" then
          local exit_code, output = execute(trimmed_line)
          if exit_code ~= 0 then
            print_message("error", "install → failed: " .. (output or "unknown error"))
            all_succeeded = false
            break
          end
        end
      end

      if all_succeeded then
        print_message("success", "install → completed")
        install_happened = true
      end
      break -- Only use the first available package manager
    end
  end

  if not install_happened then
    local available_cmds = {}
    for cmd_name, _ in pairs(config.install) do
      table.insert(available_cmds, cmd_name)
    end
    print_message("warning", "install → no available commands from: " .. table.concat(available_cmds, ", "))
  end

  return install_happened
end

-- Process macOS defaults
local function process_defaults(config, options)
  if not config.defaults then
    return false
  end

  -- Only process defaults on macOS
  if not is_macos() then
    print_message("warning", "defaults → skipping (only available on macOS)")
    return false
  end

  local defaults_processed = false

  for app_id, plist_path in pairs(config.defaults) do
    -- Handle both old format (table with plist/app keys) and new format (app_id = plist_path)
    local actual_app_id = app_id
    local actual_plist_path = plist_path

    if type(plist_path) == "table" and plist_path.plist and plist_path.app then
      -- Old format: { plist = "./file.xml", app = "com.example.app" }
      actual_app_id = plist_path.app
      actual_plist_path = plist_path.plist
    end

    -- Make relative paths relative to current working directory
    local full_plist_path = actual_plist_path or ""
    if actual_plist_path and full_plist_path ~= "" and not full_plist_path:match "^/" then
      full_plist_path = os.getenv "PWD" .. "/" .. full_plist_path:gsub("^./", "")
    end

    if not full_plist_path or full_plist_path == "" then
      print_message("error", "defaults → invalid plist path for " .. actual_app_id)
      goto continue
    end

    if options.defaults_export then
      -- Export defaults to plist file
      print_message("info", "defaults → exporting " .. actual_app_id .. " to " .. full_plist_path)

      -- Ensure parent directory exists
      local success, err = ensure_parent_directory(full_plist_path)
      if not success then
        print_message("error", "defaults → " .. err)
        goto continue
      end

      -- Determine output format based on file extension
      local format_flag = ""
      if full_plist_path and full_plist_path:match "%.xml$" then
        format_flag = " -format xml1"
      end

      local export_cmd = string.format('defaults export "%s" "%s"%s', actual_app_id, full_plist_path, format_flag)
      local exit_code, output = execute(export_cmd)

      if exit_code == 0 then
        print_message("success", "defaults → exported " .. actual_app_id)
        defaults_processed = true
      else
        print_message("error", "defaults → export failed: " .. (output or "unknown error"))
      end
    elseif options.defaults_import then
      -- Import defaults from plist file
      if not is_file(full_plist_path) then
        print_message("error", "defaults → plist file not found: " .. full_plist_path)
        goto continue
      end

      print_message("info", "defaults → importing " .. actual_app_id .. " from " .. full_plist_path)

      local import_cmd = string.format('defaults import "%s" "%s"', actual_app_id, full_plist_path)
      local exit_code, output = execute(import_cmd)

      if exit_code == 0 then
        print_message("success", "defaults → imported " .. actual_app_id)
        defaults_processed = true
      else
        print_message("error", "defaults → import failed: " .. (output or "unknown error"))
      end
    else
      -- Regular processing (import during normal dot run)
      if is_file(full_plist_path) then
        print_message("info", "defaults → importing " .. actual_app_id .. " from " .. full_plist_path)

        local import_cmd = string.format('defaults import "%s" "%s"', actual_app_id, full_plist_path)
        local exit_code, output = execute(import_cmd)

        if exit_code == 0 then
          print_message("success", "defaults → imported " .. actual_app_id)
          defaults_processed = true
        else
          print_message("error", "defaults → import failed: " .. (output or "unknown error"))
        end
      else
        print_message("warning", "defaults → plist file not found: " .. full_plist_path .. " (use -e to export)")
      end
    end

    ::continue::
  end

  return defaults_processed
end

-- Handle new link system
local function handle_links(config, module_dir, options)
  if not config.link then
    return false
  end

  local link_happened = false
  local all_links_correct = true

  for source_rel, output_pattern in pairs(config.link) do
    local source = os.getenv "PWD" .. "/" .. module_dir:gsub("^./", "") .. "/" .. source_rel:gsub("^./", "")
    local output = expand_path(output_pattern)
    local attr = get_file_info(output)

    if options.unlink_mode then
      -- Remove symlink and copy source to output
      if attr and attr.is_symlink then
        local success, err = delete_path(output)
        if success then
          print_message("success", "link → symlink removed")

          -- Ensure parent directory exists
          local success, err = ensure_parent_directory(output)
          if not success then
            print_message("error", "link → " .. err)
            return false
          end

          -- Copy source to output
          local success, err = copy_path(source, output)
          if success then
            print_message("success", "link → copied " .. source_rel .. " to " .. output_pattern)
          else
            print_message("error", "link → " .. err)
          end
        else
          print_message("error", "link → failed to remove symlink: " .. err)
        end
      else
        print_message("info", "link → " .. output .. " is not a symlink or does not exist")
      end
    else
      -- Normal installation: create symlink
      if is_symlink_correct(source, output) then
        -- Link is already correct, do nothing (minimal output)
      else
        all_links_correct = false
        if attr then
          if options.force_mode then
            local success, result = create_backup(output)
            if success then
              print_message("warning", "link → existing config backed up to " .. result)
            else
              print_message("error", "link → " .. result)
              return false
            end
          else
            print_message("error", "link → file already exists at " .. output .. ". Use -f to force.")
            return false
          end
        end

        -- Ensure parent directory exists
        local success, err = ensure_parent_directory(output)
        if not success then
          print_message("error", "link → " .. err)
          return false
        end

        local cmd = string.format('ln -sf "%s" "%s"', source, output)
        local exit_code, error_output = execute(cmd)
        if exit_code ~= 0 then
          print_message("error", "link → failed to create symlink: " .. error_output)
        else
          print_message("success", "link → created symlink " .. output_pattern)
          link_happened = true
        end
      end
    end
  end

  if all_links_correct and not options.unlink_mode then
    -- Don't print anything for minimal output when nothing changed
  end

  return link_happened
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

-- Process each module by installing dependencies and managing symlinks
local function process_module(module_name, options)
  print_section(module_name)

  local module_dir = module_name
  local dot_file = module_dir .. "/dot.lua"

  -- Load the dot.lua file
  local config_func, load_err = loadfile(dot_file)
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
      elseif normalized_os == "windows" and OS_NAME:lower():match "windows" then
        os_supported = true
        break
      end
    end

    if not os_supported then
      print_message("info", "Skipping module: not supported on " .. OS_NAME)
      return
    end
  end

  local install_happened = false
  local link_happened = false
  local defaults_happened = false

  -- Process installation
  if process_install(config) then
    install_happened = true
  end

  -- Process links
  if handle_links(config, module_dir, options) then
    link_happened = true
  end

  -- Process defaults
  if process_defaults(config, options) then
    defaults_happened = true
  end

  -- Run new hook system
  if install_happened or options.postinstall_mode then
    if config.postinstall then
      run_hook(config.postinstall, "postinstall")
    end
  end

  if link_happened or options.postlink_mode then
    if not options.unlink_mode and config.postlink then
      run_hook(config.postlink, "postlink")
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
  local profiles_path = "profiles.lua"

  if is_file(profiles_path) then
    -- Load and process the profiles file
    local profiles_func, load_err = loadfile(profiles_path)
    if not profiles_func then
      print_message("error", "Error loading profiles: " .. load_err)
      return false
    end

    local success, profiles = pcall(profiles_func)
    if not success or not profiles then
      print_message("error", "Error executing profiles or invalid profiles structure")
      return false
    end

    -- Check if the requested profile exists
    if not profiles[tool_name] then
      print_message("error", "Profile not found: " .. tool_name)
      print_message("info", "Available profiles:")
      for profile_name, _ in pairs(profiles) do
        print_message("info", "  " .. profile_name)
      end
      return false
    end

    local profile = profiles[tool_name]
    if not profile then
      print_message("error", "Invalid profile structure: profile should be a list of modules")
      return false
    end

    local modules_to_process = {}
    local exclusions = {}

    for _, module_name in ipairs(profile) do
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

    return true
  else
    -- Try fuzzy matching for module
    local matches = find_modules_fuzzy(tool_name)

    if #matches == 1 then
      -- Exact fuzzy match found
      process_module(matches[1], options)
      return true
    elseif #matches > 1 then
      print_message("error", "Multiple modules match '" .. tool_name .. "':")
      for _, match in ipairs(matches) do
        print_message("info", "  " .. match)
      end
      return false
    else
      -- Check for exact module path
      local module_path = tool_name .. "/dot.lua"
      if is_file(module_path) then
        process_module(tool_name, options)
        return true
      else
        print_message("error", "Module not found: " .. tool_name)
        return false
      end
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
    local profiles_path = "profiles.lua"
    if is_file(profiles_path) then
      local profiles_func, load_err = loadfile(profiles_path)
      if profiles_func then
        local success, profiles = pcall(profiles_func)
        if success and profiles and profiles[tool_name] then
          save_last_profile(tool_name)
        end
      end
    end
  end

  local success = true

  if tool_name then
    success = process_tool(tool_name, options)
    if success == false then
      os.exit(1)
    end
  else
    local modules = get_all_modules()
    if #modules == 0 then
      print_message("error", "no modules found")
      os.exit(1)
    end

    for _, module_name in ipairs(modules) do
      process_module(module_name, options)
    end
  end
end

main()
