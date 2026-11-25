# Contributing

This repository is a **private fork** of [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis).
It adds [PI-Desktop](https://github.com/vastsa/PI-Desktop) as a first-class platform and
publishes the CLI as [`@awesome_dura/trellis`](https://www.npmjs.com/package/@awesome_dura/trellis).

## Where things go

| Topic | Where |
| --- | --- |
| Upstream Trellis bugs, features, platform requests | [mindfold-ai/Trellis issues](https://github.com/mindfold-ai/Trellis/issues) |
| PI-Desktop install / plugin / sub-agent problems | Issues in this repository |
| Building, installing, following upstream, publishing | [FORK.md](FORK.md) |
| What the fork changed and why | `.trellis/spec/cli/backend/platform-integration.md` |

## Working on the fork

```powershell
pnpm install
pnpm build                      # core + cli
pwsh ./scripts/install-fork.ps1 # install the CLI globally from source
```

Targeted tests (the full suite has 23 known Windows-environment failures inherited
from upstream, so the scripts run only the relevant files):

```powershell
cd packages/cli
npx vitest run --maxWorkers=3 test/commands/pi-desktop.test.ts test/templates/pi-desktop.test.ts test/registry-invariants.test.ts
```

Keep `.trellis/scripts/**` and `packages/cli/src/templates/trellis/scripts/**`
byte-identical — a test asserts it.

## License

AGPL-3.0, inherited from upstream. See [LICENSE](LICENSE).
