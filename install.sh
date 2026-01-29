#!/bin/bash

set -e

REPO="gabrielmfern/shot"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="shot-tui"

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        *)
            echo "Unsupported OS: $(uname -s)" >&2
            exit 1
            ;;
    esac
}

# Get the latest release tag from GitHub
get_latest_release() {
    curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# Download the binary
download_binary() {
    local os="$1"
    local version="$2"
    local url="https://github.com/${REPO}/releases/download/${version}/${BINARY_NAME}-${os}"
    local tmp_file="/tmp/${BINARY_NAME}"

    echo "Downloading ${BINARY_NAME} ${version} for ${os}..."
    curl -fSL "$url" -o "$tmp_file"
    chmod +x "$tmp_file"

    echo "Installing to ${INSTALL_DIR}/${BINARY_NAME}..."
    if [ -w "$INSTALL_DIR" ]; then
        mv "$tmp_file" "${INSTALL_DIR}/${BINARY_NAME}"
    else
        sudo mv "$tmp_file" "${INSTALL_DIR}/${BINARY_NAME}"
    fi

    echo "Binary installed successfully!"
}

# Shell function to add
SHELL_FUNCTION_BASH='
# shot - quick try directory manager
shot() {
  local cmd
  cmd="$(/usr/local/bin/shot-tui "$@" 2>/dev/tty)"
  eval "$cmd"
}'

SHELL_FUNCTION_FISH='
# shot - quick try directory manager
function shot
  set -l cmd (/usr/local/bin/shot-tui $argv 2>/dev/tty | string collect)
  eval "$cmd"
end'

# Detect user's shell and configure
configure_shell() {
    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        bash)
            local config_file="$HOME/.bashrc"
            if [ -f "$HOME/.bash_profile" ] && [ "$(uname -s)" = "Darwin" ]; then
                config_file="$HOME/.bash_profile"
            fi
            if ! grep -q "shot-tui" "$config_file" 2>/dev/null; then
                echo "$SHELL_FUNCTION_BASH" >> "$config_file"
                echo "Added shot function to $config_file"
                echo "Run 'source $config_file' or restart your terminal to use shot"
            else
                echo "shot function already exists in $config_file"
            fi
            ;;
        zsh)
            local config_file="$HOME/.zshrc"
            if ! grep -q "shot-tui" "$config_file" 2>/dev/null; then
                echo "$SHELL_FUNCTION_BASH" >> "$config_file"
                echo "Added shot function to $config_file"
                echo "Run 'source $config_file' or restart your terminal to use shot"
            else
                echo "shot function already exists in $config_file"
            fi
            ;;
        fish)
            local config_dir="$HOME/.config/fish/functions"
            local config_file="$config_dir/shot.fish"
            mkdir -p "$config_dir"
            if [ ! -f "$config_file" ]; then
                echo "$SHELL_FUNCTION_FISH" > "$config_file"
                echo "Created $config_file"
                echo "The shot function is now available in new fish shells"
            else
                echo "shot function already exists at $config_file"
            fi
            ;;
        *)
            echo ""
            echo "Unknown shell: $shell_name"
            echo "Please manually add the following to your shell config:"
            echo ""
            echo "For bash/zsh:"
            echo "$SHELL_FUNCTION_BASH"
            echo ""
            echo "For fish:"
            echo "$SHELL_FUNCTION_FISH"
            ;;
    esac
}

main() {
    echo "Installing shot..."
    echo ""

    local os
    os=$(detect_os)

    local version
    version=$(get_latest_release)

    if [ -z "$version" ]; then
        echo "Failed to fetch latest release version" >&2
        exit 1
    fi

    download_binary "$os" "$version"
    echo ""
    configure_shell

    echo ""
    echo "Installation complete!"
}

main
