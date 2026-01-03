#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Instalación completa de Arch Linux (UEFI) - Orquestador modular
# Ejecutar como root en el live-ISO de Arch Linux
# ============================================================================


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### VARIABLES GLOBALES ###
ROOT_PART=""
EFI_PART=""
HOME_PART=""
SWAP_PART=""
HOSTNAME="arch"
USERNAME="neo"
TIMEZONE="America/Lima"
LOCALE="en_US.UTF-8"

### CARGA DE MÓDULOS ###
source "${SCRIPT_DIR}/modules/ui.sh"
source "${SCRIPT_DIR}/modules/validation.sh"
source "${SCRIPT_DIR}/modules/steps/01_disks.sh"
source "${SCRIPT_DIR}/modules/plan.sh"
source "${SCRIPT_DIR}/modules/steps/02_base.sh"
source "${SCRIPT_DIR}/modules/steps/03_config.sh"
source "${SCRIPT_DIR}/modules/steps/04_users.sh"
source "${SCRIPT_DIR}/modules/steps/05_boot.sh"
source "${SCRIPT_DIR}/modules/steps/06_network.sh"
source "${SCRIPT_DIR}/modules/steps/07_amd.sh"
source "${SCRIPT_DIR}/modules/steps/08_desktop.sh"
source "${SCRIPT_DIR}/modules/steps/09_verify.sh"
source "${SCRIPT_DIR}/modules/steps/10_finalize.sh"

### LIMPIEZA EN CASO DE ERROR ###
cleanup() {
  set +e
  if mountpoint -q /mnt 2>/dev/null; then
    info "Desmontando /mnt..."
    umount -R /mnt 2>/dev/null || true
  fi
  if [[ -n "${SWAP_PART:-}" ]]; then
    swapoff "$SWAP_PART" 2>/dev/null || true
  fi
}
trap cleanup EXIT

### MAIN ###
main() {
  setup_colors
  header "Instalador Arch Linux (UEFI)"
  info "Iniciando instalador de Arch Linux..."
  echo
  
  check_root
  check_uefi
  check_commands
  
  info "Sincronizando reloj del sistema..."
  timedatectl
  success "Reloj sincronizado"
  
  pause

  # Recopilar todas las decisiones primero
  collect_plan

  # Ejecutar instalación completa
  step_prepare_disks
  step_install_base
  step_configure_system
  step_create_users
  step_install_bootloader
  step_configure_network
  step_install_amd_drivers
  step_install_desktop
  step_verify_installation
  step_finalize
}

main "$@"
