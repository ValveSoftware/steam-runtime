#!/bin/bash

# Helper to fetch the given ubuntu cloud image, and verify its signatures against the key file in
# the repository.  Requires mktemp, gpg2/gpgv2, wget
#
# The ultimate effect of this script is roughly:
#   wget https://partner-images.canonical.com/core/unsupported/precise/current/ubuntu-precise-core-cloudimg-${ARCH}-root.tar.gz
#   wget https://partner-images.canonical.com/core/unsupported/precise/current/SHA256SUMS
#   wget https://partner-images.canonical.com/core/unsupported/precise/current/SHA256SUMS.gpg
#
# ... Followed by the necessary gpg and sha256sum commands to ensure the image checksum & signature
# matches ./ubuntu-cloud-key.txt (see verify() below)
#
# See README.md for more information
set -eu

# Output helpers
COLOR_ERR=""
COLOR_STAT=""
COLOR_CLEAR=""
if [[ $(tput colors 2>/dev/null || echo 0) -gt 0 ]]; then
  COLOR_ERR=$'\e[31;1m'
  COLOR_STAT=$'\e[32;1m'
  COLOR_CLEAR=$'\e[0m'
fi

err() { echo >&2 "${COLOR_ERR}!!${COLOR_CLEAR} $*"; }
stat() { echo >&2 "${COLOR_STAT}::${COLOR_CLEAR} $*"; }
die() { err "$@"; exit 1; }
finish() { stat "$@"; exit 0; }

# Argument
[[ $# -eq 1 && ( $1 = amd64 || $1 = i386 ) ]] || die "Usage: $0 { amd64 | i386 }"
ARCH="$1"
BASE_URL=https://partner-images.canonical.com/core/unsupported/precise/current
OWD="$(readlink -f "$(dirname "$0")")"
KEYFILE="$OWD/ubuntu-cloud-key.txt"
IMAGE_NAME="ubuntu-precise-core-cloudimg-${ARCH}-root.tar.gz"
SHA_FILE="${IMAGE_NAME}-SHA256SUMS"
SIG_FILE="${IMAGE_NAME}-SHA256SUMS.gpg"

if command -v gpg2 >/dev/null; then
  gpg2=gpg2
elif command -v gpg >/dev/null; then
  gpg2=gpg
else
  die "gpg2 not found, please install the gnupg2 or gnupg (>= 2) package"
fi

if command -v gpgv2 >/dev/null; then
  gpgv2=gpgv2
elif command -v gpgv >/dev/null; then
  gpgv2=gpgv
else
  die "gpgv2 not found, please install the gpgv2 or gpgv (>= 2) package"
fi

# Make sure the keyfile is there
[[ -f "$KEYFILE" ]] || die "Missing required file $KEYFILE"

# Setup temp directory
unset tmpdir
cleanup() { [[ -z $tmpdir || ! -d $tmpdir ]] || rm -rf "$tmpdir"; }
trap cleanup EXIT
tmpdir="$(mktemp -d --tmpdir steam-runtime-fetch-cloudimg-XXX)"
[[ -n $tmpdir && -d $tmpdir ]] || die "Failed to create temporary directory"
cd "$tmpdir"

# Checks signatures
verify() {
  local targetdir="$1"
  # Import plaintext key
  $gpg2 --batch --no-default-keyring --keyring ./ubuntu-cloud-key.gpg --import --armor --skip-verify < "$KEYFILE"
  if $gpgv2 --keyring ./ubuntu-cloud-key.gpg "$targetdir"/"$SIG_FILE" "$targetdir"/"$SHA_FILE"; then
    stat "SHA256SUMS file signature matches, checking checksum"
  else
    err "$gpgv2: Signature verification failed"
    return 1
  fi

  (
    cd "$targetdir"
    if sha256sum --ignore-missing -c ./"$SHA_FILE"; then
      stat "Image checksum matches"
    else
      die "sha256sum: Couldn't verify image checksum"
    fi
  ) || return 1
}

# Do we have any files already for this arch?
have_image() { [[ -f $OWD/$IMAGE_NAME ]]; }
have_sigfiles() { [[ -f $OWD/$SHA_FILE && -f $OWD/$SIG_FILE ]]; }
if have_image && have_sigfiles; then
  # Have the image and files already, re-validate signature
  stat "Image already exists, verifying signature"
  if verify "$OWD"; then
    finish "Image already exists and signature appears valid.  Remove to force re-download ($IMAGE_NAME)"
  else
    die "Image already exists, but could not validate signature, see above.  Remove to force re-download ($IMAGE_NAME)"
  fi
elif have_image; then
  # Image, no sigfiles
  die "Image already exists, but no SHA256SUMS files exist to validate signature.  Remove to force re-download ($IMAGE_NAME)."
elif have_sigfiles; then
  # No image, make sure we're not stomping sig files
  die "No image downloaded, but signature files exist.  Remove these to force re-download ($SHA_FILE / $SIG_FILE)"
fi

# No state, fetch items to tmpdir
(
  stat "Downloading image ($IMAGE_NAME)"
  wget "$BASE_URL"/"$IMAGE_NAME"  -O ./"$IMAGE_NAME"

  stat "Downloading checksum file ($SHA_FILE)"
  wget "$BASE_URL"/SHA256SUMS     -O ./"$SHA_FILE"

  stat "Downloading checksum signature ($SIG_FILE)"
  wget "$BASE_URL"/SHA256SUMS.gpg -O ./"$SIG_FILE"
) || die "Failed to fetch cloud image from \"$BASE_URL\", see above"

# Verify
verify . || die "Failed to verify signature on download image, see above"

# Looks good, move back to source directory
stat "Image downloaded & verified, moving to destination"
(
  # mv -n still exits with success if target exists, so check that it moved the thing.
  mv -nv ./"$IMAGE_NAME" "$OWD"/"$IMAGE_NAME" && [[ ! -f ./$IMAGE_NAME ]]
  mv -nv ./"$SHA_FILE" "$OWD"/"$SHA_FILE"     && [[ ! -f ./$SHA_FILE ]]
  mv -nv ./"$SIG_FILE" "$OWD"/"$SIG_FILE"     && [[ ! -f ./$SIG_FILE ]]
) || die "Failed to move downloaded image back to working directory ($OWD)"

finish "Successfully download & verified signature of image: $IMAGE_NAME"
