# This script helps isolate the cause of solidity stack too deep errors

source "./script/base.sh" # Setup log funcs, OS, etc

# Strategies to help isolate:
# * Run slither: slither . --filter-paths "test" --exclude naming-convention
# * Compile files in isolation (single or groups)
# * Comment out suspected problems

CORE_DIR=contract/v1_0

function do_core_build() {
    log "Building all core contract files in isolation ..."
    for FILE in $CORE_DIR/*.sol; do
        log "Building $FILE"
        FOUNDRY_PROFILE=release \
            forge build -vvvvv --sizes --build-info -C $CORE_DIR --skip ut/*.sol $FILE || break
        echo ""
    done
}

function do_test_build() {
    log "Building all test contract files in isolation ..."
    for FILE in ut/*.sol; do
        log "Building $FILE"
        FOUNDRY_PROFILE=test \
            test forge  --via-ir --build-info --skip $CORE_DIR/*.sol $FILE || break
        echo ""
    done
}

function main() {
    do_core_build $@
    do_test_build $@
}
