# Copilot Instructions for arch-install-v2

## Project Structure

- **install-unified.sh**: Complete end-to-end Arch installer (partitions → base install → config → bootloader → users → optional DE). Single script approach using `arch-chroot` commands from live ISO.
- **install-simple.sh**: Simplified installer with basic pacstrap flow; prints manual chroot steps for user to execute.
- **00-disk-setup.sh**, **01-install-base.sh**, **02-bootloader.sh**, **03-users.sh**: Modular approach split across stages (legacy/experimental).

## Runtime Requirements

- Execute as root in UEFI live-ISO environment. Scripts exit if not root or `/sys/firmware/efi` missing.
- Requires internet connection for pacstrap; `install-unified.sh` validates connectivity at startup.
- Target system: UEFI boot only; mounts EFI at `/mnt/boot` (GRUB convention).

## Safety & Error Handling

- `set -euo pipefail` and strict `IFS` mandatory; preserve in all scripts.
- Cleanup trap unmounts `/mnt` and swap on exit/error—maintain this pattern when editing.
- Default confirmation is "No" (`[y/N]`) to prevent accidental destructive operations.
- All format/partition operations require explicit double confirmation with clear warnings shown before execution.

## Interaction Flow (install-unified.sh)

1. Initial checks: root, UEFI, commands, internet
2. Disk preparation: optional `cfdisk` → numeric partition selection (EFI, ROOT, HOME opt, SWAP opt) → format → mount
3. Base install: `pacstrap -K` with predefined package list → `genfstab`
4. System config via `arch-chroot /mnt /bin/bash -c "..."`: timezone, locale, hostname, hosts
5. Users: root password, new user with wheel/sudo
6. Bootloader: GRUB install with `GRUB_DISABLE_OS_PROBER=false` enabled for dual-boot
7. Network: enable NetworkManager
8. Optional: Desktop environment (Awesome/KDE/GNOME/XFCE) with audio
9. Optional: Extra packages (kitty, firefox, zsh, neovim, etc.)
10. Finalize: offer auto-reboot or manual cleanup instructions

## UI Conventions

- Box-drawing characters for headers (`╔═╗`, `┌─┐`) and section dividers
- Numeric menu selection for disks/partitions (no manual typing of `/dev/*` paths)
- Tabular partition display: `lsblk` output with formatted columns (Idx, Device, Size, FSType, Mount)
- Status symbols: `✓` (success), `✗` (error), `→` (info/prompt)
- Messages in Spanish; keep tone clear, concise, user-friendly
- Use `pause` only after important messages where user needs time to read; avoid blocking unnecessarily

## Partition Handling

- Variables: `ROOT_PART` (mandatory), `EFI_PART` (mandatory for UEFI), `HOME_PART` (optional), `SWAP_PART` (optional)
- `select_partition(label, varname, required)`: shows numbered list from `lsblk`, allows skip if `required=0`, confirms with `blkid` display
- Partitions selected via `mapfile` from `lsblk -rpno NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT` filtering `TYPE=part`
- Mount structure: `/mnt` (root), `/mnt/boot` (EFI), `/mnt/home` (home if used)

## Bootloader Configuration

- GRUB for UEFI: `grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB`
- Dual-boot support: `GRUB_DISABLE_OS_PROBER=false` appended to `/etc/default/grub`; `os-prober` runs before `grub-mkconfig`
- Must have `os-prober` and `ntfs-3g` in pacstrap package list for Windows detection

## Package Management

- Base packages: `base linux linux-firmware base-devel sudo vim nano neovim networkmanager wpa_supplicant grub efibootmgr os-prober ntfs-3g`
- Optional DEs: specify meta-packages + display manager (e.g., `plasma-meta sddm`, `gnome gdm`, `awesome lightdm`)
- Audio: `alsa-utils pulseaudio pulseaudio-alsa pavucontrol` with user added to `audio` group
- Extras: terminal emulators, browsers, CLI tools (kitty, firefox, zsh, lsd, bat, etc.)

## Chroot Command Pattern

- All post-install config runs from live-ISO via: `arch-chroot /mnt /bin/bash -c "command"`
- Multi-line commands use heredocs or semicolon chaining inside `-c` string
- Variables (e.g., `$USERNAME`, `$HOSTNAME`) expanded in outer shell; use single quotes in `-c` if passing literal

## Testing & Verification

- Primary test environment: VirtualBox VM with EFI enabled, clean virtual disk
- Dry-run review for logic/flow; actual execution requires bootable Arch ISO with network
- For formatting/mount changes: verify cleanup trap still safe, check no unintended mounts persist

## Extensibility

- To add filesystem types (btrfs, xfs): extend `select_partition()` with fs-specific format options; add subvolume logic if btrfs
- For LUKS: insert cryptsetup step after partition selection, before format; adjust mount commands to use mapper devices
- For swapfile (vs partition): add post-mount step to create/activate swapfile, skip SWAP_PART selection
- New destructive steps must: surface clear warning, require confirmation, integrate into cleanup trap if stateful

## File Hygiene

- Prefer ASCII where possible; Spanish text with accents allowed for UX clarity
- No CI/tests currently; rely on manual VM validation
- Single-script philosophy preferred (install-unified.sh is canonical); modular scripts kept for reference/experimentation
- If adding new files, document purpose and usage here
