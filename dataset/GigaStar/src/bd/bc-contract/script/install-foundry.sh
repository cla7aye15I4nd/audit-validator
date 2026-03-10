#!/usr/bin/env bash
set -e
set -u
set -x

source "./script/base.sh" # Setup log funcs, OS, etc

# Ensure gh CLI is installed
function require_gh_attestation() {
    if command -v gh &> /dev/null; then
        return; # Installed
    fi

    # Not installed, from https://cli.github.com/
    log "'gh' (GitHub CLI) is not installed, installing ..."
    if [[ $OS == "mac" ]]; then
        brew install gh
    else # ubuntu
        TEMP_DIR=$(mktemp -d)
        pushd $TEMP_DIR >/dev/null 2>&1

        GH_VER=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | jq -r .tag_name)
        curl -LO "https://github.com/cli/cli/releases/download/$GH_VER/gh_${GH_VER#v}_${OS}_${ARCH}.tar.gz"
        tar -xzf gh_*.tar.gz
        sudo mv gh_*/bin/gh /usr/local/bin/

        popd >/dev/null 2>&1
        rm -rf $TEMP_DIR
    fi
    if ! command -v gh &> /dev/null; then
        fatal "'gh' (GitHub CLI) not found after install, try re-running this script"
    fi
    log "Using 'gh'"
    gh version
}

# Ensure genhtml is installed, if not install the lcov package
function require_genhtml() {
    if command -v genhtml &> /dev/null; then
        return; # Installed
    fi
    log "'genhtml' is not installed, installing lcov package ..."
    if [[ $OS == "mac" ]]; then
        brew install lcov
    else # ubuntu
        sudo apt install lcov
    fi
    log "'lcov' installed"
    lcov --version
    genhtml --version
}

function setup_config() {
    REPO="foundry-rs/foundry"
    VERSION="v1.3.6"    # Pinned
    # VERSION="nightly" # Latest
    if [ "${OS}" == "mac" ]; then
        OS=darwin
    fi
    TARBALL="foundry_${VERSION}_${OS}_${ARCH}.tar.gz"
    INSTALL_DIR="$HOME/.local/bin"
}

function exit_if_installed() {
    INSTALLED_VERSION=$(forge --version 2>/dev/null || echo "")
    if [[ "$INSTALLED_VERSION" == *"$VERSION"* ]]; then
        log "Foundry $VERSION already installed"
    fi
}

function check_path() {
    # Ensure INSTALL_DIR is in PATH
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        log "Adding $INSTALL_DIR to PATH in $BASH_CONFIG"
        log "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$BASH_CONFIG"
        log "Please restart your shell or run: source $BASH_CONFIG"
    else
        log "$INSTALL_DIR is already in PATH"
    fi
}

# Install via 'foundryup', cleaner but less transparent - maybe better but untested
function do_install_foundryup() {
    TEMP_DIR=$(mktemp -d)
    pushd $TEMP_DIR >/dev/null 2>&1

    URL=https://foundry.paradigm.xyz
    log "Downloading Foundry version \"$VERSION\" via $URL ..."
    curl -L $URL | bash

    log "Downloaded, installing $VERSION ..."
    source ~/.bashrc
    foundryup --version $VERSION

    popd >/dev/null 2>&1
    rm -rf $TEMP_DIR

    log "Installed Foundry $VERSION"
}

# Install from a tar file specific to the environment
function do_install_tar() {
    log "Installing Foundry $VERSION"

    TEMP_DIR=$(mktemp -d)
    pushd $TEMP_DIR >/dev/null 2>&1

    # Download Foundry tarball
    FILE="https://github.com/$REPO/releases/download/$VERSION/$TARBALL"
    log "Downloading Foundry version \"$VERSION\" via $FILE ..."
    curl -LO "$FILE"

    # Extract to a temp dir
    log "Extracting $TARBALL ..."
    tar -xzf "$TARBALL"

    # Create install directory if needed
    mkdir -p "$INSTALL_DIR"

    # Verify and install each binary
    for BIN in forge cast anvil; do
        log "Verifying $BIN ..."
        gh attestation verify "$BIN" --repo "$REPO"

        log "Installing $BIN to $INSTALL_DIR"
        chmod +x "$BIN"
        mv "$BIN" "$INSTALL_DIR/"
    done

    popd >/dev/null 2>&1
    rm -rf $TEMP_DIR

    check_path

    forge install foundry-rs/forge-std

    log "Installed Foundry $VERSION"
}

function main() {
    setup_config
    exit_if_installed
    require_genhtml
    require_gh_attestation
    do_install_tar
    #do_install_foundryup
}

main $@
