# Charcoal SteamOS Kernel - Vulcano Edition 
BEFORE INSTALLING, PLEASE CHECK IF YOU'RE ON THE STEAMOS STABLE CHANNEL 
[![build](https://github.com/zarpon/linux-charcoal-vulcano/actions/workflows/push.yml/badge.svg)](https://github.com/zarpon/linux-charcoal-vulcano/actions)

[Português (Brasil)](README.pt-BR.md)

Charcoal Vulcano is an experimental kernel package for Steam Deck, Asus ROG Ally, and
other AMD handheld PCs. It is built from Valve's
[`linux-neptune`](https://gitlab.steamos.cloud/jupiter/linux-integration)
source with a source-locked set of scheduler, memory, I/O, wireless, and
handheld-specific changes.

> **Current build target:** the newest Valve tag matching
> `6.16.12-valve*`. A release includes the exact source revision and dynamic
> patch selection used for that build.

## Supported Devices

| Device | Status | Notes |
| --- | --- | --- |
| Steam Deck (LCD) | ✅ Tested | Primary target |
| Steam Deck (OLED) | ✅ Tested | Primary target |
| Asus ROG Ally (RC71L) | ✅ Tested | Community-confirmed |
| Other AMD handhelds | ❓ Untested | Please report your result in an issue |

## Applied Patches and Configuration

The release workflow resolves the maintained patch components below before
building. The resulting release archive contains `patch-lock.json`, which is
the authoritative record of the exact patch paths, commits, origins, and
SHA-256 values.

| Component | What is applied in Charcoal |
| --- | --- |
| [LRU Marie](https://github.com/firelzrd/lru_marie) | Enables the LRU Marie memory-reclaim path (`CONFIG_LRU_MARIE=y`). |
| [zram-ir](https://github.com/firelzrd/zram-ir) | Adds immediate zram recompression control through `vm.zram_recomp_immediate`. A packaged `zram-generator` drop-in overrides the SteamOS `zstd` primary setting before `zram0` is initialized: LZ4 is the primary compressor and ZSTD is recompression priority `1`. A `systemd-zram-setup@` `ExecStartPre` runs the same setup before `disksize`, making the configuration deterministic even if an older generator does not configure secondary algorithms. The udev helper reasserts the sysctl and provides a safe fallback; it never resets an initialized device or active swap and does not create an additional zram swap device. |
| [ADIOS](https://github.com/firelzrd/adios) | Adds the Adaptive Deadline I/O Scheduler and makes it the default MQ I/O scheduler. The packaged udev rule also selects `adios` for supported block devices, excluding loop and zram devices. |
| [BORE Scheduler 6.6.3](https://github.com/firelzrd/bore-scheduler/tree/main/patches/stable/linux-6.18-bore) | Enables the Burst-Oriented Response Enhancer CPU scheduler (`CONFIG_SCHED_BORE=y`) through the reviewed 6.16.12 Valve port of the current upstream BORE 6.18 patch. |
| [POC Selector](https://github.com/firelzrd/poc-selector) | Enables bitmap-based idle-CPU selection (`CONFIG_SCHED_POC_SELECTOR=y`) for the task wake-up path. |
| [Nap](https://github.com/firelzrd/nap) | Enables the Neural Adaptive Predictor CPU-idle governor. The Charcoal fragment disables the ladder, menu, and teo governors and enables NAP. |

For components with an official 6.16-compatible patch, the resolver fetches
the newest matching upstream patch. When an approved 6.16.12 port is required,
the build uses the repository's local port while recording the newer upstream
source it follows in `patch-lock.json`. BORE is tracked from
`firelzrd/bore-scheduler`'s stable Linux 6.18 directory and applied through
the reviewed local 6.16.12 Valve port.

### Other Included Changes

- **Vangogh limits:** raises the exposed CPU soft maximum from 3.5 GHz to
  4.2 GHz and the reported PPT maximum from 29 W to 50 W.
- **Compiler and CPU configuration:** Clang/LLVM build, full Clang LTO, Polly,
  and Zen 2 as the minimum CPU target.
- **Static source patches:** selected Linux-TKG, Gentoo, CachyOS, OpenWrt,
  Qualcomm ath11k, and pinned Zen Kernel patches. They cover, among other
  things, futex waitv/fsync support, compiler and DKMS compatibility, Wi-Fi
  fixes, and build optimization.
- **Kernel configuration:** sound-input validation, debugging overhead, and
  selected legacy or unused drivers and subsystems are disabled.
- **Persistent runtime tuning:** installs VM and writeback sysctls, transparent
  huge-page and MGLRU boot settings, KSM disabled at boot, and the Steam-session
  Mesa shader-cache settings.

> **Security trade-off:** Charcoal explicitly sets
> `CONFIG_CPU_MITIGATIONS=n`. CPU vulnerability mitigations are disabled;
> install it only on a device and threat model where that trade-off is
> acceptable.

### Bundled Modules

These external modules are built into the packages, so no separate DKMS
installation is required:

| Module | Purpose |
| --- | --- |
| [ryzen_smu](https://github.com/amkillam/ryzen_smu) | Ryzen SMU access for power monitoring and controls. |
| [xone](https://github.com/dlundqvist/xone) | Xbox One wireless-dongle driver. |
| [xpad-noone](https://github.com/forkymcforkface/xpad-noone) | Lets xone/xpadneo handle controllers instead of the conflicting xpad driver. |
| [xpadneo](https://github.com/atar-axis/xpadneo) | Advanced Xbox controller driver. |

## Install

Run this in SteamOS Desktop Mode:

```bash
curl -fsSL https://raw.githubusercontent.com/zarpon/linux-charcoal-vulcano/master/install-charcoal.sh -o install-charcoal.sh && bash install-charcoal.sh
```

The installer always retrieves the [latest published
release](https://github.com/zarpon/linux-charcoal-vulcano/releases/latest). Before
calling `pacman`, it verifies the release ZIP SHA-256 and the SHA-256 of each
package inside it. It then enables SteamOS Developer Mode non-interactively to
initialize `pacman`, installs the Charcoal kernel and headers packages, and
updates the bootloader configuration. It prefers `grub-mkconfig`, then
`steamos-update-grub`, then `update-grub`; it stops instead of reporting
success if none is available. It deliberately reinstalls the verified packages
when necessary, because Charcoal release revisions can change while the Valve
base kernel version remains the same.

Developer Mode remains enabled after installation; only the SteamOS root
filesystem is restored to read-only mode, including when the package
transaction or bootloader update fails.

Confirm the replacement of `linux-neptune` if pacman asks. Then reboot and
verify:

```bash
uname -a  # should contain "charcoal"
```

The installer intentionally does not reset the active zram swap, because the
kernel does not permit changing its compressor after initialization. The LZ4
primary compressor and ZSTD priority-`1` recompressor apply on the first boot
into Charcoal. Verify them after that reboot:

```bash
cat /sys/block/zram0/comp_algorithm
cat /sys/block/zram0/recomp_algorithm
```

`[lz4]` marks the selected primary compressor. In `recomp_algorithm`, ZSTD is
shown in the priority-`1` row.

You can also see the kernel version in Gaming Mode under
**Settings → System**.

![Kernel version shown in SteamOS Gaming Mode under Settings → System](https://i.ibb.co/KzRyb2j7/20260525103630-1.jpg)

SteamOS updates can replace the installed kernel. After an update, check
`uname -a` and run the installer again if `charcoal` is no longer present.

## Uninstall

To remove Charcoal and return to the stock Neptune kernel:

```bash
sudo steamos-readonly disable
_neptune=$(pacman -Qi $(pacman -Qq 'linux-charcoal*') | awk '/^Replaces/{print $3}')
sudo pacman -Rsn $(pacman -Qq 'linux-charcoal*')
sudo pacman -S "$_neptune"
sudo steamos-readonly enable
```

Then reboot.

## Build from Source

Docker provides the expected Arch Linux build environment:

```bash
git clone https://github.com/zarpon/linux-charcoal-vulcano.git
cd linux-charcoal-vulcano
docker build -t linux-charcoal .
docker run --rm -it -v "$PWD:/project" linux-charcoal bash
```

Inside the container, resolve the current patch set before building:

```bash
cd /project
python3 automation/resolve-latest-patches.py --write
makepkg -s
```

The resolver writes the selected `latest-*.patch` files, updates
`PKGBUILD`, and creates `logs/patch-lock.json`. Review those generated
changes before distributing a local build. The GitHub workflow performs the
same resolution and checksum validation before packaging a release.

## Manual GitHub Build

To create a fresh build from the current patch set without changing the
repository, open [Build latest SteamOS Charcoal kernel](https://github.com/zarpon/linux-charcoal-vulcano/actions/workflows/push.yml), click **Run workflow**, and select `master`.

- Keep **Publish the compiled packages as a GitHub release** enabled to create
  a normal downloadable release after all checks pass.
- Disable it to validate a build only. The packages and patch lock are then
  available as workflow artifacts for 14 days; no GitHub release is created.

Every manual run resolves the newest compatible upstream patches first and
records their exact commits and SHA-256 values in `patch-lock.json`.

You can also build directly on an Arch-based system. Required dependencies
include `llvm`, `clang`, `lld`, `polly`, `bc`, `cpio`, `pahole`,
`python`, `git`, and `openssh`; see `PKGBUILD` for the complete list.

## Contributing

Report bugs and device-compatibility results in the
[issue tracker](https://github.com/zarpon/linux-charcoal-vulcano/issues). Pull
requests should target `master`. For a patch or configuration change, include
the source, target-kernel compatibility, and validation result.
