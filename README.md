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
