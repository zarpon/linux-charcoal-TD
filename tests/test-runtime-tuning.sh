#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/configure-zram-ir"
zram_generator_dropin="$root/90-charcoal-zram.conf"
zram_setup_dropin="$root/90-charcoal-zram-ir.conf"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

fail() {
  echo "runtime tuning validation failed: $*" >&2
  exit 1
}

require_line() {
  local file="$1"
  local line="$2"
  grep -Fxq -- "$line" "$file" || fail "missing '$line' in ${file#$root/}"
}

require_value() {
  local file="$1"
  local value="$2"
  [[ "$(<"$file")" == "$value" ]] || fail "expected '$value' in $file"
}

bash -n "$root/PKGBUILD"
sh -n "$helper"

require_line "$zram_generator_dropin" "[zram0]"
require_line "$zram_generator_dropin" "compression-algorithm = lz4 zstd"
require_line "$zram_setup_dropin" "[Service]"
require_line "$zram_setup_dropin" "ExecStartPre=/usr/lib/charcoal/configure-zram-ir %I"

# SteamOS configures zram0 with zstd in its main generator configuration.
# A zram-generator *.conf.d entry has higher precedence; verify the Charcoal
# drop-in changes only the compressor and preserves Valve's size/swap policy.
python3 - "$zram_generator_dropin" <<'PY'
import configparser
import sys

base = """\
[zram0]
zram-size = ram/2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
"""

parser = configparser.ConfigParser(interpolation=None)
parser.read_string(base)
parser.read(sys.argv[1], encoding="utf-8")

zram0 = parser["zram0"]
assert zram0["compression-algorithm"] == "lz4 zstd"
assert zram0["zram-size"] == "ram/2"
assert zram0["swap-priority"] == "100"
assert zram0["fs-type"] == "swap"
PY

require_line "$root/99-charcoal-sysctl.conf" "vm.min_free_kbytes=262144"
require_line "$root/99-charcoal-sysctl.conf" "vm.compaction_proactiveness=15"
require_line "$root/99-charcoal-sysctl.conf" "vm.dirty_expire_centisecs=3500"
require_line "$root/99-charcoal-sysctl.conf" "vm.dirty_writeback_centisecs=500"
require_line "$root/99-charcoal-sysctl.conf" "vm.watermark_boost_factor=0"
require_line "$root/99-charcoal-sysctl.conf" "vm.watermark_scale_factor=125"
require_line "$root/99-charcoal-sysctl.conf" "kernel.split_lock_mitigate=0"
require_line "$root/99-charcoal-sysctl.conf" "vm.dirty_background_bytes=209715200"
require_line "$root/99-charcoal-sysctl.conf" "vm.dirty_bytes=409430400"
require_line "$root/99-charcoal-sysctl.conf" "vm.vfs_cache_pressure=125"
require_line "$root/99-charcoal-sysctl.conf" "-vm.zram_recomp_immediate=1"

require_line "$root/99-charcoal-gaming.conf" "MESA_SHADER_CACHE_MAX_SIZE=10G"
require_line "$root/99-charcoal-gaming.conf" "MESA_DISK_CACHE_DATABASE=1"
require_line "$root/99-charcoal.sh" "export MESA_SHADER_CACHE_MAX_SIZE=10G"
require_line "$root/99-charcoal.sh" "export MESA_DISK_CACHE_DATABASE=1"

require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/transparent_hugepage/khugepaged/defrag - - - - 0"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 64"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap - - - - 0"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/ksm/run - - - - 0"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/lru_gen/enabled - - - - 7"
require_line "$root/99-charcoal-memory.conf" "w! /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 0"

require_line "$root/config-charcoal" "CONFIG_ZRAM_DEF_COMP_LZ4=y"
require_line "$root/config-charcoal" "# CONFIG_ZRAM_DEF_COMP_ZSTD is not set"
require_line "$root/config-charcoal" 'CONFIG_ZRAM_DEF_COMP="lz4"'
require_line "$root/config" "CONFIG_ZRAM_BACKEND_LZ4=y"
require_line "$root/config" "CONFIG_ZRAM_BACKEND_ZSTD=y"
require_line "$root/config" "CONFIG_ZRAM_MULTI_COMP=y"
grep -Fq 'zram_recomp_immediate' "$root/0001-linux6.16.12-zram-ir-1.2.patch" || fail "ZRAM-IR sysctl patch is missing"
grep -Fq '/usr/lib/charcoal/configure-zram-ir' "$root/60-charcoal-zram-ir.rules" || fail "udev helper path is missing"
grep -Fq 'ACTION=="add"' "$root/60-charcoal-zram-ir.rules" || fail "udev add rule is missing"
grep -Fq 'ACTION=="change"' "$root/60-charcoal-zram-ir.rules" || fail "udev change rule is missing"
grep -Fq 'algo=zstd priority=1' "$helper" || fail "zstd priority-1 setup is missing"
grep -Fq 'lz4 > "$sys/comp_algorithm"' "$helper" || fail "lz4 primary setup is missing"

for package_path in \
  'usr/lib/sysctl.d/99-charcoal.conf' \
  'usr/lib/tmpfiles.d/99-charcoal-memory.conf' \
  'usr/lib/environment.d/99-charcoal-gaming.conf' \
  'usr/lib/udev/rules.d/60-charcoal-zram-ir.rules' \
  'usr/lib/charcoal/configure-zram-ir' \
  'usr/lib/systemd/zram-generator.conf.d/90-charcoal-zram.conf' \
  'usr/lib/systemd/system/systemd-zram-setup@.service.d/90-charcoal-zram-ir.conf'; do
  grep -Fq "\$pkgdir/$package_path" "$root/PKGBUILD" || fail "package install missing: $package_path"
done

# Validate every tracked local source checksum, including the runtime payload.
source "$root/PKGBUILD"
for index in "${!source[@]}"; do
  candidate="${source[$index]%%::*}"
  [[ -f "$root/$candidate" ]] || continue
  [[ "${sha256sums[$index]}" != "SKIP" ]] || fail "local source has SKIP checksum: $candidate"
  actual="$(sha256sum "$root/$candidate" | awk '{print $1}')"
  [[ "$actual" == "${sha256sums[$index]}" ]] || fail "SHA-256 mismatch: $candidate"
done

# Exercise the exact helper against regular files standing in for sysfs/procfs.
mkdir -p "$sandbox/sys/block/zram0" "$sandbox/proc/sys/vm" "$sandbox/bin"
printf '0\n' > "$sandbox/sys/block/zram0/initstate"
printf 'zstd lz4\n' > "$sandbox/sys/block/zram0/comp_algorithm"
printf 'zstd lz4\n' > "$sandbox/sys/block/zram0/recomp_algorithm"
printf '0\n' > "$sandbox/proc/sys/vm/zram_recomp_immediate"
printf '#!/bin/sh\nexit 0\n' > "$sandbox/bin/logger"
chmod +x "$sandbox/bin/logger"

PATH="$sandbox/bin:$PATH" \
  CHARCOAL_SYS_ROOT="$sandbox/sys" \
  CHARCOAL_PROC_SYS_ROOT="$sandbox/proc/sys" \
  sh "$helper" zram0
require_value "$sandbox/proc/sys/vm/zram_recomp_immediate" "1"
require_value "$sandbox/sys/block/zram0/comp_algorithm" "lz4"
require_value "$sandbox/sys/block/zram0/recomp_algorithm" "algo=zstd priority=1"

# A later udev change event must reassert the sysctl but leave active swap alone.
printf '1\n' > "$sandbox/sys/block/zram0/initstate"
printf 'already-active-primary\n' > "$sandbox/sys/block/zram0/comp_algorithm"
printf 'already-active-secondary\n' > "$sandbox/sys/block/zram0/recomp_algorithm"
printf '0\n' > "$sandbox/proc/sys/vm/zram_recomp_immediate"
PATH="$sandbox/bin:$PATH" \
  CHARCOAL_SYS_ROOT="$sandbox/sys" \
  CHARCOAL_PROC_SYS_ROOT="$sandbox/proc/sys" \
  sh "$helper" zram0
require_value "$sandbox/proc/sys/vm/zram_recomp_immediate" "1"
require_value "$sandbox/sys/block/zram0/comp_algorithm" "already-active-primary"
require_value "$sandbox/sys/block/zram0/recomp_algorithm" "already-active-secondary"

# Have systemd parse and apply the shipped tmpfiles payload in an isolated root.
if command -v systemd-tmpfiles >/dev/null 2>&1; then
  rootfs="$sandbox/rootfs"
  install -D -m 0644 "$root/99-charcoal-memory.conf" \
    "$rootfs/usr/lib/tmpfiles.d/99-charcoal-memory.conf"
  while read -r path; do
    install -D -m 0644 /dev/null "$rootfs$path"
  done <<'EOF'
/sys/kernel/mm/transparent_hugepage/enabled
/sys/kernel/mm/transparent_hugepage/defrag
/sys/kernel/mm/transparent_hugepage/shmem_enabled
/sys/kernel/mm/transparent_hugepage/khugepaged/defrag
/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap
/sys/kernel/mm/ksm/run
/sys/kernel/mm/lru_gen/enabled
/sys/kernel/mm/lru_gen/min_ttl_ms
EOF
  systemd-tmpfiles --create --boot --root="$rootfs"
  require_value "$rootfs/sys/kernel/mm/transparent_hugepage/enabled" "madvise"
  require_value "$rootfs/sys/kernel/mm/transparent_hugepage/defrag" "defer"
  require_value "$rootfs/sys/kernel/mm/transparent_hugepage/shmem_enabled" "advise"
  require_value "$rootfs/sys/kernel/mm/transparent_hugepage/khugepaged/defrag" "0"
  require_value "$rootfs/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none" "64"
  require_value "$rootfs/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap" "0"
  require_value "$rootfs/sys/kernel/mm/ksm/run" "0"
  require_value "$rootfs/sys/kernel/mm/lru_gen/enabled" "7"
  require_value "$rootfs/sys/kernel/mm/lru_gen/min_ttl_ms" "0"
fi

# Deterministic admission-control simulation for one 2 MiB x86 THP. This is
# not a hardware FPS benchmark: it proves that the shipped limits preserve a
# dense 64-hole candidate while excluding the sparse and swapped candidates
# that could add allocation or swap-in work to khugepaged.
python3 - "$root/99-charcoal-memory.conf" <<'PY'
from dataclasses import dataclass
from pathlib import Path
import sys

PTE_PER_THP = 512
PAGE_SIZE = 4096


def tmpfiles_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        fields = raw_line.split()
        if len(fields) == 7 and fields[0] == "w!":
            values[fields[1]] = fields[-1]
    return values


@dataclass(frozen=True)
class Policy:
    max_none: int
    max_swap: int


def eligible(policy: Policy, *, none: int, swap: int) -> bool:
    present = PTE_PER_THP - none - swap
    assert present >= 0
    return none <= policy.max_none and swap <= policy.max_swap


values = tmpfiles_values(Path(sys.argv[1]))
assert values["/sys/kernel/mm/transparent_hugepage/defrag"] == "defer"
proposed = Policy(
    max_none=int(values["/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none"]),
    max_swap=int(values["/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap"]),
)
assert proposed == Policy(max_none=64, max_swap=0)

legacy = Policy(max_none=409, max_swap=16)
assert eligible(legacy, none=64, swap=0)
assert eligible(proposed, none=64, swap=0)
assert eligible(legacy, none=409, swap=0)
assert not eligible(proposed, none=409, swap=0)
assert eligible(legacy, none=0, swap=16)
assert not eligible(proposed, none=0, swap=16)

legacy_zero_fill = legacy.max_none * PAGE_SIZE
proposed_zero_fill = proposed.max_none * PAGE_SIZE
legacy_swap_bytes = legacy.max_swap * PAGE_SIZE
proposed_swap_bytes = proposed.max_swap * PAGE_SIZE
assert legacy_zero_fill - proposed_zero_fill == 1_413_120
assert legacy_swap_bytes - proposed_swap_bytes == 65_536

print(
    "THP admission simulation passed: zero-fill cap "
    f"{legacy_zero_fill / 1024**2:.2f} MiB -> "
    f"{proposed_zero_fill / 1024**2:.2f} MiB; "
    f"swap candidate cap {legacy_swap_bytes // 1024} KiB -> "
    f"{proposed_swap_bytes // 1024} KiB"
)
PY

echo "runtime tuning validation passed"
