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

# The tarball for the version in VERSION, named exactly.
#
# Not `ls dist/headless-spotify-*-macos.tar.gz | head -1`. That takes whichever
# entry the glob happens to sort first, so on a machine that still has an older
# tarball in dist/ it stages the cask against *that* one: the sha256 matches, the
# download succeeds, and then the install fails with "the App source ... is not
# there", because the cask's `app` stanza looks for a directory named after
# VERSION and the stale tarball unpacks under the old one. A CI runner has a
# clean dist/ and never sees it, which is why it survived.
VERSION="$(tr -d ' \t\r\n' < VERSION)"
TARBALL="headless-spotify-$VERSION-macos.tar.gz"
if [ ! -f "dist/$TARBALL" ]; then
  echo "error: dist/$TARBALL is missing — run scripts/package-release.sh first" >&2
  echo "       (dist/ holds: $(ls dist/*.tar.gz 2>/dev/null | tr '\n' ' ' || echo nothing))" >&2
  exit 1
fi
SHA="$(cd dist && shasum -a 256 "$TARBALL" | cut -d' ' -f1)"

# One owner for both the tap and the token, so the two jobs cannot disagree
# about which cask is being checked.
OWNER="$(printf '%s' "${GITHUB_REPOSITORY_OWNER:-kathir-d}" | tr '[:upper:]' '[:lower:]')"
TAPDIR="$(brew --repository)/Library/Taps/$OWNER/homebrew-headless-spotify"
mkdir -p "$TAPDIR/Casks"

# Only the lines that name the release move. `version` has to follow VERSION
# too: the checked-in cask still names the last published release until
# release.yml bumps it after tagging, so on a version-bump commit the `app`
# stanza would otherwise look for a directory named after the old version.
sed -e "s|^  version \".*\"|  version \"$VERSION\"|" \
    -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" \
    -e "s|^  url \"https://github.com.*|  url \"file://$SCRIPT_DIR/dist/$TARBALL\"|" \
    Casks/headless-spotify.rb > "$TAPDIR/Casks/headless-spotify.rb"

# A sed that quietly matches nothing leaves a cask pointing at a release whose
# checksum it does not have, and every check downstream then either fails for
# the wrong reason or — worse — passes against a download it never looked at.
if ! grep -q "^  version \"$VERSION\"$" "$TAPDIR/Casks/headless-spotify.rb"; then
  echo "error: the version line was not rewritten; the cask layout changed" >&2
  exit 1
fi
if ! grep -q "^  sha256 \"$SHA\"$" "$TAPDIR/Casks/headless-spotify.rb"; then
  echo "error: the sha256 line was not rewritten; the cask layout changed" >&2
  exit 1
fi
if ! grep -q "^  url \"file://" "$TAPDIR/Casks/headless-spotify.rb"; then
  echo "error: the url line was not rewritten; the cask layout changed" >&2
  exit 1
fi

echo "$OWNER/headless-spotify/headless-spotify"
