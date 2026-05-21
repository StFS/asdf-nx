# Follow-ups

Tracking items that are intentionally out of scope for v1 but worth doing later. None of these are blocking — v1 is shipped and CI-green.

## Pending

### 1. Submit to the asdf-plugins shortname registry

Open a PR against [`asdf-vm/asdf-plugins`](https://github.com/asdf-vm/asdf-plugins) adding `plugins/nx` containing:

```text
repository = https://github.com/StFS/asdf-nx
```

Once merged, users can install via `asdf plugin add nx` without the full URL. Their PR template requires a passing CI run, which `build.yml` already satisfies.

### 2. Tag v1.0.0

When ready for the first stable release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Consider whether to create a GitHub release with notes pointing at this repo's commit history.

### 3. Minor polish from the v1 code review

Non-blocking items flagged by the final whole-repo code review (none of these affect correctness). All could land in a single follow-up commit.

- **`bin/list-all` and `bin/latest-stable` swallow `curl` failures silently** — if the registry is unreachable (DNS, corp proxy, 5xx), the user sees a bare "list-all failed" from asdf with no diagnostic. Wrap the curl call in `if ! body=$(curl …)` and `fail` with a registry-aware message pointing at `NPM_CONFIG_REGISTRY`.

- **`bin/install` failure path is less informative than `bin/download`'s** — `bin/download` wraps `npm pack` with `|| fail "npm pack failed for nx@…"`. `bin/install` relies on the `ERR` trap and skips the explicit banner. Stylistic only; either add a matching `|| fail` to `npm install` or remove the wrapper from `bin/download` for symmetry. Friendlier choice is the former.

- **`bin/help.deps` lists `npm`** — there is no `npm` shortname in the asdf-plugins registry, and `npm` ships with `nodejs`, so the line is redundant. Remove `echo "npm"` from `bin/help.deps` (and update spec §5.7 to match).

- **Spec and plan still reference `plugin-test@v3`** — the working CI uses `@v4` (commit `edf31cd` bumped it). Either add a one-line addendum to the spec ("`v4` superseded `v3` on 2026-05-21") or leave it as commit history. Author's call.

- **Paranoid guard against `$ASDF_INSTALL_PATH == /` in `bin/install`'s cleanup** — `rm -rf "$ASDF_INSTALL_PATH"` is catastrophic if the variable is ever `/`. asdf computes the path itself so the real risk is zero, but adding `[[ -n "$ASDF_INSTALL_PATH" && "$ASDF_INSTALL_PATH" != "/" ]]` to the cleanup guard costs one line.

### 4. Out-of-scope items deliberately deferred from v1

These were called out as non-goals in the design spec (§3) and remain so. Revisit only if user reports indicate they're actually needed.

- **nx-major → Node-major compatibility assertion** (`bin/exec-env`). nx already prints a clear error if Node is too old; maintaining a lookup table per nx release would rot.

- **`bin/post-plugin-add` banner** pointing at the asdf-nodejs prerequisite. The friendly error in `ensure_node` is judged sufficient.

- **Bats unit tests for `lib/utils.bash`**. The smoke tests in Task 2 and the CI plugin-test integration are deemed sufficient.

- **`.gitignore` additions** suggested in Task 1's review (`*.swo`, `node_modules/`). Advisory; user opted out.

## How to use this file

When you pick up any item, move it to a "Done" section at the bottom with the commit SHA, or just delete the entry once it lands.
