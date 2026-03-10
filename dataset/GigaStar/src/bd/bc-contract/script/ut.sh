#!/usr/bin/env bash
set -e  # exit on error
# set -x  # echo commands

source "./script/base.sh" # Setup log funcs, OS, etc

function run_unit_tests() {
    log "unit tests:"
    START_TIME=$(date +%s)

    TOP_DIR=$(pwd)
    CORE_DIR=./contract # Contracts being tested
    TEST_DIR=./test     # Solidity test contracts for Foundry

    # OPTION 1: Normal flow
    log 'building test contracts concurrently'
    # Build/run test contracts (excluding core contracts from build)
    # The config seems to ignore the 'ir' setting so also passed via CLI
    FOUNDRY_PROFILE=test forge test --via-ir --build-info --skip "$CORE_DIR"/**/*.sol

    # OPTION 2 (sequential) kept in comments in case needed again
    # log 'building test contracts sequentially'
    # for FILE in $(find "$TEST_DIR" -type f -name '*.sol' | egrep -v '/Library|/I[A-Z]|/Mock' | sort); do
    #     if [[ "0" == "$(egrep "^contract " "$FILE" | wc -l)" ]]; then
    #         continue # No contract found, skipping; Likely a library or abstract contract
    #     fi
    #     FOUNDRY_PROFILE=test forge test --via-ir --build-info "$FILE" --skip "$CORE_DIR"/**/*.sol
    # done

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))s
    log "runtime: $ELAPSED "
}

# Run all forge unit tests
function main() {
    NO_BUILD=$(echo $@ | egrep "no-build" | wc -l | sed 's/ //g')
    if [ $NO_BUILD == 0 ]; then
        ./script/build.sh "${@:1}" # Pass all arguments except the first (script name)
    fi

    echo ""
    run_unit_tests "$@"
}

main "$@"
