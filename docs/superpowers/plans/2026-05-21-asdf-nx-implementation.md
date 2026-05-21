# asdf-nx Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working asdf 0.16+ plugin that installs the `nx` monorepo CLI via `npm install`, exposes `nx` and `nx-cloud` shims, and passes a matrix CI smoke test on Ubuntu and macOS.

**Architecture:** Bash plugin scripts in `bin/` (one per asdf contract entry-point) that source shared helpers from `lib/utils.bash`. `bin/download` runs `npm pack` against the public registry to cache the nx tarball; `bin/install` consumes that tarball via `npm install --prefix` against a stub `package.json` in `$ASDF_INSTALL_PATH`, then symlinks `node_modules/.bin/nx` and `nx-cloud` into `$ASDF_INSTALL_PATH/bin/` for asdf's default shim discovery. Static checks via shellcheck + shfmt; end-to-end via `asdf-vm/actions/plugin-test@v3`.

**Tech Stack:** Bash (strict mode), curl, npm, shellcheck, shfmt, GitHub Actions.

---

## Reference notes

Anything not spelled out here is in the design spec at `docs/superpowers/specs/2026-05-21-asdf-nx-design.md`. Check it before deviating.

**Working directory for all commands:** `/Users/stefan.freyr/work/tmp/asdf-nx`

**Existing state at plan start:** Repo initialized, `LICENSE` and `README.md` (one-line) committed, remote `origin` set to `git@github.com:StFS/asdf-nx.git`, branch `main`.

**Bash strictness:** Every executable script in `bin/` and `scripts/` starts with `#!/usr/bin/env bash` and `set -euo pipefail`. `lib/utils.bash` does **not** set strict mode itself (sourced files inherit caller's settings).

**asdf contract reminders:**

- `bin/list-all` must print all versions space-separated on stdout.
- `bin/latest-stable` must print one version on stdout.
- `bin/download` receives `$ASDF_INSTALL_TYPE`, `$ASDF_INSTALL_VERSION`, `$ASDF_DOWNLOAD_PATH` and must populate `$ASDF_DOWNLOAD_PATH`.
- `bin/install` receives `$ASDF_INSTALL_TYPE`, `$ASDF_INSTALL_VERSION`, `$ASDF_INSTALL_PATH`, `$ASDF_DOWNLOAD_PATH`. Must produce an executable at `$ASDF_INSTALL_PATH/bin/<tool>`.

---

## Task 1: Scaffold repository structure

**Files:**

- Create: `.gitignore`
- Create: `.tool-versions`
- Create: `bin/.gitkeep`
- Create: `lib/.gitkeep`
- Create: `scripts/.gitkeep`
- Create: `.github/workflows/.gitkeep`

- [ ] **Step 1: Create `.gitignore`**

```text
.DS_Store
.env
*.swp
```

- [ ] **Step 2: Create `.tool-versions`** (pins shellcheck/shfmt for reproducible local dev)

```text
shellcheck 0.10.0
shfmt 3.8.0
```

- [ ] **Step 3: Create directory structure with `.gitkeep` placeholders**

```bash
mkdir -p bin lib scripts .github/workflows
touch bin/.gitkeep lib/.gitkeep scripts/.gitkeep .github/workflows/.gitkeep
```

- [ ] **Step 4: Verify**

Run: `ls -la bin lib scripts .github/workflows`
Expected: each directory exists and contains a `.gitkeep` file.

- [ ] **Step 5: Commit**

```bash
git add .gitignore .tool-versions bin/.gitkeep lib/.gitkeep scripts/.gitkeep .github/workflows/.gitkeep
git commit -m "chore: scaffold plugin directory structure"
```

---

## Task 2: Implement `lib/utils.bash` (shared helpers)

**Files:**

- Create: `lib/utils.bash`

This file holds every helper the bin scripts reuse: `fail`, `ensure_node`, `ensure_npm`, `get_registry`, `filter_unstable`, `sort_versions`, plus the `TOOL_NAME` constant.

- [ ] **Step 1: Write `lib/utils.bash`**

```bash
#!/usr/bin/env bash
# Shared helpers for asdf-nx plugin scripts.
# This file is sourced; it does not set strict mode itself.

TOOL_NAME="nx"
DEFAULT_REGISTRY="https://registry.npmjs.org"
# Versions matching this regex are filtered out of list-all by default.
PRERELEASE_REGEX='(-pr-|-canary\.|-beta\.|-rc\.|-next\.)'

# Print an error message in red and exit 1.
fail() {
    echo -e "\033[31masdf-nx: $*\033[0m" >&2
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
    asdf install nodejs lts
    asdf set -u nodejs lts

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
filter_unstable() {
    if [[ "${ASDF_NX_INCLUDE_PRERELEASES:-0}" == "1" ]]; then
        cat
    else
        grep -Ev "$PRERELEASE_REGEX" || true
    fi
}

# Standard asdf-plugin-template version-sort idiom (ascending, semver-aware).
sort_versions() {
    sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' \
        | LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n \
        | awk '{print $2}'
}
```

- [ ] **Step 2: Smoke-test `filter_unstable`**

Run:

```bash
bash -c '
source ./lib/utils.bash
printf "22.7.2\n23.0.0-beta.17\n0.0.0-pr-99-abc\n21.6.11\n" | filter_unstable
'
```

Expected output (two lines):

```text
22.7.2
21.6.11
```

- [ ] **Step 3: Smoke-test `filter_unstable` with prereleases enabled**

Run:

```bash
ASDF_NX_INCLUDE_PRERELEASES=1 bash -c '
source ./lib/utils.bash
printf "22.7.2\n23.0.0-beta.17\n0.0.0-pr-99-abc\n21.6.11\n" | filter_unstable
'
```

Expected output (four lines, all four versions present).

- [ ] **Step 4: Smoke-test `sort_versions`**

Run:

```bash
bash -c '
source ./lib/utils.bash
printf "22.7.2\n21.0.0\n22.0.0\n21.6.11\n" | sort_versions
'
```

Expected output:

```text
21.0.0
21.6.11
22.0.0
22.7.2
```

- [ ] **Step 5: Smoke-test `get_registry`**

Run:

```bash
NPM_CONFIG_REGISTRY=https://example.com/npm/ bash -c '
source ./lib/utils.bash
get_registry; echo
'
```

Expected output:

```text
https://example.com/npm
```

(Note the trailing slash was stripped.)

- [ ] **Step 6: Shellcheck**

Run: `shellcheck lib/utils.bash`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/utils.bash
git rm lib/.gitkeep
git commit -m "feat: add lib/utils.bash with shared plugin helpers"
```

---

## Task 3: Implement the three `bin/help.*` scripts

**Files:**

- Create: `bin/help.overview`
- Create: `bin/help.deps`
- Create: `bin/help.links`

These are tiny stubs asdf reads when a user runs `asdf help nx`.

- [ ] **Step 1: Write `bin/help.overview`**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "nx is a smart, fast and extensible build system from Nrwl (https://nx.dev)."
```

- [ ] **Step 2: Write `bin/help.deps`**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "nodejs"
echo "npm"
```

- [ ] **Step 3: Write `bin/help.links`**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "homepage: https://nx.dev"
echo "source: https://github.com/nrwl/nx"
```

- [ ] **Step 4: Make all three executable**

```bash
chmod +x bin/help.overview bin/help.deps bin/help.links
```

- [ ] **Step 5: Verify**

Run: `./bin/help.overview && ./bin/help.deps && ./bin/help.links`
Expected: each prints its single/two-line output, exit 0.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck bin/help.overview bin/help.deps bin/help.links`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add bin/help.overview bin/help.deps bin/help.links
git commit -m "feat: add help.overview/deps/links scripts"
```

---

## Task 4: Implement `bin/list-all` and `bin/latest-stable`

**Files:**

- Create: `bin/list-all`
- Create: `bin/latest-stable`

Both touch the npm registry only. Neither requires Node/npm to be installed (curl is sufficient), so they're safe to run before the user has a Node toolchain.

- [ ] **Step 1: Write `bin/list-all`**

```bash
#!/usr/bin/env bash
set -euo pipefail

plugin_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/utils.bash
source "$plugin_dir/lib/utils.bash"

list_all_versions() {
    local registry url
    registry="$(get_registry)"
    url="$registry/$TOOL_NAME"

    curl -sfL -H 'Accept: application/vnd.npm.install-v1+json' "$url" \
        | grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+[^"]*"' \
        | tr -d '"' \
        | sort -u
}

list_all_versions \
    | filter_unstable \
    | sort_versions \
    | tr '\n' ' '
echo
```

- [ ] **Step 2: Write `bin/latest-stable`**

```bash
#!/usr/bin/env bash
set -euo pipefail

plugin_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/utils.bash
source "$plugin_dir/lib/utils.bash"

registry="$(get_registry)"

curl -sfL "$registry/$TOOL_NAME" \
    | grep -Eo '"latest":"[^"]+"' \
    | head -n1 \
    | sed 's/.*"latest":"\([^"]*\)"/\1/'
```

- [ ] **Step 3: Make both executable**

```bash
chmod +x bin/list-all bin/latest-stable
```

- [ ] **Step 4: Run `bin/list-all`**

Run: `./bin/list-all`
Expected: one line of space-separated versions, ending with the current latest stable nx (e.g. `… 22.7.1 22.7.2`). Should contain only stable versions (no `0.0.0-pr-*`, no `-beta.`, etc.).

- [ ] **Step 5: Run `bin/latest-stable`**

Run: `./bin/latest-stable`
Expected: one line containing the version under the `latest` dist-tag (e.g. `22.7.2` at time of writing).

- [ ] **Step 6: Sanity-check filtering**

Run: `./bin/list-all | tr ' ' '\n' | grep -E '(-pr-|-beta\.|-canary\.|-rc\.|-next\.)' | head`
Expected: no output (no prereleases leak through).

- [ ] **Step 7: Shellcheck**

Run: `shellcheck -x bin/list-all bin/latest-stable`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add bin/list-all bin/latest-stable
git commit -m "feat: add list-all and latest-stable scripts"
```

---

## Task 5: Implement `bin/download`

**Files:**

- Create: `bin/download`

Runs `npm pack` to fetch the nx tarball into `$ASDF_DOWNLOAD_PATH`. Does **not** extract — `bin/install` consumes the tgz directly.

- [ ] **Step 1: Write `bin/download`**

```bash
#!/usr/bin/env bash
set -euo pipefail

plugin_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/utils.bash
source "$plugin_dir/lib/utils.bash"

: "${ASDF_INSTALL_TYPE:?ASDF_INSTALL_TYPE not set}"
: "${ASDF_INSTALL_VERSION:?ASDF_INSTALL_VERSION not set}"
: "${ASDF_DOWNLOAD_PATH:?ASDF_DOWNLOAD_PATH not set}"

if [[ "$ASDF_INSTALL_TYPE" != "version" ]]; then
    fail "$TOOL_NAME does not support install type '$ASDF_INSTALL_TYPE'; only 'version' is supported"
fi

ensure_node
ensure_npm

mkdir -p "$ASDF_DOWNLOAD_PATH"

echo "asdf-nx: downloading $TOOL_NAME@$ASDF_INSTALL_VERSION via npm pack"
npm pack --silent \
    "$TOOL_NAME@$ASDF_INSTALL_VERSION" \
    --pack-destination "$ASDF_DOWNLOAD_PATH" \
    > /dev/null \
    || fail "npm pack failed for $TOOL_NAME@$ASDF_INSTALL_VERSION"

expected_tarball="$ASDF_DOWNLOAD_PATH/$TOOL_NAME-$ASDF_INSTALL_VERSION.tgz"
if [[ ! -f "$expected_tarball" ]]; then
    fail "npm pack succeeded but expected tarball not found: $expected_tarball"
fi

echo "asdf-nx: downloaded $expected_tarball"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/download
```

- [ ] **Step 3: Smoke-test against a real version**

Run:

```bash
rm -rf /tmp/asdf-nx-download-test
ASDF_INSTALL_TYPE=version \
ASDF_INSTALL_VERSION=22.7.2 \
ASDF_DOWNLOAD_PATH=/tmp/asdf-nx-download-test \
./bin/download
ls -la /tmp/asdf-nx-download-test
```

Expected: directory contains `nx-22.7.2.tgz` (a real ~few-MB file).

- [ ] **Step 4: Test failure path — non-existent version**

Run:

```bash
ASDF_INSTALL_TYPE=version \
ASDF_INSTALL_VERSION=99.99.99 \
ASDF_DOWNLOAD_PATH=/tmp/asdf-nx-download-bogus \
./bin/download || echo "EXIT=$?"
```

Expected: prints an npm error about 404 Not Found, then prints `asdf-nx: npm pack failed for nx@99.99.99`, then `EXIT=1`.

- [ ] **Step 5: Cleanup smoke-test artifacts**

```bash
rm -rf /tmp/asdf-nx-download-test /tmp/asdf-nx-download-bogus
```

- [ ] **Step 6: Shellcheck**

Run: `shellcheck -x bin/download`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add bin/download
git commit -m "feat: add download script (npm pack)"
```

---

## Task 6: Implement `bin/install`

**Files:**

- Create: `bin/install`

The only script that mutates user-visible state. Uses an `ERR` trap to wipe `$ASDF_INSTALL_PATH` on failure so asdf never sees a half-installed version.

- [ ] **Step 1: Write `bin/install`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Trap MUST be the first executable thing so a Node/npm-missing failure
# also triggers cleanup.
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -d "${ASDF_INSTALL_PATH:-}" ]]; then
        echo "asdf-nx: install failed; cleaning up $ASDF_INSTALL_PATH" >&2
        rm -rf "$ASDF_INSTALL_PATH"
    fi
    exit "$exit_code"
}
trap cleanup_on_error ERR

plugin_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/utils.bash
source "$plugin_dir/lib/utils.bash"

: "${ASDF_INSTALL_TYPE:?ASDF_INSTALL_TYPE not set}"
: "${ASDF_INSTALL_VERSION:?ASDF_INSTALL_VERSION not set}"
: "${ASDF_INSTALL_PATH:?ASDF_INSTALL_PATH not set}"
: "${ASDF_DOWNLOAD_PATH:?ASDF_DOWNLOAD_PATH not set}"

if [[ "$ASDF_INSTALL_TYPE" != "version" ]]; then
    fail "$TOOL_NAME does not support install type '$ASDF_INSTALL_TYPE'; only 'version' is supported"
fi

ensure_node
ensure_npm

tarball="$ASDF_DOWNLOAD_PATH/$TOOL_NAME-$ASDF_INSTALL_VERSION.tgz"
if [[ ! -f "$tarball" ]]; then
    fail "expected downloaded tarball not found: $tarball
Run \`asdf install $TOOL_NAME $ASDF_INSTALL_VERSION\` to re-download."
fi

mkdir -p "$ASDF_INSTALL_PATH"
cat > "$ASDF_INSTALL_PATH/package.json" << 'JSON'
{"name": "asdf-nx-wrapper", "version": "0.0.0", "private": true}
JSON

echo "asdf-nx: installing $TOOL_NAME@$ASDF_INSTALL_VERSION (resolves ~300 MB of dependencies)"
npm install --silent \
    --prefix "$ASDF_INSTALL_PATH" \
    --no-audit --no-fund --no-save \
    "$tarball" \
    > /dev/null

mkdir -p "$ASDF_INSTALL_PATH/bin"
for binname in nx nx-cloud; do
    src="$ASDF_INSTALL_PATH/node_modules/.bin/$binname"
    if [[ ! -e "$src" ]]; then
        fail "expected binary not found after install: $src"
    fi
    ln -sf "$src" "$ASDF_INSTALL_PATH/bin/$binname"
done

echo "asdf-nx: installed $TOOL_NAME@$ASDF_INSTALL_VERSION to $ASDF_INSTALL_PATH"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/install
```

- [ ] **Step 3: End-to-end smoke test (download then install)**

Run:

```bash
rm -rf /tmp/asdf-nx-{download,install}-test
mkdir -p /tmp/asdf-nx-{download,install}-test

ASDF_INSTALL_TYPE=version \
ASDF_INSTALL_VERSION=22.7.2 \
ASDF_DOWNLOAD_PATH=/tmp/asdf-nx-download-test \
./bin/download

ASDF_INSTALL_TYPE=version \
ASDF_INSTALL_VERSION=22.7.2 \
ASDF_INSTALL_PATH=/tmp/asdf-nx-install-test \
ASDF_DOWNLOAD_PATH=/tmp/asdf-nx-download-test \
./bin/install
```

Expected: prints the two `asdf-nx: …` progress lines; exit 0. May take 30-90 seconds depending on network.

- [ ] **Step 4: Verify install layout**

Run: `ls -la /tmp/asdf-nx-install-test/bin && /tmp/asdf-nx-install-test/bin/nx --version`
Expected:

- `bin/` contains symlinks `nx` and `nx-cloud` pointing into `node_modules/.bin/`.
- `nx --version` prints something like `Nx Version: 22.7.2`.

- [ ] **Step 5: Verify failure cleanup**

Run:

```bash
rm -rf /tmp/asdf-nx-install-fail
ASDF_INSTALL_TYPE=version \
ASDF_INSTALL_VERSION=22.7.2 \
ASDF_INSTALL_PATH=/tmp/asdf-nx-install-fail \
ASDF_DOWNLOAD_PATH=/tmp/asdf-nx-nonexistent-download \
./bin/install || echo "EXIT=$?"
ls /tmp/asdf-nx-install-fail 2>&1 || echo "directory removed as expected"
```

Expected: install fails because the download path doesn't exist, then the install path is removed by the `ERR` trap. Final output includes `directory removed as expected`.

- [ ] **Step 6: Cleanup smoke-test artifacts**

```bash
rm -rf /tmp/asdf-nx-{download,install}-test /tmp/asdf-nx-install-fail
```

- [ ] **Step 7: Shellcheck**

Run: `shellcheck -x bin/install`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add bin/install
git commit -m "feat: add install script (npm install + bin symlinks)"
```

---

## Task 7: Add local lint/format scripts

**Files:**

- Create: `scripts/lint.bash`
- Create: `scripts/format.bash`

These mirror the CI lint job so developers can iterate without pushing.

- [ ] **Step 1: Write `scripts/lint.bash`**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

files=()
for f in bin/*; do [[ -f $f ]] && files+=("$f"); done
for f in lib/*.bash scripts/*.bash; do [[ -f $f ]] && files+=("$f"); done

echo "==> shellcheck"
shellcheck -x "${files[@]}"

echo "==> shfmt -d"
shfmt -d -i 4 -ci -sr "${files[@]}"

echo "lint OK"
```

- [ ] **Step 2: Write `scripts/format.bash`**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

files=()
for f in bin/*; do [[ -f $f ]] && files+=("$f"); done
for f in lib/*.bash scripts/*.bash; do [[ -f $f ]] && files+=("$f"); done

shfmt -w -i 4 -ci -sr "${files[@]}"
echo "formatted ${#files[@]} files"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x scripts/lint.bash scripts/format.bash
```

- [ ] **Step 4: Run the formatter (idempotency check)**

Run: `./scripts/format.bash && git diff --stat`
Expected: either no changes (everything already formatted) or only whitespace tweaks. If non-trivial code changes appear, stop and inspect.

- [ ] **Step 5: Run the linter**

Run: `./scripts/lint.bash`
Expected: prints `==> shellcheck`, `==> shfmt -d`, `lint OK`, exit 0.

- [ ] **Step 6: Stage any formatter changes**

If `git diff` showed whitespace changes, stage them now:

```bash
git add -u
```

- [ ] **Step 7: Commit**

```bash
git add scripts/lint.bash scripts/format.bash
git rm scripts/.gitkeep
git commit -m "chore: add scripts/lint.bash and scripts/format.bash"
```

---

## Task 8: Add CI lint workflow

**Files:**

- Create: `.github/workflows/lint.yml`

Runs shellcheck + shfmt on every push and PR.

- [ ] **Step 1: Write `.github/workflows/lint.yml`**

```yaml
name: Lint

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    name: shellcheck + shfmt
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install shfmt
        run: |
          sudo curl -fsSL \
            -o /usr/local/bin/shfmt \
            https://github.com/mvdan/sh/releases/download/v3.8.0/shfmt_v3.8.0_linux_amd64
          sudo chmod +x /usr/local/bin/shfmt
          shfmt --version

      - name: Run lint
        run: ./scripts/lint.bash
```

(`shellcheck` is pre-installed on `ubuntu-latest` GitHub runners.)

- [ ] **Step 2: Validate YAML locally**

Run: `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/lint.yml"))'`
Expected: exit 0, no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/lint.yml
git commit -m "ci: add lint workflow (shellcheck + shfmt)"
```

---

## Task 9: Add CI build workflow (plugin-test matrix)

**Files:**

- Create: `.github/workflows/build.yml`

Runs `asdf-vm/actions/plugin-test@v3` against a matrix of OSes and nx versions.

- [ ] **Step 1: Write `.github/workflows/build.yml`**

```yaml
name: Build

on:
  push:
    branches: [main]
  pull_request:
  schedule:
    # Weekly run so we notice breakage from new nx releases.
    - cron: "0 6 * * 1"

jobs:
  plugin-test:
    name: ${{ matrix.os }} / nx ${{ matrix.nx-version }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        nx-version: ["latest", "22.7.2", "21.0.0"]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: lts/*

      - name: Test asdf plugin
        uses: asdf-vm/actions/plugin-test@v3
        with:
          command: nx --version
          version: ${{ matrix.nx-version }}
```

- [ ] **Step 2: Validate YAML locally**

Run: `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/build.yml"))'`
Expected: exit 0, no output.

- [ ] **Step 3: Remove the `.github/workflows/.gitkeep` placeholder**

```bash
git rm .github/workflows/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: add plugin-test matrix workflow"
```

---

## Task 10: Replace placeholder README

**Files:**

- Modify: `README.md` (currently one line: `# asdf-nx`)

- [ ] **Step 1: Read the existing README to confirm it's still the one-line placeholder**

Run: `cat README.md`
Expected: a single `# asdf-nx` heading.

- [ ] **Step 2: Replace with the full README**

Write the entire file with this content (GFM-compatible: blank lines around every block element, 4-space nested-list indent, backticks around identifiers with underscores):

````markdown
# asdf-nx

[![Lint](https://github.com/StFS/asdf-nx/actions/workflows/lint.yml/badge.svg)](https://github.com/StFS/asdf-nx/actions/workflows/lint.yml)
[![Build](https://github.com/StFS/asdf-nx/actions/workflows/build.yml/badge.svg)](https://github.com/StFS/asdf-nx/actions/workflows/build.yml)

[asdf](https://asdf-vm.com) plugin for [`nx`](https://nx.dev) — the monorepo build system from Nrwl.

## Dependencies

- asdf 0.16 or newer
- Node.js (recommended: latest LTS, see `nx`'s own engine requirements per major version)
- npm

The plugin requires `node` and `npm` on `$PATH` at install time. The easiest way to provide them is via [`asdf-nodejs`](https://github.com/asdf-vm/asdf-nodejs).

## Install

```sh
asdf plugin add nx https://github.com/StFS/asdf-nx
```

Once submitted to the [asdf-plugins registry](https://github.com/asdf-vm/asdf-plugins), `asdf plugin add nx` will work without the URL.

## Use

```sh
asdf install nx latest
asdf set -u nx 22.7.2
nx --version
```

Standard asdf workflow — pin per-project in `.tool-versions`:

```text
nx 22.7.2
nodejs 22.11.0
```

## Notes

- **Disk usage**: each installed nx version is ~300 MB (the full dependency tree is resolved into `node_modules/`). This is the same disk footprint as a project-local `npm install nx`.
- **Pre-releases hidden by default**: `asdf list-all nx` shows stable versions only. Set `ASDF_NX_INCLUDE_PRERELEASES=1` to include `beta`, `rc`, `next`, `canary`, and PR builds.
- **Custom npm registries**: the plugin honors `NPM_CONFIG_REGISTRY` and falls back to `npm config get registry`. Works behind Verdaccio/Artifactory mirrors.
- **Native dependencies**: nx ships platform-specific `@nx/nx-*` binaries (file watcher, daemon) as `optionalDependencies`. They are installed by default — `--omit=optional` is NOT used.

## Troubleshooting

**`node is required but was not found on PATH`** — install Node.js. The error message points at `asdf-nodejs`; that's the recommended approach.

**Registry timeouts / `npm pack` 404s** — check `npm config get registry` and `$NPM_CONFIG_REGISTRY`. Corporate proxies sometimes intercept HTTPS to the public npm registry.

**nx prints "platform not supported"** — your platform isn't covered by nx's `@nx/nx-*` native binaries. nx still runs (JS fallback); file watching and the nx daemon may be slower.

## Development

```sh
./scripts/lint.bash     # shellcheck + shfmt -d
./scripts/format.bash   # shfmt -w
```

Install from a local checkout for end-to-end testing:

```sh
asdf plugin add nx /path/to/asdf-nx
asdf install nx latest
```

## License

MIT, see [LICENSE](./LICENSE). Copyright (c) 2026 Stefán Freyr Stefánsson.
````

- [ ] **Step 3: Verify the README renders sensibly**

Run: `wc -l README.md`
Expected: roughly 70-90 lines.

Run: `grep -c '```' README.md`
Expected: an even number (every code fence opened is closed).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: write full README"
```

---

## Task 11: Final lint + end-to-end local install verification

This task ties the bow: re-run the linter against the complete plugin, then install the plugin into the actual asdf and install a real nx version through it.

- [ ] **Step 1: Re-run the linter on the full plugin**

Run: `./scripts/lint.bash`
Expected: `lint OK`, exit 0.

- [ ] **Step 2: Install the plugin into asdf from the local checkout**

Run:

```bash
asdf plugin remove nx 2>/dev/null || true
asdf plugin add nx "$(pwd)"
asdf plugin list
```

Expected: the output of `asdf plugin list` includes `nx`.

- [ ] **Step 3: List versions through asdf**

Run: `asdf list-all nx | tr ' ' '\n' | tail -n 5`
Expected: the last five stable nx versions, ending with the current latest.

- [ ] **Step 4: Install a real version through asdf**

Run: `asdf install nx latest`
Expected: download + install completes; exit 0. May take 30-90 seconds.

- [ ] **Step 5: Verify the shim works**

Run:

```bash
version="$(asdf latest nx)"
asdf set -u nx "$version"
asdf which nx
nx --version
```

Expected: `asdf which nx` points into `~/.asdf/installs/nx/<version>/bin/nx`; `nx --version` prints `Nx Version: <version>`. Note: `asdf set -u` writes to `$HOME/.tool-versions` — back up that file first if you have nx pinned globally for other reasons.

- [ ] **Step 6: Uninstall the test version (optional cleanup)**

```bash
asdf uninstall nx "$version" 2>/dev/null || true
```

- [ ] **Step 7: Push**

```bash
git push origin main
```

Expected: push succeeds. Watch the GitHub Actions runs — both `Lint` and `Build` workflows should appear and (eventually) pass.

- [ ] **Step 8: Verify CI**

Open https://github.com/StFS/asdf-nx/actions and confirm both workflows are green. Real-world platform / nx-version failures from this matrix are exactly what we want to learn before tagging a release — if one cell fails, investigate before declaring v1 done.

---

## Out of scope (do NOT do as part of this plan)

- Submitting to `asdf-vm/asdf-plugins` registry (do this manually after the first green CI run).
- Tagging a release.
- Adding `bin/exec-env`, `bin/post-plugin-add`, or any Node-version assertion logic. See [§3 of the spec](../specs/2026-05-21-asdf-nx-design.md#3-non-goals).
- Bats unit tests for `lib/utils.bash`. The smoke tests in Task 2 are deemed sufficient.
