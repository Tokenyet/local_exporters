# Contributing

## Validate both products

Run the monorepo checks from PowerShell:

```powershell
.\scripts\test-all.ps1
.\scripts\package-all.ps1
```

Each product can also be tested directly from `apps\twitch` or `apps\youtube`.

## Release tags

Product releases use independent tags:

- `twitch-v0.1.0`
- `youtube-v0.1.0`

The release workflow can also be started manually with a product and version.

## Scope

Keep Twitch and YouTube behavior, permissions, manifests, native host names, and release artifacts separate. Put genuinely shared toolchain or repository automation at the monorepo root; do not make one extension depend on the other extension's product code.
