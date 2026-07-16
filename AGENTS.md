# Repository Guidelines

## Project Structure & Module Organization

This Windows-first monorepo contains two independent Chromium extensions:

- `apps/twitch/`: Twitch video/audio/subtitle/VOD-chat export extension, Python native host, tool updater, and VOD-summary skill.
- `apps/youtube/`: YouTube video/audio/subtitle export extension and Python native host.
- `scripts/`: Monorepo-wide test, packaging, ID-reporting, and clean-install entry points.
- `docs/`: GitHub Pages site, support/privacy pages, and store-submission drafts.
- `.github/workflows/`: CI, product release, and Pages deployment automation.

Within each app, browser code is in `src/`, `popup/`, and `options/`; localized strings are in `_locales/`; native-host code and tests are in `native-host/` and `native-host/tests/`; release helpers are in `scripts/`.

## Build, Test, and Development Commands

Run from the repository root in PowerShell:

```powershell
.\scripts\test-all.ps1       # Syntax, smoke, and native-host tests for both apps
.\scripts\package-all.ps1    # Create each app's ZIP and unpacked extension
.\scripts\show-extension-ids.ps1
```

For one product, change to `apps\twitch` or `apps\youtube` and run `node scripts\smoke-test.mjs`, `python -m unittest discover -s native-host\tests -p "test*.py"`, and `.\scripts\package.ps1`. Use the documented native install/update scripts only when validating browser integration.

## Coding Style & Naming Conventions

Use four spaces in Python and PowerShell, two spaces in JavaScript/JSON, and clear `camelCase` JavaScript identifiers. Use `PascalCase` for PowerShell variables/parameters and `snake_case` for Python modules and functions. Keep app-specific code, manifests, permissions, native-host names, and artifacts isolated. No repository-wide formatter or linter is configured; preserve surrounding style and run syntax checks before submitting.

## Testing Guidelines

Tests combine Node syntax checks, product smoke tests, and Python standard-library `unittest`. Name Python tests `test*.py`; place native-host tests under the matching app's `native-host/tests/`. Run the root test script before changes are submitted; CI runs the same checks independently for both products.

## Commit & Pull Request Guidelines

Use short, imperative commit subjects, consistent with history (for example, `Redesign Twitch export architecture diagram`). Keep commits focused. Pull requests should explain the affected product(s), include test commands and results, call out permission/native-host/toolchain changes, and include screenshots or updated docs when user-facing UI or store/site content changes. Use product release tags such as `twitch-v0.1.0` or `youtube-v0.1.0` only for intentional releases.

## Security & Configuration Tips

Export only content you own or are authorized to use. Keep credentials and local toolchain files out of Git. Native hosts run locally and write to the user's selected output folder; changes to permissions, browser allowlists, tool downloads, or installer paths require careful review and an end-to-end smoke test.
