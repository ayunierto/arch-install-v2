#!/usr/bin/env bash
# shellcheck shell=bash
# Paso final

step_finalize() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "10" "Instalación completada"

  success "Arch Linux ha sido instalado exitosamente"
  echo
  echo "Configuración:"
  echo "  • Hostname: $HOSTNAME"
  echo "  • Usuario: $USERNAME"
  echo "  • Timezone: $TIMEZONE"
  echo "  • Locale: $LOCALE"
  echo "  • Bootloader: GRUB (UEFI) con os-prober habilitado"
  echo "  • Red: NetworkManager"
  echo
  echo "Próximos pasos:"
  echo "  1. Sal del instalador: exit"
  echo "  2. Desmonta las particiones: umount -R /mnt"
  echo "  3. Desactiva swap (si usaste): swapoff -a"
  echo "  4. Reinicia: reboot"
  echo "  5. Retira el USB/ISO y arranca desde el disco"
  echo
  info "Después del primer arranque, inicia sesión con tu usuario y configura"
  info "lo que necesites (escritorio, aplicaciones, etc.)"
  echo
  
  if confirm "¿Desmontar /mnt y reiniciar ahora?"; then
    info "Desmontando..."
    umount -R /mnt || true
    swapoff -a 2>/dev/null || true
    info "Reiniciando en 5 segundos..."
    sleep 5
    reboot
  else
    info "No olvides desmontar y reiniciar manualmente cuando termines"
  fi
}
