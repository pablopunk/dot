#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos";;
        Linux*)     echo "linux";;
        *)          echo "unknown";;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Lua on macOS
install_lua_macos() {
    if command_exists brew; then
        print_status "Installing Lua via Homebrew..."
        brew install lua
    else
        print_error "Homebrew not found. Please install Homebrew first:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
}

# Install Lua on Linux
install_lua_linux() {
    if command_exists apt-get; then
        print_status "Installing Lua via apt..."
        sudo apt-get update
        sudo apt-get install -y lua5.4
    elif command_exists yum; then
        print_status "Installing Lua via yum..."
        sudo yum install -y lua
    elif command_exists dnf; then
        print_status "Installing Lua via dnf..."
        sudo dnf install -y lua
    elif command_exists pacman; then
        print_status "Installing Lua via pacman..."
        sudo pacman -S --noconfirm lua
    elif command_exists zypper; then
        print_status "Installing Lua via zypper..."
        sudo zypper install -y lua
    else
        print_error "No supported package manager found. Please install Lua manually."
        exit 1
    fi
}



# Get version from dot.lua file
get_version_from_file() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        local version_line=$(grep "local version = " "$file_path" 2>/dev/null)
        if [[ -n "$version_line" ]]; then
            echo "$version_line" | sed 's/local version = "\([^"]*\)"/\1/'
        fi
    fi
}

# Get latest version from GitHub
get_latest_version() {
    local version_url="https://raw.githubusercontent.com/pablopunk/dot/main/dot.lua"
    local version_line=$(curl -fsSL "$version_url" 2>/dev/null | grep "local version = " | head -1)
    if [[ -n "$version_line" ]]; then
        echo "$version_line" | sed 's/local version = "\([^"]*\)"/\1/'
    fi
}

# Compare versions
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Convert versions to comparable numbers (e.g., 1.2.3 -> 1002003)
    local v1=$(echo "$version1" | awk -F. '{print $1*1000000 + $2*1000 + $3}')
    local v2=$(echo "$version2" | awk -F. '{print $1*1000000 + $2*1000 + $3}')
    
    if [[ "$v1" -lt "$v2" ]]; then
        echo "older"
    elif [[ "$v1" -gt "$v2" ]]; then
        echo "newer"
    else
        echo "same"
    fi
}

# Install dot tool
install_dot() {
    local os=$(detect_os)
    local install_dir="$HOME/.local/bin"
    local dot_path="$install_dir/dot"
    
    # Create install directory
    mkdir -p "$install_dir"
    
    # Check if dot is already installed
    local current_version=""
    local latest_version=""
    local update_needed=false
    
    if [[ -f "$dot_path" ]]; then
        current_version=$(get_version_from_file "$dot_path")
        latest_version=$(get_latest_version)
        
        if [[ -n "$current_version" && -n "$latest_version" ]]; then
            local comparison=$(version_compare "$current_version" "$latest_version")
            if [[ "$comparison" == "older" ]]; then
                print_status "Current version: $current_version"
                print_status "Latest version: $latest_version"
                print_status "Updating dot tool..."
                update_needed=true
            elif [[ "$comparison" == "same" ]]; then
                print_success "dot tool is already up to date (version $current_version)"
                # Still check PATH and show usage info
            else
                print_warning "Local version ($current_version) is newer than remote ($latest_version)"
                print_warning "This might be a development version"
            fi
        else
            print_status "Installing dot tool..."
            update_needed=true
        fi
    else
        print_status "Installing dot tool..."
        update_needed=true
    fi
    
    # Download/update the dot.lua file
    if [[ "$update_needed" == true ]]; then
        print_status "Downloading dot tool..."
        if command_exists curl; then
            curl -fsSL "https://raw.githubusercontent.com/pablopunk/dot/main/dot.lua" -o "$dot_path"
        elif command_exists wget; then
            wget -qO "$dot_path" "https://raw.githubusercontent.com/pablopunk/dot/main/dot.lua"
        else
            print_error "Neither curl nor wget found. Please install one of them."
            exit 1
        fi
        
        # Make it executable
        chmod +x "$dot_path"
        
        # Get the new version
        local new_version=$(get_version_from_file "$dot_path")
        if [[ -n "$new_version" ]]; then
            print_success "dot tool updated to version $new_version"
        else
            print_success "dot tool installed successfully"
        fi
    fi
    
    # Check if directory is already in PATH
    if [[ ":$PATH:" == *":$install_dir:"* ]]; then
        print_success "PATH already includes $install_dir"
    else
        print_warning "The dot tool is installed to $install_dir"
        print_warning "To use it, either:"
        echo "  1. Add $install_dir to your PATH manually"
        echo "  2. Run the tool directly: $install_dir/dot"
        echo "  3. Create a symlink: ln -s $install_dir/dot /usr/local/bin/dot"
    fi
    
    print_success "dot tool installed to $dot_path"
}

# Main installation process
main() {
    print_status "Starting dot tool installation..."
    
    local os=$(detect_os)
    print_status "Detected OS: $os"
    
    # Check if Lua is installed
    if ! command_exists lua; then
        print_status "Lua not found. Installing Lua..."
        case "$os" in
            macos) install_lua_macos;;
            linux) install_lua_linux;;
            *) print_error "Unsupported OS: $os"; exit 1;;
        esac
    else
        print_success "Lua already installed"
    fi
    
    # Install dot tool
    install_dot
    
    print_success "Installation complete!"
    echo
    print_status "Installation details:"
    echo "  Location: $HOME/.local/bin/dot"
    echo
    print_status "Usage:"
    echo "  $HOME/.local/bin/dot            # Install all modules"
    echo "  $HOME/.local/bin/dot neovim     # Install only the 'neovim' module"
    echo "  $HOME/.local/bin/dot work       # Install only the 'work' profile"
    echo "  $HOME/.local/bin/dot -h         # Show help"
    echo
    print_status "To make 'dot' available as a command, add $HOME/.local/bin to your PATH"
}

# Run main function
main "$@" 