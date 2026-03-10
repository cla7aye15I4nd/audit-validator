# Description: Helper script for reuse, forked from more general file for downstream audit subtree

set -e # exit on error
set -u # exit on undefined var
# set -x # echo commands

# The parent script should have an interpretter: #!/usr/bin/env bash
[[ ${BASH_VERSINFO-0} -ge 5 ]] || { echo "FATAL: bash version >= 5 required"; exit 1; }

function sed() { gsed "$@"; }

# Logging
function log()   { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): INFO : $*"; }
function info()  { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): INFO : $*"; }
function warn()  { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): WARN : $*"; }
function error() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): ERROR: $*" >&2; }
function fatal() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): FATAL: $*" >&2; exit 1; }

function setup_env() {
    # Vars to help scripts run on each OS
    if [[ $(uname) == "Darwin" ]]; then
        export OS=mac
        export BASH_CONFIG=~/.bash_profile

        # Note: This path has an annoying space ----v
        export VSCODE_SETTINGS=~/Library/Application\ Support/Code/User/settings.json
    else
        export OS=linux
        export BASH_CONFIG=~/.bashrc
        export VSCODE_SETTINGS=$HOME/.config/Code/User/settings.json
    fi

    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            echo "Unsupported architecture: $UNAME_M"
            exit 1
            ;;
    esac
}
setup_env
