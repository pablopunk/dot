#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
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

# Detect OS and architecture
detect_os_arch() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $OS in
        darwin)
            OS="darwin"
            ;;
        linux)
            OS="linux"
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
    
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    print_info "Detected OS: $OS, Architecture: $ARCH"
}

# Get the latest release version from GitHub
get_latest_version() {
    print_info "Fetching latest version..."
    
    if command -v curl >/dev/null 2>&1; then
        VERSION=$(curl -s https://api.github.com/repos/pablopunk/dot/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    elif command -v wget >/dev/null 2>&1; then
        VERSION=$(wget -qO- https://api.github.com/repos/pablopunk/dot/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi
    
    if [ -z "$VERSION" ]; then
        print_error "Failed to fetch latest version"
        exit 1
    fi
    
    print_info "Latest version: $VERSION"
}

# Download the binary
download_binary() {
    BINARY_NAME="dot-${OS}-${ARCH}"
    if [ "$OS" = "darwin" ]; then
        BINARY_NAME="dot-${OS}-${ARCH}"
    fi
    
    DOWNLOAD_URL="https://github.com/pablopunk/dot/releases/download/${VERSION}/${BINARY_NAME}"
    
    print_info "Downloading from: $DOWNLOAD_URL"
    
    # Create temporary directory
    TMP_DIR=$(mktemp -d)
    TMP_FILE="${TMP_DIR}/dot"
    
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$TMP_FILE" "$DOWNLOAD_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TMP_FILE" "$DOWNLOAD_URL"
    else
        print_error "Neither curl nor wget is available"
        exit 1
    fi
    
    if [ ! -f "$TMP_FILE" ]; then
        print_error "Failed to download binary"
        exit 1
    fi
    
    print_success "Binary downloaded successfully"
}

# Install the binary
install_binary() {
    # Create ~/.local/bin if it doesn't exist
    LOCAL_BIN="$HOME/.local/bin"
    if [ ! -d "$LOCAL_BIN" ]; then
        print_info "Creating $LOCAL_BIN directory"
        mkdir -p "$LOCAL_BIN"
    fi
    
    # Move binary to ~/.local/bin
    DOT_PATH="$LOCAL_BIN/dot"
    print_info "Installing binary to $DOT_PATH"
    
    mv "$TMP_FILE" "$DOT_PATH"
    chmod +x "$DOT_PATH"
    
    print_success "Binary installed to $DOT_PATH"
}

# Update PATH in shell profile
update_path() {
    LOCAL_BIN="$HOME/.local/bin"
    
    # Check if ~/.local/bin is already in PATH
    if echo "$PATH" | grep -q "$LOCAL_BIN"; then
        print_info "~/.local/bin is already in PATH"
        return
    fi
    
    # Detect shell and update appropriate profile
    SHELL_NAME=$(basename "$SHELL")
    
    case $SHELL_NAME in
        bash)
            PROFILE_FILES=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")
            ;;
        zsh)
            PROFILE_FILES=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.profile")
            ;;
        fish)
            FISH_CONFIG="$HOME/.config/fish/config.fish"
            if [ ! -d "$(dirname "$FISH_CONFIG")" ]; then
                mkdir -p "$(dirname "$FISH_CONFIG")"
            fi
            PROFILE_FILES=("$FISH_CONFIG")
            ;;
        *)
            PROFILE_FILES=("$HOME/.profile")
            ;;
    esac
    
    # Find the first existing profile file or create .profile
    PROFILE_FILE=""
    for file in "${PROFILE_FILES[@]}"; do
        if [ -f "$file" ]; then
            PROFILE_FILE="$file"
            break
        fi
    done
    
    if [ -z "$PROFILE_FILE" ]; then
        PROFILE_FILE="$HOME/.profile"
        print_info "Creating $PROFILE_FILE"
        touch "$PROFILE_FILE"
    fi
    
    # Add PATH export to profile
    print_info "Adding ~/.local/bin to PATH in $PROFILE_FILE"
    
    if [ "$SHELL_NAME" = "fish" ]; then
        echo 'set -gx PATH $HOME/.local/bin $PATH' >> "$PROFILE_FILE"
    else
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE_FILE"
    fi
    
    print_success "Updated PATH in $PROFILE_FILE"
    print_warning "Please restart your shell or run: source $PROFILE_FILE"
}

# Verify installation
verify_installation() {
    DOT_PATH="$HOME/.local/bin/dot"
    
    if [ -x "$DOT_PATH" ]; then
        print_success "Installation verified: $DOT_PATH is executable"
        
        # Try to run the binary
        if "$DOT_PATH" --help >/dev/null 2>&1; then
            print_success "Binary runs successfully"
        else
            print_warning "Binary exists but may not run correctly"
        fi
    else
        print_error "Installation failed: $DOT_PATH is not executable"
        exit 1
    fi
}

# Cleanup
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

# Main installation function
main() {
    print_info "Starting dot installation..."
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    detect_os_arch
    get_latest_version
    download_binary
    install_binary
    update_path
    verify_installation
    
    print_success "dot installation completed successfully!"
    print_info "You can now use 'dot' command (restart your shell first if needed)"
    print_info "For help, run: dot --help"
    print_info "To get started, create a dot.yaml file in your dotfiles directory"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "dot installation script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -h, --help     Show this help message"
            echo "  -v, --verbose  Enable verbose output"
            echo ""
            echo "This script will:"
            echo "  1. Detect your OS and architecture"
            echo "  2. Download the latest dot binary from GitHub"
            echo "  3. Install it to ~/.local/bin/dot"
            echo "  4. Update your shell profile to include ~/.local/bin in PATH"
            echo ""
            echo "Requirements:"
            echo "  - curl or wget"
            echo "  - Internet connection"
            echo ""
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main