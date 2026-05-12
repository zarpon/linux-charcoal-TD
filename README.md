# Charcoal SteamOS Kernel turbo Decky edition from. 
[![build](https://github.com/V10lator/linux-charcoal/actions/workflows/push.yml/badge.svg)](https://github.com/V10lator/linux-charcoal/actions)

Works on Steam Deck and possibly other AMD based handheld PCs.

# Changes to Neptune
- Add WiFi patches from OpenWRT
- Change maximum allowed CPU frequency on Steam Deck from 3.5 to 4.2 GHz (as requested on Discord)
- Change maximum PPT limit on Steam Deck from 30 to 50 watt (as requested at #5)
- Add wait on multiple futexes opcode for fsync (from tkg)
- Add [ADIOS](https://github.com/firelzrd/adios)
- Switch default DRM scheduling policy to round-robin
- Optimize kernel with -O3 (from tkg)
- Optimize for Zen 2 (from Gentoo)
- Build with LLVM + LTO + polly
- Build-in various always needed modules for LTO to shine even more
- Disable a lot of debugging
- Disable CPU mitigations
- Disable sound input validation
- Disable various unneeded things (open a bug report in case something you need is missing)
- Switch CPU IDLE sheduler
- Add some Clear Linux patches (from tkg)
- Add some Zen Linux patches
- Small fixes (from Gentoo)
- Fix dkms with LLVM clang (from CachyOS)
- Add [ryzen_smu](https://github.com/amkillam/ryzen_smu)
- Add [xone](https://github.com/dlundqvist/xone), [xpad-noone](https://github.com/forkymcforkface/xpad-noone) and [xpadneo](https://github.com/atar-axis/xpadneo)

Adicionados patch re-swappiness
(https://github.com/firelzrd/re-swappiness)

Adicionado Kcompressd-unofficial 
(https://github.com/firelzrd/kcompressd-unofficial)

Add poc selector
(https://github.com/firelzrd/poc-selector) 

# Install

```
cd ~/Downloads
sudo steamos-readonly disable
sudo pacman -U linux-charcoal-*-x86_64.pkg.tar.zst # Confirm when it asks you to remove linux-neptune-*
sudo steamos-readonly enable
rm linux-charcoal*
```
Note that you'll see erros like `==> ERROR: module not found: 'ata_generic'` but these are really just bad worded harmless warnings.
Reboot and check `uname -a` to see the new kernel. If the string contains `charcoal` installation worked correctly.
