# Homebrew release CI/CD

This app should be distributed with a Homebrew cask, not a formula. Homebrew formulae build CLI tools and libraries; `.app` bundles belong in a cask.

## Repositories

Use:

- app source: `XiaNetworks/WeatherBarX`
- tap repo: `XiaNetworks/homebrew-tap`

Create the tap repo as a public GitHub repository. Homebrew will install from it as:

```bash
brew install --cask xianetworks/tap/weatherbarx
```

## What the workflows do

- `.github/workflows/ci.yml` runs macOS unit tests on pushes and pull requests.
- `.github/workflows/release.yml` runs on tags like `v1.2.3` and:
  - builds an unsigned `Release` app bundle
  - zips `WeatherBarX.app`
  - computes the SHA256 for Homebrew
  - publishes or updates the GitHub release asset
  - renders `weatherbarx.rb`
  - optionally commits that cask into `XiaNetworks/homebrew-tap`

## Required setup

### 1. Create the tap repo

Create `https://github.com/XiaNetworks/homebrew-tap` with this structure:

```text
Casks/
```

### 2. Add a token secret to `WeatherBarX`

In `XiaNetworks/WeatherBarX`, add this repository secret:

- `TAP_GITHUB_TOKEN`: a GitHub personal access token that can push to `XiaNetworks/homebrew-tap`

The workflow uses the default `GITHUB_TOKEN` for the release in the current repo, but it needs a separate token to update another repo.

### 3. Tag releases

Push a semver tag:

```bash
git tag v1.0.0
git push release v1.0.0
```

That triggers the release workflow.

## First release check

After the workflow completes, verify:

```bash
brew tap xianetworks/tap
brew install --cask weatherbarx
```

If you want Homebrew to accept the app without Gatekeeper warnings, add Apple code signing and notarization later. The current pipeline ships an unsigned app, which is enough for Homebrew delivery but not for a polished macOS distribution experience.
