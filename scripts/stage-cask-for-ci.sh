#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# stage-cask-for-ci.sh — put Casks/headless-spotify.rb into a local tap, with
# its version and checksum pointed at the tarball in dist/.
#
# CI needs this because the checked-in cask names a published release, and its
# sha256 is only correct once a tag has been pushed. A cask audited against a
# download it cannot match proves nothing, so the audit runs against the
# artifact this build actually produced.
#
# `brew audit`/`brew style [path]` cannot take a file, so the cask has to live
# in a real tap either way.
#
# Usage: ./scripts/stage-cask-for-ci.sh
#   Output: the fully qualified token, e.g. kathir-d/headless-spotify/headless-spotify
#   Requires: dist/headless-spotify-*-macos.tar.gz (scripts/package-release.sh)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

TARBALL="$(cd dist && ls headless-spotify-*-macos.tar.gz 2>/dev/null | head -1 || true)"
if [ -z "$TARBALL" ]; then
  echo "error: no tarball in dist/ — run scripts/package-release.sh first" >&2
  exit 1
fi
SHA="$(cd dist && shasum -a 256 "$TARBALL" | cut -d' ' -f1)"

# One owner for both the tap and the token, so the two jobs cannot disagree
# about which cask is being checked.
OWNER="$(printf '%s' "${GITHUB_REPOSITORY_OWNER:-kathir-d}" | tr '[:upper:]' '[:lower:]')"
TAPDIR="$(brew --repository)/Library/Taps/$OWNER/homebrew-headless-spotify"
mkdir -p "$TAPDIR/Casks"

# Only the two lines that name the release move; `url` interpolates
# #{version}, so the download follows the version on its own.
sed -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" \
    -e "s|^  url \"https://github.com.*|  url \"file://$SCRIPT_DIR/dist/$TARBALL\"|" \
    Casks/headless-spotify.rb > "$TAPDIR/Casks/headless-spotify.rb"

# A sed that quietly matches nothing leaves a cask pointing at a release whose
# checksum it does not have, and every check downstream then either fails for
# the wrong reason or — worse — passes against a download it never looked at.
if ! grep -q "^  sha256 \"$SHA\"$" "$TAPDIR/Casks/headless-spotify.rb"; then
  echo "error: the sha256 line was not rewritten; the cask layout changed" >&2
  exit 1
fi
if ! grep -q "^  url \"file://" "$TAPDIR/Casks/headless-spotify.rb"; then
  echo "error: the url line was not rewritten; the cask layout changed" >&2
  exit 1
fi

echo "$OWNER/headless-spotify/headless-spotify"
