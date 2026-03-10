#!/usr/bin/env bash
set -e # exit on error
# set -x # echo commands

source "./script/base.sh" # Setup log funcs, OS, etc

function static_analysis() {
    if [ ! -e out/build-info ]; then
        mkdir -p out
        ln -s ../out out/build-info
    fi

    # Comma separated list of disabled detectors:
    # * naming-convention     - No desire to follow this convention
    # * incorrect-equality    - If this only occurred with respect to ETH balances it might be sane, otherwise dumb
    # * reentrancy-benign     - All mutable funcs have account level access control which is sufficient to ignore this
    # * reentrancy-events     - See previous item
    # * reentrancy-no-eth     - See previous item
    # * cyclomatic-complexity - Too many if-statements in a function, this conflicts with SIZE limites
    # * calls-loop            - Loops are expensive, too many hits
    # * missing-zero-check    - Has many false positives such as when using a helper func to check
    # * timestamp             - block.timestamp has known accuracy limits, usage is fine when knowing the limitations
    DETECTORS_OFF=naming-convention,incorrect-equality,reentrancy-benign,reentrancy-events,reentrancy-no-eth,cyclomatic-complexity,calls-loop,missing-zero-check,timestamp

    # To see all disabled detectors in source:
    # grep 'slither-disable' contract/*/*.sol | sed 's/: */ /g' | cut -d' ' -f4 | sort | uniq -c

    # Run slither on contracts exclude libraries and interfaces to avoid many artificial issues such as unused code
    FILES=$(find contract -type f -name *.sol | egrep -v '/Library|/I[A-Z]' | sort)
    FILE_LEN=$(echo $FILES | sed 's/ /\n/g' | wc -l)
    log "Running slither for $FILE_LEN files:"
    echo "$FILES"
    I=1
    for FILE in $FILES; do
        echo ""
        if [ $(grep "^contract" $FILE | wc -l) == "0" ]; then
            log "Skipping slither on file $I of $FILE_LEN: $FILE (No contract in file)"
            continue
        fi
        log "Running slither on file $I of $FILE_LEN: $FILE ..."

        # slither requires the source AST and does not work on EVM IR so 'via-ir' (IR pipeline) must be disabled; thus,
        # 'Contract code size' warnings can be ignored for contracts that are below the limit with 'via-ir' in prod
        slither $FILE --filter-paths 'node_modules,lib' --ignore-compile --exclude $DETECTORS_OFF --solc-args "--base-path . --include-path node_modules --allow-paths . -revert-strings=strip --optimize"

        I=$(( $I + 1 ))
    done
}

# Do solidity core contract static analysis
function main() {
    echo ""
    if [ $(which go | wc -l) == 0 ]; then
        fatal "go not found in PATH"
    fi

    log  "Static analysis started"

    START_TIME=$(date +%s)

    static_analysis $@

    ELAPSED=$(($(date +%s) - START_TIME))s
    log  "static analysis completed in $ELAPSED"
}

main $@
