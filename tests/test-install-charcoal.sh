#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INSTALLER="$REPO_ROOT/install-charcoal.sh"
readonly BASH_BIN="$(command -v bash)"

test_root="$(mktemp -d)"
fixture_dir="$test_root/fixture"
bin_dir="$test_root/bin"
log_file="$test_root/commands.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local expected=$1
  grep -F -- "$expected" "$log_file" >/dev/null || fail "expected log entry: $expected"
}

assert_not_contains() {
  local unexpected=$1
  if grep -F -- "$unexpected" "$log_file" >/dev/null; then
    fail "unexpected log entry: $unexpected"
  fi
}

assert_precedes() {
  local before=$1
  local after=$2
  local before_line
  local after_line

  before_line="$(grep -n -m 1 -F -- "$before" "$log_file" || true)"
  after_line="$(grep -n -m 1 -F -- "$after" "$log_file" || true)"
  [[ -n "$before_line" ]] || fail "missing log entry: $before"
  [[ -n "$after_line" ]] || fail "missing log entry: $after"
  before_line=${before_line%%:*}
  after_line=${after_line%%:*}
  (( before_line < after_line )) || fail "expected '$before' before '$after'"
}

assert_log_line() {
  local expected=$1
  grep -Fx -- "$expected" "$log_file" >/dev/null || fail "expected log line: $expected"
}

assert_not_log_line() {
  local unexpected=$1
  if grep -Fx -- "$unexpected" "$log_file" >/dev/null; then
    fail "unexpected log line: $unexpected"
  fi
}

write_bootloader_command() {
  local directory=$1
  local name=$2

  printf '%s\n' \
    "#!$BASH_BIN" \
    'set -Eeuo pipefail' \
    'if (($#)); then' \
    '  printf "%s %s\\n" "${0##*/}" "$*" >> "$CHARCOAL_TEST_LOG"' \
    'else' \
    '  printf "%s\\n" "${0##*/}" >> "$CHARCOAL_TEST_LOG"' \
    'fi' \
    '[[ "${CHARCOAL_TEST_SCENARIO:-normal}" != "bootloader-failure" ]] || exit 7' \
    > "$directory/$name"
  chmod +x "$directory/$name"
}

write_sudo_command() {
  local directory=$1

  printf '%s\n' \
    "#!$BASH_BIN" \
    'exec "$@"' \
    > "$directory/sudo"
  chmod +x "$directory/sudo"
}

bootloader_case_index=0

run_bootloader_update_case() {
  local steamos_efi_dir=$1
  shift

  ((bootloader_case_index += 1))
  local case_bin="$test_root/bootloader-case-$bootloader_case_index"
  local updater
  mkdir -p "$case_bin"
  write_sudo_command "$case_bin"
  for updater in "$@"; do
    write_bootloader_command "$case_bin" "$updater"
  done

  (
    export PATH="$case_bin"
    export CHARCOAL_TEST_LOG="$log_file"
    export CHARCOAL_TEST_SCENARIO=normal
    source "$INSTALLER"
    _update_grub "$steamos_efi_dir"
  )
}

make_fixture() {
  local build_dir="$fixture_dir/build"
  local kernel_package="linux-charcoal-616-9.9.9-1-x86_64.pkg.tar.zst"
  local headers_package="linux-charcoal-616-headers-9.9.9-1-x86_64.pkg.tar.zst"

  mkdir -p "$build_dir" "$bin_dir"
  printf 'kernel fixture\n' > "$build_dir/$kernel_package"
  printf 'headers fixture\n' > "$build_dir/$headers_package"
  (
    cd "$build_dir"
    sha256sum "$kernel_package" "$headers_package" > SHA256SUMS
    zip -q "$fixture_dir/linux-charcoal-test.zip" SHA256SUMS "$kernel_package" "$headers_package"
  )
  (
    cd "$fixture_dir"
    sha256sum linux-charcoal-test.zip > RELEASE-ZIP-SHA256SUM
  )

  mkdir -p "$fixture_dir/bad-package"
  cp "$build_dir/$kernel_package" "$build_dir/$headers_package" "$fixture_dir/bad-package/"
  (
    cd "$fixture_dir/bad-package"
    printf '%064d  %s\n' 0 "$kernel_package" > SHA256SUMS
    sha256sum "$headers_package" >> SHA256SUMS
    zip -q "$fixture_dir/bad-package.zip" SHA256SUMS "$kernel_package" "$headers_package"
  )
  (
    cd "$fixture_dir"
    sha256sum bad-package.zip | sed 's/bad-package\.zip/linux-charcoal-test.zip/' > BAD-PACKAGE-RELEASE-ZIP-SHA256SUM
  )

  printf '%s\n' '{"tag_name":"charcoal-test","draft":false,"prerelease":false,"assets":[{"name":"linux-charcoal-test.zip","browser_download_url":"https://github.com/zarpon/linux-charcoal-TD/releases/download/charcoal-test/linux-charcoal-test.zip"},{"name":"RELEASE-ZIP-SHA256SUM","browser_download_url":"https://github.com/zarpon/linux-charcoal-TD/releases/download/charcoal-test/RELEASE-ZIP-SHA256SUM"}]}' > "$fixture_dir/release.json"
}

write_fake_commands() {
  printf '%s\n' \
    "#!$BASH_BIN" \
    'set -Eeuo pipefail' \
    'output=""' \
    'url=""' \
    'while (($#)); do' \
    '  case "$1" in' \
    '    --output|-o) output="$2"; shift 2 ;;' \
    '    *) url="$1"; shift ;;' \
    '  esac' \
    'done' \
    '[[ -n "$output" ]] || exit 2' \
    'case "$url" in' \
    '  https://api.github.com/repos/zarpon/linux-charcoal-TD/releases/latest)' \
    '    cp "$CHARCOAL_TEST_FIXTURE/release.json" "$output" ;;' \
    '  https://github.com/zarpon/linux-charcoal-TD/releases/download/charcoal-test/linux-charcoal-test.zip)' \
    '    if [[ "${CHARCOAL_TEST_SCENARIO:-normal}" == "bad-package-checksum" ]]; then' \
    '      cp "$CHARCOAL_TEST_FIXTURE/bad-package.zip" "$output"' \
    '    else' \
    '      cp "$CHARCOAL_TEST_FIXTURE/linux-charcoal-test.zip" "$output"' \
    '    fi ;;' \
    '  https://github.com/zarpon/linux-charcoal-TD/releases/download/charcoal-test/RELEASE-ZIP-SHA256SUM)' \
    '    if [[ "${CHARCOAL_TEST_SCENARIO:-normal}" == "bad-checksum" ]]; then' \
    '      printf "%064d  linux-charcoal-test.zip\\n" 0 > "$output"' \
    '    elif [[ "${CHARCOAL_TEST_SCENARIO:-normal}" == "bad-package-checksum" ]]; then' \
    '      cp "$CHARCOAL_TEST_FIXTURE/BAD-PACKAGE-RELEASE-ZIP-SHA256SUM" "$output"' \
    '    else' \
    '      cp "$CHARCOAL_TEST_FIXTURE/RELEASE-ZIP-SHA256SUM" "$output"' \
    '    fi ;;' \
    '  *) exit 3 ;;' \
    'esac' \
    > "$bin_dir/curl"

  printf '%s\n' \
    "#!$BASH_BIN" \
    'exec "$@"' \
    > "$bin_dir/sudo"

  printf '%s\n' \
    "#!$BASH_BIN" \
    'printf "steamos-readonly %s\\n" "$*" >> "$CHARCOAL_TEST_LOG"' \
    > "$bin_dir/steamos-readonly"

  printf '%s\n' \
    "#!$BASH_BIN" \
    'printf "steamos-devmode %s\\n" "$*" >> "$CHARCOAL_TEST_LOG"' \
    '[[ "${CHARCOAL_TEST_SCENARIO:-normal}" != "devmode-failure" ]] || exit 7' \
    > "$bin_dir/steamos-devmode"

  printf '%s\n' \
    "#!$BASH_BIN" \
    'set -Eeuo pipefail' \
    '[[ "$1" == "-U" && "$2" == "--needed" ]] || exit 4' \
    'for package in "${@:3}"; do' \
    '  [[ -f "$package" ]] || exit 5' \
    'done' \
    'printf "pacman %s\\n" "$*" >> "$CHARCOAL_TEST_LOG"' \
    '[[ "${CHARCOAL_TEST_SCENARIO:-normal}" != "pacman-failure" ]] || exit 6' \
    > "$bin_dir/pacman"

  write_bootloader_command "$bin_dir" grub-mkconfig
  chmod +x "$bin_dir/curl" "$bin_dir/sudo" "$bin_dir/steamos-readonly" "$bin_dir/steamos-devmode" "$bin_dir/pacman"
}

run_installer() {
  local scenario=$1
  PATH="$bin_dir:$PATH" \
    CHARCOAL_TEST_FIXTURE="$fixture_dir" \
    CHARCOAL_TEST_LOG="$log_file" \
    CHARCOAL_TEST_SCENARIO="$scenario" \
    bash "$INSTALLER"
}

make_fixture
write_fake_commands

: > "$log_file"
run_installer normal
assert_contains 'steamos-readonly disable'
assert_contains 'steamos-devmode enable --no-prompt'
assert_contains 'pacman -U --needed'
assert_contains 'linux-charcoal-616-9.9.9-1-x86_64.pkg.tar.zst'
assert_contains 'linux-charcoal-616-headers-9.9.9-1-x86_64.pkg.tar.zst'
assert_contains 'grub-mkconfig -o /boot/grub/grub.cfg'
assert_contains 'steamos-readonly enable'
assert_precedes 'steamos-readonly disable' 'steamos-devmode enable --no-prompt'
assert_precedes 'steamos-devmode enable --no-prompt' 'pacman -U --needed'
assert_precedes 'pacman -U --needed' 'grub-mkconfig -o /boot/grub/grub.cfg'
assert_precedes 'grub-mkconfig -o /boot/grub/grub.cfg' 'steamos-readonly enable'

: > "$log_file"
if run_installer bad-checksum >/dev/null 2>&1; then
  fail 'installer accepted a release ZIP with an invalid checksum'
fi
assert_not_contains 'steamos-readonly'
assert_not_contains 'steamos-devmode'
assert_not_contains 'pacman'

: > "$log_file"
if run_installer bad-package-checksum >/dev/null 2>&1; then
  fail 'installer accepted a package that did not match SHA256SUMS'
fi
assert_not_contains 'steamos-readonly'
assert_not_contains 'steamos-devmode'
assert_not_contains 'pacman'

: > "$log_file"
if run_installer pacman-failure >/dev/null 2>&1; then
  fail 'installer reported success after a pacman failure'
fi
assert_contains 'steamos-readonly disable'
assert_contains 'steamos-devmode enable --no-prompt'
assert_contains 'pacman -U --needed'
assert_contains 'steamos-readonly enable'

: > "$log_file"
if run_installer devmode-failure >/dev/null 2>&1; then
  fail 'installer reported success after a SteamOS developer mode failure'
fi
assert_contains 'steamos-readonly disable'
assert_contains 'steamos-devmode enable --no-prompt'
assert_not_contains 'pacman'
assert_not_contains 'grub-mkconfig'
assert_contains 'steamos-readonly enable'

: > "$log_file"
if run_installer bootloader-failure >/dev/null 2>&1; then
  fail 'installer reported success after a bootloader update failure'
fi
assert_contains 'steamos-readonly disable'
assert_contains 'steamos-devmode enable --no-prompt'
assert_contains 'pacman -U --needed'
assert_contains 'grub-mkconfig -o /boot/grub/grub.cfg'
assert_contains 'steamos-readonly enable'

: > "$log_file"
steam_efi_dir="$test_root/efi/EFI/steamos"
mkdir -p "$steam_efi_dir"
run_bootloader_update_case "$steam_efi_dir" grub-mkconfig steamos-update-grub update-grub
assert_log_line "grub-mkconfig -o $steam_efi_dir/grub.cfg"
assert_not_log_line 'steamos-update-grub'
assert_not_log_line 'update-grub'

: > "$log_file"
run_bootloader_update_case "$test_root/missing-steamos-efi" steamos-update-grub update-grub
assert_log_line 'steamos-update-grub'
assert_not_log_line 'update-grub'

: > "$log_file"
run_bootloader_update_case "$test_root/missing-steamos-efi" update-grub
assert_log_line 'update-grub'

: > "$log_file"
if run_bootloader_update_case "$test_root/missing-steamos-efi" >/dev/null 2>&1; then
  fail 'bootloader update reported success without a supported updater'
fi

printf 'install-charcoal tests passed\n'
