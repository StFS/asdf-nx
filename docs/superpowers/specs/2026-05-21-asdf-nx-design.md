# asdf-nx — Design Spec

| Field | Value |
| --- | --- |
| Date | 2026-05-21 |
| Author | Stefán Freyr Stefánsson |
| Status | Approved (pending implementation) |
| Repo | `StFS/asdf-nx` |

## 1. Overview

`asdf-nx` is an [asdf](https://asdf-vm.com) plugin that installs the [`nx`](https://nx.dev) monorepo CLI from Nrwl. It targets asdf 0.16+ (the Go rewrite) and uses the modern `bin/download` + `bin/install` plugin contract.

Because `nx` is distributed exclusively as an npm package with ~100 runtime dependencies and platform-specific native binaries (`@nx/nx-*`), the plugin runs `npm install` against the npm registry rather than extracting a self-contained tarball. This mirrors the pattern used by the only registered asdf plugin with the same constraint, `paulo-ferraz-oliveira/asdf-markdownlint-cli2`.

## 2. Goals

- Pin a specific `nx` CLI version per project via `.tool-versions`, alongside Node/Python/etc.
- Achieve CI/CD parity — CI and local dev resolve to the exact same `nx` version, driven by `.tool-versions`, without committing `node_modules`.
- Provide a global standalone `nx` command without depending on any project's `node_modules` or `npx`.
- Fit the team-wide asdf tooling standard.

## 3. Non-goals

- No `bin/exec-env` that asserts a nx-major → Node-major compatibility matrix. nx prints its own error if Node is too old; maintaining a lookup table would rot.
- No bundled telemetry-disable defaults, autocompletion shipping, or banner via `bin/post-plugin-add`.
- No support for installing pre-release / canary / PR-build versions by default — opt-in via env var.
- No automatic chaining to `asdf-nodejs`. The plugin requires `node` and `npm` on `$PATH`, surfaced via a friendly error message; the user manages Node.

## 4. Architecture

### 4.1 Repository layout

```text
asdf-nx/
├── bin/
│   ├── list-all
│   ├── latest-stable
│   ├── download
│   ├── install
│   ├── help.overview
│   ├── help.deps
│   └── help.links
├── lib/
│   └── utils.bash
├── scripts/
│   ├── format.bash
│   └── lint.bash
├── .github/workflows/
│   ├── build.yml
│   └── lint.yml
├── README.md
├── LICENSE              (already in place; MIT, 2026 Stefán Freyr Stefánsson)
└── .tool-versions       (pins shellcheck/shfmt for reproducible CI)
```

### 4.2 Boundaries

**`bin/list-all` and `bin/latest-stable`**

- Touch only the npm registry over HTTPS.
- No filesystem writes.
- Do not require `node`/`npm` (use `curl` only) — listing must work before Node is installed.

**`bin/download`**

- Writes only to `$ASDF_DOWNLOAD_PATH` (asdf-provided scratch dir).
- Requires `npm` (calls `npm pack`).

**`bin/install`**

- Writes only to `$ASDF_INSTALL_PATH`.
- Requires `npm` (calls `npm install --prefix`).
- Only script that mutates user-visible state.
- Cleans up `$ASDF_INSTALL_PATH` on failure via `trap ERR` so asdf never sees a half-installed version.

**`lib/utils.bash`**

- Pure helpers — no side effects beyond the `fail`/`ensure` helpers that print and `exit 1`.

### 4.3 Data flow

```text
asdf  ──┐                                       ┌── npm registry (HTTPS)
        │ 1. asks plugin: do you know <ver>?     │
        ├───────────────────────────────────────►┤
        │   bin/list-all curls /nx                │
        │ 2. download                             │
        ├───────────────────────────────────────►┤
        │   bin/download → npm pack --pack-       │
        │   destination $ASDF_DOWNLOAD_PATH       │
        │ 3. install                              │
        ├───────────────────────────────────────►┤
        │   bin/install → npm install --prefix    │
        │   $ASDF_INSTALL_PATH nx@<ver>           │
        │   then symlink nx, nx-cloud into        │
        │   $ASDF_INSTALL_PATH/bin/               │
        └───────────────────────────────────────►┤

        asdf creates shims in ~/.asdf/shims/
        pointing at $ASDF_INSTALL_PATH/bin/nx
```

## 5. Plugin contract scripts

### 5.1 `bin/list-all`

**Behavior:**

1. Resolve registry URL via the chain in [§5.6](#56-registry-resolution).
2. `curl -sfL -H 'Accept: application/vnd.npm.install-v1+json' "$REGISTRY/nx"` — the abbreviated metadata document (~10× smaller than the full doc).
3. Extract versions with `grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+[^"]*"'` (no `jq` dependency).
4. Apply the prerelease filter from [§5.5](#55-version-filtering) unless `ASDF_NX_INCLUDE_PRERELEASES=1`.
5. Sort ascending using the standard asdf `sed | sort | awk` version-sort idiom.
6. Print space-separated on one line.

### 5.2 `bin/latest-stable`

**Behavior:**

1. Resolve registry URL.
2. `curl -sfL "$REGISTRY/nx"` (full doc — one extra request, only called by `asdf latest nx`).
3. Extract `"latest":"<version>"` from `dist-tags`. Print it.

### 5.3 `bin/download`

**Behavior:**

1. Call `ensure_node` and `ensure_npm` ([§6.1](#61-node--npm-missing)).
2. `npm pack --silent "nx@$ASDF_INSTALL_VERSION" --pack-destination "$ASDF_DOWNLOAD_PATH"`.

Leaves `$ASDF_DOWNLOAD_PATH/nx-${ASDF_INSTALL_VERSION}.tgz` for `bin/install` to consume. No extraction — `npm install <tarball>` reads the tgz directly and resolves the full dep tree from it. asdf caches `$ASDF_DOWNLOAD_PATH`, so re-installs avoid hitting the registry for the tarball itself.

### 5.4 `bin/install`

**Behavior:**

1. As the very first executable line, install `trap cleanup_on_error ERR` (see [§6.3](#63-network-failure-mid-install)).
2. Call `ensure_node` and `ensure_npm`.
3. Write a stub `package.json` at `$ASDF_INSTALL_PATH/package.json`:

    ```json
    {"name": "asdf-nx-wrapper", "version": "0.0.0", "private": true}
    ```

    This makes `$ASDF_INSTALL_PATH` a valid npm project root so `npm install --prefix` has somewhere to anchor.

4. `npm install --silent --prefix "$ASDF_INSTALL_PATH" "$ASDF_DOWNLOAD_PATH/nx-${ASDF_INSTALL_VERSION}.tgz" --no-audit --no-fund --no-save` — installs nx from the locally-cached tarball and resolves all dependencies (including platform-specific `@nx/nx-*` native deps) from the npm registry into `$ASDF_INSTALL_PATH/node_modules/`.
5. Create bin symlinks:

    ```sh
    mkdir -p "$ASDF_INSTALL_PATH/bin"
    ln -sf "$ASDF_INSTALL_PATH/node_modules/.bin/nx"       "$ASDF_INSTALL_PATH/bin/nx"
    ln -sf "$ASDF_INSTALL_PATH/node_modules/.bin/nx-cloud" "$ASDF_INSTALL_PATH/bin/nx-cloud"
    ```

**`--omit=optional` is deliberately NOT used.** The `@nx/nx-*-${platform}` packages provide the file watcher and daemon; omitting them would partially break `nx`. Disk usage is ~300 MB per installed version, documented in the README.

### 5.5 Version filtering

Filter out the following from `bin/list-all` output by default:

- `0.0.0-pr-*` — PR builds (registry contains ~2,000 of these)
- `*-canary.*`
- `*-beta.*`
- `*-rc.*`
- `*-next.*`

Override by setting `ASDF_NX_INCLUDE_PRERELEASES=1` — all versions returned, unfiltered.

### 5.6 Registry resolution

Tried in order:

1. `$NPM_CONFIG_REGISTRY` environment variable.
2. `npm config get registry` (only if `npm` is on `$PATH`).
3. `https://registry.npmjs.org` (default).

Strip trailing `/` for consistent URL assembly. This matches `asdf-pnpm` and enables enterprise users behind Verdaccio/Artifactory mirrors.

### 5.7 Help scripts

- **`bin/help.overview`** — one-line description: `nx is a smart, fast and extensible build system from Nrwl (https://nx.dev).`
- **`bin/help.deps`** — prints `nodejs` and `npm`, one per line.
- **`bin/help.links`** — prints `homepage: https://nx.dev` and `source: https://github.com/nrwl/nx`.

### 5.8 `lib/utils.bash` helpers

- `fail "<msg>"` — print red error to stderr, `exit 1`.
- `ensure_node` / `ensure_npm` — `command -v` check, friendly fail message.
- `get_registry` — registry URL resolution chain.
- `sort_versions` — standard asdf version-sort awk idiom.
- `filter_unstable` — regex filter for PR/canary/beta versions, honors `ASDF_NX_INCLUDE_PRERELEASES`.

### 5.9 No `bin/list-bin-paths`

asdf's default (`$ASDF_INSTALL_PATH/bin/`) is what we use — the install step creates symlinks there.

## 6. Error handling

### 6.1 Node / npm missing

`ensure_node` / `ensure_npm` use `command -v` with this message:

```text
nx requires Node.js and npm to install.

Install Node.js via asdf:
    asdf plugin add nodejs
    asdf install nodejs lts
    asdf set -u nodejs lts

Or install from https://nodejs.org/
```

Called at the top of `bin/download` and `bin/install` (asdf can invoke them separately). NOT called from `bin/list-all` — listing must work without Node.

### 6.2 Registry unreachable / corp proxy

`curl` calls use `-sfL` (silent, fail-on-HTTP-error, follow-redirects) so HTTP errors surface cleanly rather than dumping HTML. `get_registry` ([§5.6](#56-registry-resolution)) lets users override via env var.

### 6.3 Network failure mid-install

`bin/install` installs an `ERR` trap as its first executable line (before any `ensure_*` calls or other commands), which removes `$ASDF_INSTALL_PATH` on failure:

```sh
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -d "$ASDF_INSTALL_PATH" ]]; then
        rm -rf "$ASDF_INSTALL_PATH"
    fi
    exit "$exit_code"
}
trap cleanup_on_error ERR
```

Without this, a flaky `npm install` would leave a version marked "installed" but broken.

### 6.4 Version doesn't exist on registry

No pre-validation against `list-all`. `npm pack` exits non-zero with a clear `404 Not Found` message; that's good enough and saves a registry round-trip per install.

### 6.5 Unsupported platform

If no matching `@nx/nx-*` optional dep is available (e.g., FreeBSD/arm), `npm install` succeeds but native features fall back to JS implementations. nx prints its own runtime warning. README documents this.

### 6.6 Disk-space failure

No special handling — `npm install` fails with `ENOSPC`, the `ERR` trap cleans up, asdf surfaces the error.

### 6.7 Explicitly NOT validated

- Node-version compatibility with the requested nx version (decided in [§3](#3-non-goals)).
- Existing global `nx` install on the system — `$PATH` ordering decides.

## 7. Testing & CI

### 7.1 `.github/workflows/build.yml` — end-to-end install test

**Matrix:**

- **OS:** `ubuntu-latest` (covers `linux-x64-gnu`), `macos-latest` (covers `darwin-arm64` — Apple Silicon, the only platform `macos-latest` ships on as of 2025).
- **nx version:** `latest`, plus two pinned versions (one current-major, one previous-major — e.g., `22.7.2` and `21.0.0`) to catch regressions when nx's package layout shifts across majors.

**Steps per combination:**

1. Check out the plugin.
2. Set up Node via `actions/setup-node@v4` with `node-version: lts/*` (matches asdf-markdownlint-cli2; sidesteps the asdf-nodejs chaining question in CI).
3. Run `asdf-vm/actions/plugin-test@v3` with:
    - `command: nx --version`
    - `version: <matrix version>`

This is the canonical asdf plugin smoke test — catches broken symlinks, missing deps, version-parse errors without us writing test code.

### 7.2 `.github/workflows/lint.yml`

- `shellcheck` on every `.bash` and `bin/*` script.
- `shfmt -d` for formatting.

### 7.3 Not tested

- nx command behaviors (nx has its own test suite).
- Every nx version ever (matrix samples meaningful boundaries).
- Network-error paths (too flaky in CI; `trap ERR` cleanup is short enough to eyeball).

### 7.4 Local development

`scripts/lint.bash` and `scripts/format.bash` mirror the CI checks so developers iterate without pushing.

### 7.5 Pre-release manual smoke test

README documents how to install the plugin from a local checkout and run `asdf install nx latest` to verify on the dev's machine before tagging a release. Catches platform-specific issues CI can't reproduce.

## 8. README structure

```text
# asdf-nx

asdf plugin for nx (https://nx.dev), the monorepo build system from Nrwl.

## Dependencies
    - asdf >= 0.16
    - Node.js (recommended: latest LTS)
    - npm

## Install
    asdf plugin add nx https://github.com/StFS/asdf-nx

## Use
    asdf install nx latest
    asdf set -u nx 22.7.2

## Notes
    - Each installed nx version is ~300 MB on disk (full dep tree resolved).
    - Pre-releases hidden by default. Set ASDF_NX_INCLUDE_PRERELEASES=1 to include.
    - Honors NPM_CONFIG_REGISTRY for corp/private registries.

## Troubleshooting
    - "node not found" → install Node first (see asdf-nodejs).
    - Registry timeouts → check NPM_CONFIG_REGISTRY or npm config get registry.

## Contributing / License
```

## 9. Distribution

### 9.1 License

MIT, already in place at the repo root. Author: Stefán Freyr Stefánsson, 2026.

### 9.2 asdf-plugins shortname registry submission

**Follow-up, not part of v1 implementation.** After publishing and verifying `asdf install nx latest` works on Ubuntu + macOS, open a PR against [`asdf-vm/asdf-plugins`](https://github.com/asdf-vm/asdf-plugins) adding `plugins/nx`:

```text
repository = https://github.com/StFS/asdf-nx
```

That enables `asdf plugin add nx` without the full URL. The asdf-plugins PR template requires a green CI run, which `build.yml` satisfies.

## 10. Open questions / future work

- Whether to add `bin/exec-env` later if user reports show frequent Node-version mismatches in the wild. Currently out of scope.
- Whether to expose a `bin/post-plugin-add` banner pointing at the asdf-nodejs prerequisite. Currently out of scope — friendly error in `ensure_node` is judged sufficient.
- Decide on a release-tagging convention (semver-on-plugin vs. mirror-nx-versions). Recommend: semver-on-plugin, since the plugin's lifecycle is independent of nx's.

## 11. Prior art consulted

- [`jonathanmorley/asdf-pnpm`](https://github.com/jonathanmorley/asdf-pnpm) — registry resolution, `list-all` abbreviated metadata trick, bin-symlink defensive lookup.
- [`paulo-ferraz-oliveira/asdf-markdownlint-cli2`](https://github.com/paulo-ferraz-oliveira/asdf-markdownlint-cli2) — only registered asdf plugin that runs `npm install` to resolve a dep tree. Direct precedent for the install strategy used here.
- [`CanRau/asdf-ni`](https://github.com/CanRau/asdf-ni) — npm-registry tarball pattern (rejected for nx because nx is not self-contained).
- [`jthegedus/asdf-firebase`](https://github.com/jthegedus/asdf-firebase) — modern `bin/download` + `bin/install` split reference.
- [`asdf-vm/actions/plugin-test`](https://github.com/asdf-vm/actions) — canonical CI smoke test.
