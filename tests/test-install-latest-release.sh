#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/install-latest-release.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

fail() {
  echo "latest-release installer validation failed: $*" >&2
  exit 1
}

[[ -x "$installer" ]] || fail "installer is not executable"
bash -n "$installer"
grep -Fq 'RELEASE-ZIP-SHA256SUM' "$root/.github/workflows/push.yml" \
  || fail "release workflow does not publish the ZIP checksum expected by the installer"

fixture="$sandbox/fixture"
mock_bin="$sandbox/bin"
state="$sandbox/state"
mkdir -p "$fixture" "$mock_bin" "$state"

zip_name="linux-charcoal-6.16.12.valve27.cc1-r1.zip"
zip_path="$fixture/$zip_name"
checksum_path="$fixture/RELEASE-ZIP-SHA256SUM"
release_json="$fixture/release.json"

python3 - "$zip_path" "$checksum_path" "$release_json" "$zip_name" <<'PY'
import hashlib
import json
import sys
import zipfile

zip_path, checksum_path, release_json, zip_name = sys.argv[1:]
packages = {
    "linux-charcoal-616-6.16.12.valve27.cc1-1-x86_64.pkg.tar.zst": b"kernel package\n",
    "linux-charcoal-616-headers-6.16.12.valve27.cc1-1-x86_64.pkg.tar.zst": b"headers package\n",
}
checksums = "".join(
    f"{hashlib.sha256(payload).hexdigest()}  {name}\n"
    for name, payload in sorted(packages.items())
)
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_STORED) as archive:
    archive.writestr("SHA256SUMS", checksums)
    for name, payload in packages.items():
        archive.writestr(name, payload)

with open(zip_path, "rb") as archive:
    archive_digest = hashlib.sha256(archive.read()).hexdigest()
with open(checksum_path, "w", encoding="utf-8") as output:
    output.write(f"{archive_digest}  {zip_name}\n")
with open(release_json, "w", encoding="utf-8") as output:
    json.dump(
        {
            "tag_name": "charcoal-test-r1",
            "assets": [
                {
                    "name": "RELEASE-ZIP-SHA256SUM",
                    "browser_download_url": "https://downloads.example/RELEASE-ZIP-SHA256SUM",
                },
                {
                    "name": zip_name,
                    "browser_download_url": f"https://downloads.example/{zip_name}",
                },
            ],
        },
        output,
    )
PY

cat >"$mock_bin/curl" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

output=""
url=""
while (($#)); do
  case "$1" in
    -o|--output)
      output="$2"
      shift 2
      ;;
    --)
      [[ $# -eq 2 ]] || {
        echo "curl URL must be the final argument" >&2
        exit 1
      }
      url="$2"
      break
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

case "$url" in
  "$CHARCOAL_RELEASE_API") cp -- "$FIXTURE_DIR/release.json" "$output" ;;
  "https://downloads.example/$ZIP_NAME") cp -- "$FIXTURE_DIR/$ZIP_NAME" "$output" ;;
  "https://downloads.example/RELEASE-ZIP-SHA256SUM") cp -- "$CHECKSUM_FILE" "$output" ;;
  *)
    echo "unexpected curl URL: $url" >&2
    exit 1
    ;;
esac
SH

cat >"$mock_bin/steamos-readonly" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  status) echo "${READONLY_STATUS:-enabled}" ;;
  disable|enable) printf '%s\n' "$1" >> "$READONLY_LOG" ;;
  *) exit 1 ;;
esac
SH

cat >"$mock_bin/pacman" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%q\n' "$@" > "$PACMAN_LOG"
exit "${PACMAN_EXIT:-0}"
SH

chmod +x "$mock_bin/curl" "$mock_bin/steamos-readonly" "$mock_bin/pacman"

run_installer() {
  local checksum_file="$1"
  local pacman_exit="${2:-0}"
  local readonly_status="${3:-enabled}"

  PATH="$mock_bin:$PATH" \
    CHARCOAL_REPOSITORY="zarpon/linux-charcoal-TD" \
    CHARCOAL_RELEASE_API="https://api.github.com/repos/zarpon/linux-charcoal-TD/releases/latest" \
    FIXTURE_DIR="$fixture" \
    ZIP_NAME="$zip_name" \
    CHECKSUM_FILE="$checksum_file" \
    PACMAN_LOG="$state/pacman.log" \
    READONLY_LOG="$state/readonly.log" \
    PACMAN_EXIT="$pacman_exit" \
    READONLY_STATUS="$readonly_status" \
    bash "$installer"
}

rm -f "$state/pacman.log" "$state/readonly.log"
run_installer "$checksum_path"

grep -Fxq -- '-U' "$state/pacman.log" || fail "pacman was not called with -U"
grep -Fxq -- '--needed' "$state/pacman.log" || fail "pacman was not called with --needed"
grep -Fq -- 'linux-charcoal-616-6.16.12.valve27.cc1-1-x86_64.pkg.tar.zst' "$state/pacman.log" \
  || fail "kernel package was not passed to pacman"
grep -Fq -- 'linux-charcoal-616-headers-6.16.12.valve27.cc1-1-x86_64.pkg.tar.zst' "$state/pacman.log" \
  || fail "headers package was not passed to pacman"
[[ "$(<"$state/readonly.log")" == $'disable\nenable' ]] \
  || fail "readonly mode was not restored after a successful install"

rm -f "$state/pacman.log" "$state/readonly.log"
run_installer "$checksum_path" 0 disabled
[[ ! -e "$state/readonly.log" ]] \
  || fail "installer changed a SteamOS filesystem that was already writable"

bad_checksum="$fixture/bad-RELEASE-ZIP-SHA256SUM"
printf '%064d  %s\n' 0 "$zip_name" >"$bad_checksum"
rm -f "$state/pacman.log" "$state/readonly.log"
if run_installer "$bad_checksum" >/dev/null 2>&1; then
  fail "installer accepted a ZIP with an invalid checksum"
fi
[[ ! -e "$state/pacman.log" ]] || fail "pacman ran after ZIP checksum validation failed"
[[ ! -e "$state/readonly.log" ]] || fail "readonly mode changed before ZIP checksum validation"

rm -f "$state/pacman.log" "$state/readonly.log"
if run_installer "$checksum_path" 42 >/dev/null 2>&1; then
  fail "installer accepted a failing pacman transaction"
fi
[[ "$(<"$state/readonly.log")" == $'disable\nenable' ]] \
  || fail "readonly mode was not restored after pacman failed"

echo "latest-release installer validation passed"
