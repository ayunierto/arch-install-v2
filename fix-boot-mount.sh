#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Script de Recuperación: Reparar montaje de /boot
# ============================================================================
# Este script repara problemas con el montaje de /boot después de una
# instalación de Arch Linux que falla al arrancar.
#
# Ejecutar desde el live-ISO de Arch Linux como root

### UTILIDADES ###
info() {
  echo "→ $1"
}

error() {
  echo "✗ ERROR: $1" >&2
  exit 1
}

success() {
  echo "✓ $1"
}

### VERIFICACIONES ###
[[ $EUID -eq 0 ]] || error "Este script debe ejecutarse como root"
[[ -d /sys/firmware/efi ]] || error "Sistema UEFI no detectado"

clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║    Script de Recuperación: Reparar montaje de /boot           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo
echo "Este script ayudará a reparar el problema de montaje de /boot"
echo "que causa que el sistema entre en modo de emergencia."
echo
read -rp "Presiona ENTER para continuar..."

### PASO 1: SELECCIONAR PARTICIONES ###
echo
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ PASO 1: Identificar particiones                                │"
echo "└────────────────────────────────────────────────────────────────┘"
echo
info "Particiones disponibles:"
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
echo

read -rp "→ Partición ROOT (ej: /dev/sda2): " ROOT_PART
read -rp "→ Partición EFI  (ej: /dev/sda1): " EFI_PART

[[ -b "$ROOT_PART" ]] || error "La partición ROOT $ROOT_PART no existe"
[[ -b "$EFI_PART" ]] || error "La partición EFI $EFI_PART no existe"

### PASO 2: MONTAR SISTEMA ###
echo
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ PASO 2: Montar sistema instalado                               │"
echo "└────────────────────────────────────────────────────────────────┘"
echo

# Desmontar si ya está montado
umount -R /mnt 2>/dev/null || true

info "Montando ROOT en /mnt..."
mount "$ROOT_PART" /mnt
success "ROOT montado"

info "Montando EFI en /mnt/boot..."
mount --mkdir "$EFI_PART" /mnt/boot
success "EFI montado"

# Verificar montaje
if ! mountpoint -q /mnt/boot; then
  error "No se pudo montar /boot correctamente"
fi

echo
info "Estado actual de montajes:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -E "NAME|$(basename $ROOT_PART)|$(basename $EFI_PART)"

### PASO 3: DIAGNÓSTICO ###
echo
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ PASO 3: Diagnóstico                                            │"
echo "└────────────────────────────────────────────────────────────────┘"
echo

info "Verificando /etc/fstab actual:"
echo
cat /mnt/etc/fstab
echo

if ! grep -q "/boot" /mnt/etc/fstab; then
  echo "✗ PROBLEMA ENCONTRADO: /boot NO está en fstab"
  NEEDS_FIX=1
else
  success "/boot está en fstab"
  NEEDS_FIX=0
  
  # Verificar si el UUID es correcto
  info "Verificando UUID de la partición EFI..."
  EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
  
  if grep -q "$EFI_UUID" /mnt/etc/fstab; then
    success "UUID en fstab coincide con la partición EFI"
  else
    echo "✗ PROBLEMA: El UUID en fstab NO coincide con la partición EFI"
    echo "  UUID actual de $EFI_PART: $EFI_UUID"
    echo "  UUID en fstab:"
    grep "/boot" /mnt/etc/fstab || echo "  (no encontrado)"
    NEEDS_FIX=1
  fi
fi

info "Verificando archivos de arranque en /boot..."
if ls /mnt/boot/vmlinuz-* &>/dev/null; then
  success "Kernel encontrado en /boot"
else
  echo "✗ PROBLEMA: No se encuentra el kernel en /boot"
  NEEDS_FIX=1
fi

if [[ -f /mnt/boot/grub/grub.cfg ]]; then
  success "grub.cfg encontrado"
else
  echo "✗ PROBLEMA: grub.cfg no existe"
  NEEDS_FIX=1
fi

if [[ -d /mnt/boot/EFI ]]; then
  success "Directorio EFI existe"
  ls -la /mnt/boot/EFI/ 2>/dev/null || true
else
  echo "✗ PROBLEMA: Directorio EFI no existe en /boot"
  NEEDS_FIX=1
fi

### PASO 4: REPARACIÓN ###
if [[ $NEEDS_FIX -eq 1 ]]; then
  echo
  echo "┌────────────────────────────────────────────────────────────────┐"
  echo "│ PASO 4: Reparación                                             │"
  echo "└────────────────────────────────────────────────────────────────┘"
  echo
  
  read -rp "¿Deseas reparar estos problemas? [y/N]: " fix_ans
  if [[ "$fix_ans" != "y" && "$fix_ans" != "Y" ]]; then
    info "Reparación cancelada"
    exit 0
  fi
  
  # Backup del fstab actual
  info "Creando backup de fstab..."
  cp /mnt/etc/fstab /mnt/etc/fstab.backup.$(date +%s)
  success "Backup creado"
  
  # Regenerar fstab
  info "Regenerando /etc/fstab..."
  genfstab -U /mnt > /mnt/etc/fstab.new
  
  echo
  info "Nuevo fstab generado:"
  echo
  cat /mnt/etc/fstab.new
  echo
  
  read -rp "¿Aplicar este nuevo fstab? [y/N]: " apply_ans
  if [[ "$apply_ans" == "y" || "$apply_ans" == "Y" ]]; then
    mv /mnt/etc/fstab.new /mnt/etc/fstab
    success "fstab actualizado"
  else
    info "fstab no actualizado. Puedes editarlo manualmente en /mnt/etc/fstab"
  fi
  
  # Reinstalar GRUB si es necesario
  if [[ ! -f /mnt/boot/grub/grub.cfg ]] || [[ ! -d /mnt/boot/EFI/Arch ]]; then
    echo
    info "Reinstalando GRUB..."
    
    arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch"
    success "GRUB reinstalado"
    
    info "Regenerando grub.cfg..."
    arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
    success "grub.cfg regenerado"
  fi
  
else
  echo
  success "No se detectaron problemas críticos"
fi

### PASO 5: VERIFICACIÓN FINAL ###
echo
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ PASO 5: Verificación Final                                     │"
echo "└────────────────────────────────────────────────────────────────┘"
echo

FINAL_ERRORS=0

if grep -q "/boot" /mnt/etc/fstab; then
  success "/boot está en fstab"
else
  echo "✗ /boot NO está en fstab"
  FINAL_ERRORS=$((FINAL_ERRORS + 1))
fi

if [[ -f /mnt/boot/grub/grub.cfg ]]; then
  success "grub.cfg existe"
else
  echo "✗ grub.cfg NO existe"
  FINAL_ERRORS=$((FINAL_ERRORS + 1))
fi

if [[ -d /mnt/boot/EFI/Arch ]]; then
  success "Bootloader instalado"
else
  echo "✗ Bootloader NO está instalado"
  FINAL_ERRORS=$((FINAL_ERRORS + 1))
fi

if ls /mnt/boot/vmlinuz-* &>/dev/null; then
  success "Kernel existe en /boot"
else
  echo "✗ Kernel NO existe en /boot"
  FINAL_ERRORS=$((FINAL_ERRORS + 1))
fi

echo
if [[ $FINAL_ERRORS -eq 0 ]]; then
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║              ¡REPARACIÓN COMPLETADA CON ÉXITO!                 ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo
  info "Próximos pasos:"
  echo "  1. Desmonta: umount -R /mnt"
  echo "  2. Reinicia: reboot"
  echo "  3. Retira el USB/ISO"
  echo "  4. El sistema debería arrancar correctamente"
else
  echo "⚠ AÚN HAY $FINAL_ERRORS PROBLEMA(S)"
  echo "  Es posible que necesites ayuda adicional o reinstalar"
fi

echo
read -rp "Presiona ENTER para salir..."
