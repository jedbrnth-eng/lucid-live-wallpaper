# Packaging drafts

`lucid.rb` is a **draft** Homebrew cask. Nothing here is published.

- Fill in `sha256` from the `Lucid.zip.sha256` file attached to the release, then run `brew audit --cask --new ./lucid.rb`
  and a local `brew install --cask ./lucid.rb` before sharing it.
- Lucid is ad-hoc signed and not notarized. Homebrew's [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) policy
  requires apps in the official `homebrew/cask` repository to pass Gatekeeper (Developer ID signed and notarized), and casks
  that fail it are deprecated and removed. So the realistic home today is a personal tap (`<user>/homebrew-tap`), with the
  same "Open Anyway" caveat as the zip download. Re-check the policy before publishing.
- Homebrew does not remove the quarantine flag for casks, so users still see the Gatekeeper prompt once.
