#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INSTALLER="$REPO_ROOT/install-charcoal.sh"

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
    '#!/usr/bin/env bash' \
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
    '#!/usr/bin/env bash' \
    'exec "$@"' \
    > "$bin_dir/sudo"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "steamos-readonly %s\\n" "$*" >> "$CHARCOAL_TEST_LOG"' \
    > "$bin_dir/steamos-readonly"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    '[[ "$1" == "-U" && "$2" == "--needed" ]] || exit 4' \
    'for package in "${@:3}"; do' \
    '  [[ -f "$package" ]] || exit 5' \
    'done' \
    'printf "pacman %s\\n" "$*" >> "$CHARCOAL_TEST_LOG"' \
    '[[ "${CHARCOAL_TEST_SCENARIO:-normal}" != "pacman-failure" ]] || exit 6' \
    > "$bin_dir/pacman"

  chmod +x "$bin_dir/curl" "$bin_dir/sudo" "$bin_dir/steamos-readonly" "$bin_dir/pacman"
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
assert_contains 'pacman -U --needed'
assert_contains 'linux-charcoal-616-9.9.9-1-x86_64.pkg.tar.zst'
assert_contains 'linux-charcoal-616-headers-9.9.9-1-x86_64.pkg.tar.zst'
assert_contains 'steamos-readonly enable'

: > "$log_file"
if run_installer bad-checksum >/dev/null 2>&1; then
  fail 'installer accepted a release ZIP with an invalid checksum'
fi
assert_not_contains 'steamos-readonly'
assert_not_contains 'pacman'

: > "$log_file"
if run_installer bad-package-checksum >/dev/null 2>&1; then
  fail 'installer accepted a package that did not match SHA256SUMS'
fi
assert_not_contains 'steamos-readonly'
assert_not_contains 'pacman'

: > "$log_file"
if run_installer pacman-failure >/dev/null 2>&1; then
  fail 'installer reported success after a pacman failure'
fi
assert_contains 'steamos-readonly disable'
assert_contains 'pacman -U --needed'
assert_contains 'steamos-readonly enable'

printf 'install-charcoal tests passed\n'
