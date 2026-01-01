# Copilot Instructions for arch-install-v2

- Scope: single Bash script `arch-install-guided_Version2.sh`; assists with guided disk prep on Arch live ISO. No package install (pacstrap) or chroot config done here.
- Runtime expectations: run as root in UEFI live environment. Script exits if not root or if `/sys/firmware/efi` missing. Do not run on a system you are not ready to repartition/format.
- Safety: `set -euo pipefail` and strict `IFS` are intentional; keep them. Cleanup trap unmounts `/mnt` and swap on exit—preserve when editing. Default confirmation is "No"; preserve that behavior to avoid accidental formatting.
- Interaction flow: header → command checks → optional `cfdisk` → partition selections via `lsblk` + `blkid` → summary confirmation → mount-status precheck → formatting (`mkfs.fat`, `mkfs.ext4`, `mkswap`) → mount `/mnt`, `/mnt/boot/efi`, `/mnt/home`, `swapon` → optional `genfstab`. Keep prompts and Spanish messaging consistent.
- Partition handling: variables `ROOT_PART`, `EFI_PART`, `HOME_PART`, `SWAP_PART`; `ROOT_PART` mandatory. `select_partition()` confirms each entry; respect its pattern if adding new mountpoints.
- Conventions: messages are Spanish; keep tone concise. Use `confirm` helper for yes/no. Use `pause` only when staying in the same step after non-fatal issues. Echo important warnings before destructive actions.
- Extensibility: if adding steps (e.g., btrfs, luks), mirror existing confirmation and safety checks; ensure mountpoints created under `/mnt`. Any new destructive action should surface a clear warning before execution.
- External commands assumed available in the Arch live ISO: `lsblk`, `cfdisk`, `mkfs.fat`, `mkfs.ext4`, `mkswap`, `swapon`, `mount`, `blkid`, `genfstab`. `check_commands` emits warnings only; maintain that behavior.
- Output: uses `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT` for status; preserve format for predictability. `header()` clears screen—keep for readability in TTY.
- Testing/verification: primary way is dry review; true execution requires Arch live ISO with block devices. For changes that alter formatting/mount logic, review for unintended mounts and ensure trap still safe.
- Project hygiene: keep ASCII where possible; file currently contains Spanish accents—add only when necessary. No existing CI/tests. Keep single-file structure unless there is a compelling reason; otherwise document new files here.
- If you change prompts, re-read flow to ensure default paths and safety confirmations still lead to deliberate formatting only.
