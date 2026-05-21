#!/usr/bin/env bash
# Shared helpers for asdf-nx plugin scripts.
# This file is sourced; it does not set strict mode itself.

# shellcheck disable=SC2034  # TOOL_NAME is used by scripts that source this file.
TOOL_NAME="nx"
DEFAULT_REGISTRY="https://registry.npmjs.org"
# Versions matching this regex are filtered out of list-all by default.
PRERELEASE_REGEX='(-pr[-.]|-canary\.|-beta\.|-rc\.|-next\.)'

# Print an error message in red and exit 1.
fail() {
    printf '\033[31masdf-nx: %s\033[0m\n' "$*" >&2
    exit 1
}

# Fail with a friendly Node/npm install hint if the given command is missing.
ensure_command() {
    local cmd="$1"
    if ! command -v "$cmd" > /dev/null 2>&1; then
        fail "$cmd is required but was not found on PATH.

nx requires Node.js and npm to install.

Install Node.js via asdf:
    asdf plugin add nodejs
    asdf install nodejs latest
    asdf set -u nodejs latest

Or install from https://nodejs.org/"
    fi
}

ensure_node() { ensure_command "node"; }
ensure_npm() { ensure_command "npm"; }

# Resolve the npm registry URL. Tries NPM_CONFIG_REGISTRY, then `npm config get registry`,
# then falls back to the public registry. Always prints without a trailing slash.
get_registry() {
    local url

    if [[ -n "${NPM_CONFIG_REGISTRY:-}" ]]; then
        url="$NPM_CONFIG_REGISTRY"
    elif command -v npm > /dev/null 2>&1; then
        url="$(npm config get registry 2> /dev/null | tr -d '[:space:]')"
        if [[ -z "$url" || "$url" == "undefined" ]]; then
            url="$DEFAULT_REGISTRY"
        fi
    else
        url="$DEFAULT_REGISTRY"
    fi

    printf '%s' "${url%/}"
}

# Filter prerelease/PR/canary versions out of stdin unless ASDF_NX_INCLUDE_PRERELEASES=1.
# Only the literal value "1" enables prereleases; "true"/"yes"/etc are not accepted.
filter_unstable() {
    if [[ "${ASDF_NX_INCLUDE_PRERELEASES:-0}" == "1" ]]; then
        cat
    else
        grep -Ev "$PRERELEASE_REGEX" || true
    fi
}

# Standard asdf-plugin-template version-sort idiom (ascending, semver-aware).
# Note: pre-release versions (e.g. 23.0.0-beta.17) sort AFTER their matching
# stable release (23.0.0), which is incorrect strict-semver order. This is
# acceptable here because filter_unstable removes prereleases by default;
# users opting into ASDF_NX_INCLUDE_PRERELEASES=1 see this approximation.
sort_versions() {
    sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
        LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n |
        awk '{print $2}'
}
