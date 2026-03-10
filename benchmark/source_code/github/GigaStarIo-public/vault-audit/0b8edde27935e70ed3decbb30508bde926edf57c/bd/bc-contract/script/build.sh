#!/usr/bin/env bash

source "./script/base.sh" # Setup log funcs, OS, etc
# set -x # echo commands

# Clone a library repo into lib/, without bringing any of its submodules,
# and strip git metadata so it behaves like vendored source code
clone_lib() {
    local url="$1"   # eg https://github.com/OpenZeppelin/openzeppelin-contracts.git
    local dest="$2"  # eg lib/openzeppelin-contracts
    local tag="$3"   # Empty=latest, else: tag/branch, eg v5.3.0
    local force="$4" # Boolean whether to remove existing lib dir

    if [[ -d "$dest" ]]; then
        if [ $force == "1" ]; then
            echo "removing existing lib at $dest"
            rm -rf $dest
        else
            # Adding version sensitivity would be better, simple for now, can use 'force' option or remove manually
            echo "lib found, skipping clone: $dest"
            return
        fi
    fi

    log "Cloning $url into $dest (tag: ${tag})"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"

    if [[ -n "$tag" ]]; then
        TAG_SUFFIX=$(echo --branch "$tag")
    else
        TAG_SUFFIX=""
    fi
    git clone -q -c advice.detachedHead=false --depth=1 --recurse-submodules=0 "$url" "$dest" $TAG_SUFFIX

    # Strip git metadata so this is not a submodule and cannot pull nested deps
    rm -rf "$dest/.git" "$dest/.gitmodules"
}

# Clean out nested libs that OZ pulls in when cloned with submodules
sanitize_lib() {
    local dir="$1"

    # Remove embedded git metadata OpenZeppelin ships with
    rm -f  "$dir/.gitmodules"
    rm -rf "$dir/lib/erc4626-tests"
    rm -rf "$dir/lib/forge-std"
    rm -rf "$dir/lib/halmos-cheatcodes"
    rm -rf "$dir/lib/openzeppelin-contracts"

    # In case upgradeable package also contains embedded libs
    rm -f  "$dir/openzeppelin-contracts-upgradeable/.gitmodules"
}

# Remove *all* git-ish metadata from lib/ so forge never treats them as submodules
sanitize_libs() {
    # Kill any nested repos
    find lib -type d -name ".git"          -exec rm -rf {} +
    find lib -type f -name ".gitmodules"   -delete
    find lib -type f -name ".gitattributes" -delete
    find lib -type f -name ".gitignore"    -delete
    find lib -type d -name ".github"       -exec rm -rf {} +
}

# Ensure all required Solidity libs exist in ./lib and are sanitized
# - Libs are downloaded if necessary or conditionally skipped if found/cached
get_libs() {
    log "ensuring libs..."

    # Pin versions here if desired; empty = default branch
    FORGE_STD_TAG="v1.12.0"
    OZ_TAG="v5.5.0"

    # Capture option to force lib downloads
    FORCE=0
    if [[ $(echo "$@" | grep force | wc -l) == 1 ]]; then
        FORCE=1
    fi

    clone_lib "https://github.com/foundry-rs/forge-std.git" \
        "lib/forge-std" \
        "$FORGE_STD_TAG" \
        $FORCE

    clone_lib "https://github.com/OpenZeppelin/openzeppelin-contracts.git" \
        "lib/openzeppelin-contracts" \
        "$OZ_TAG" \
        $FORCE

    clone_lib "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable.git" \
        "lib/openzeppelin-contracts-upgradeable" \
        "$OZ_TAG" \
        $FORCE

    # Remove nested libs / submodule metadata
    sanitize_lib lib/openzeppelin-contracts
    sanitize_lib lib/openzeppelin-contracts-upgradeable
    sanitize_libs

    # Let forge regenerate the lock to avoid edge-cases with: "Missing dependencies found. Installing now..."
    rm -f foundry.lock || true
}

# Build Solidity code via Foundry
function build_sol() {
    log "solidity build..."

    TOP_DIR=$(pwd)      # For debug context
    CORE_DIR=./contract # Contracts being tested
    TEST_DIR=./test     # Solidity test contracts for Foundry

    if [[ $(echo "$@" | grep clean | wc -l) == 1 ]]; then
        forge clean
        rm -rf ./abi/V1_0/ ./cache/ # Previous command should do this, but does not...
    fi

    if [[ $(echo "$@" | grep coverage | wc -l) == 1 ]]; then

        log 'building for coverage'
        mkdir -p doc

        log 'building contracts concurrently'
        FOUNDRY_PROFILE=coverage forge coverage --ir-minimum --report lcov --report-file doc/lcov.info

        # Generate an HTML summary to discover uncovered lines
        genhtml doc/lcov.info --output-directory doc/forge-coverage-html | tail -n3

    else
        log 'building release contracts for size'
        # Build core contracts with release settings for consistent behavior in dev and prod
        # 24 KiB (24,576 bytes) is the max size for CREATE deployment
        # - Cannot add './lib/**/*.sol' to the skip path since ts-vault expects the 'ERC1967Proxy.sol' ABI
        FOUNDRY_PROFILE=release forge build -vvvvv --sizes --build-info -C $CORE_DIR --skip $TEST_DIR/**/*.sol
    fi
}

function main() {
    echo ""

    START_TIME=$(date +%s)
    log "build started with args: $@"

    get_libs $@
    build_sol $@

    ELAPSED=$(($(date +%s) - START_TIME))s
    log "build completed in $ELAPSED"
}

main $@
