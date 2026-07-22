#!/usr/bin/env bash
# Install the latest published Charcoal SteamOS kernel release.

set -Eeuo pipefail

readonly REPOSITORY="zarpon/linux-charcoal-TD"
readonly RELEASE_API="https://api.github.com/repos/${REPOSITORY}/releases/latest"
readonly RELEASE_DOWNLOAD_PREFIX="https://github.com/${REPOSITORY}/releases/download/"
readonly USER_AGENT="charcoal-kernel-installer"

WORKDIR=""
MADE_ROOT_WRITABLE=0

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

run_privileged() {
  if (( EUID == 0 )); then
    command "$@"
  else
    sudo "$@"
  fi
}

cleanup() {
  local exit_status=$?
  trap - EXIT

  if (( MADE_ROOT_WRITABLE )); then
    info "Restoring SteamOS read-only mode..."
    if ! run_privileged steamos-readonly enable; then
      printf 'warning: could not restore SteamOS read-only mode; run sudo steamos-readonly enable manually.\n' >&2
      exit_status=1
    fi
  fi

  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf -- "$WORKDIR"
  fi

  exit "$exit_status"
}

download_file() {
  local url=$1
  local destination=$2

  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --retry 3 \
    --connect-timeout 15 \
    --output "$destination" \
    "$url"
}

parse_release_metadata() {
  local release_json=$1

  python3 - "$release_json" "$REPOSITORY" "$RELEASE_DOWNLOAD_PREFIX" <<'PY'
import json
import sys
from pathlib import PurePosixPath

release_json, repository, download_prefix = sys.argv[1:]

try:
    with open(release_json, encoding="utf-8") as handle:
        release = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"Could not parse the GitHub release response: {exc}")

if not isinstance(release, dict) or release.get("draft") or release.get("prerelease"):
    raise SystemExit("GitHub did not return a published stable release")

def text(value, label):
    if not isinstance(value, str) or not value or any(char in value for char in "\x00\r\n"):
        raise SystemExit(f"Invalid {label} in the GitHub release response")
    return value

def asset_url(asset, expected_name):
    name = text(asset.get("name"), "asset name")
    url = text(asset.get("browser_download_url"), "asset URL")
    if name != expected_name:
        raise SystemExit(f"Unexpected asset name: {name}")
    if not url.startswith(download_prefix):
        raise SystemExit(f"Refusing asset outside {repository} releases: {url}")
    return name, url

tag_name = text(release.get("tag_name"), "release tag")
assets = release.get("assets")
if not isinstance(assets, list):
    raise SystemExit("GitHub release has no assets")

archives = [asset for asset in assets if isinstance(asset, dict) and str(asset.get("name", "")).startswith("linux-charcoal-") and str(asset.get("name", "")).endswith(".zip")]
checksums = [asset for asset in assets if isinstance(asset, dict) and asset.get("name") == "RELEASE-ZIP-SHA256SUM"]

if len(archives) != 1:
    raise SystemExit("Expected exactly one linux-charcoal release ZIP")
if len(checksums) != 1:
    raise SystemExit("Expected exactly one RELEASE-ZIP-SHA256SUM asset")

archive_name, archive_url = asset_url(archives[0], text(archives[0].get("name"), "archive name"))
checksum_name, checksum_url = asset_url(checksums[0], "RELEASE-ZIP-SHA256SUM")

if PurePosixPath(archive_name).name != archive_name:
    raise SystemExit("Invalid release ZIP filename")

print(tag_name)
print(archive_name)
print(archive_url)
print(checksum_name)
print(checksum_url)
PY
}

verify_release_archive() {
  local archive=$1
  local checksum_file=$2
  local archive_name=$3

  python3 - "$archive" "$checksum_file" "$archive_name" <<'PY'
import hashlib
import re
import sys

archive, checksum_file, archive_name = sys.argv[1:]

try:
    lines = open(checksum_file, encoding="utf-8").read().splitlines()
except OSError as exc:
    raise SystemExit(f"Could not read release checksum: {exc}")

entries = []
for line in lines:
    match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", line)
    if not match:
        raise SystemExit("Invalid RELEASE-ZIP-SHA256SUM format")
    entries.append((match.group(1).lower(), match.group(2)))

if len(entries) != 1 or entries[0][1] != archive_name:
    raise SystemExit("Release checksum does not match the selected ZIP")

digest = hashlib.sha256()
with open(archive, "rb") as handle:
    for block in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(block)

if digest.hexdigest() != entries[0][0]:
    raise SystemExit("Release ZIP SHA-256 verification failed")
PY
}

extract_and_verify_packages() {
  local archive=$1
  local destination=$2

  python3 - "$archive" "$destination" <<'PY'
import hashlib
import re
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath

archive, destination = map(Path, sys.argv[1:])
package_pattern = re.compile(r"^linux-charcoal-[^/\\\x00\r\n]+\.pkg\.tar\.zst$")
checksum_pattern = re.compile(r"([0-9a-fA-F]{64}) [ *](linux-charcoal-[^/\\\x00\r\n]+\.pkg\.tar\.zst)")

try:
    with zipfile.ZipFile(archive) as handle:
        infos = handle.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            raise ValueError("release ZIP contains duplicate entries")

        if "SHA256SUMS" not in names:
            raise ValueError("release ZIP is missing SHA256SUMS")

        package_infos = [info for info in infos if package_pattern.fullmatch(info.filename)]
        package_names = {info.filename for info in package_infos}
        if not package_infos:
            raise ValueError("release ZIP contains no Charcoal packages")
        if not any("-headers-" not in name for name in package_names):
            raise ValueError("release ZIP is missing the kernel package")
        if not any("-headers-" in name for name in package_names):
            raise ValueError("release ZIP is missing the headers package")

        for info in [next(info for info in infos if info.filename == "SHA256SUMS"), *package_infos]:
            if PurePosixPath(info.filename).name != info.filename:
                raise ValueError(f"unsafe path in release ZIP: {info.filename}")
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError(f"symbolic link in release ZIP: {info.filename}")

        manifest = handle.read("SHA256SUMS").decode("utf-8")
        checksums = {}
        for line in manifest.splitlines():
            match = checksum_pattern.fullmatch(line)
            if not match:
                raise ValueError("invalid package SHA256SUMS format")
            digest, name = match.groups()
            if name in checksums:
                raise ValueError(f"duplicate checksum entry: {name}")
            checksums[name] = digest.lower()

        if set(checksums) != package_names:
            raise ValueError("package list does not exactly match SHA256SUMS")

        destination.mkdir(mode=0o700)
        checksum_target = destination / "SHA256SUMS"
        checksum_target.write_text(manifest, encoding="utf-8")

        for info in package_infos:
            package_target = destination / info.filename
            digest = hashlib.sha256()
            with handle.open(info) as source, package_target.open("xb") as target:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(block)
                    target.write(block)
            if digest.hexdigest() != checksums[info.filename]:
                package_target.unlink(missing_ok=True)
                raise ValueError(f"package SHA-256 verification failed: {info.filename}")
except (OSError, ValueError, zipfile.BadZipFile, UnicodeDecodeError) as exc:
    raise SystemExit(f"Could not verify release packages: {exc}")
PY
}

main() {
  require_command curl
  require_command python3
  require_command mktemp
  require_command pacman
  require_command steamos-readonly
  if (( EUID != 0 )); then
    require_command sudo
  fi

  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/charcoal-installer.XXXXXX")"
  trap cleanup EXIT

  info "Fetching the latest published Charcoal release..."
  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --retry 3 \
    --connect-timeout 15 \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --user-agent "$USER_AGENT" \
    --output "$WORKDIR/release.json" \
    "$RELEASE_API"

  local metadata
  if ! metadata="$(parse_release_metadata "$WORKDIR/release.json")"; then
    die "Could not identify the required assets in the latest release"
  fi

  local -a fields
  mapfile -t fields <<< "$metadata"
  (( ${#fields[@]} == 5 )) || die "Incomplete GitHub release metadata"

  local release_tag=${fields[0]}
  local archive_name=${fields[1]}
  local archive_url=${fields[2]}
  local checksum_name=${fields[3]}
  local checksum_url=${fields[4]}
  local archive_path="$WORKDIR/$archive_name"
  local checksum_path="$WORKDIR/$checksum_name"
  local package_dir="$WORKDIR/packages"

  info "Downloading release ${release_tag}..."
  download_file "$archive_url" "$archive_path"
  download_file "$checksum_url" "$checksum_path"

  info "Verifying release archive SHA-256..."
  verify_release_archive "$archive_path" "$checksum_path" "$archive_name"

  info "Extracting and verifying kernel package SHA-256 checksums..."
  extract_and_verify_packages "$archive_path" "$package_dir"

  local -a packages
  mapfile -d '' -t packages < <(find "$package_dir" -maxdepth 1 -type f -name 'linux-charcoal-*.pkg.tar.zst' -print0 | sort -z)
  (( ${#packages[@]} >= 2 )) || die "Verified release does not contain the expected kernel and headers packages"

  info "Making SteamOS writable for the package transaction..."
  run_privileged steamos-readonly disable
  MADE_ROOT_WRITABLE=1

  info "Installing ${release_tag}. Confirm the replacement of linux-neptune when pacman asks."
  run_privileged pacman -U --needed "${packages[@]}"

  info "Charcoal ${release_tag} was installed successfully. Reboot, then verify with: uname -r"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
