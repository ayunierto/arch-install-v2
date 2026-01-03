#!/usr/bin/env bash
# shellcheck shell=bash
# Planificador: recopila todas las decisiones antes de ejecutar la instalación

# Variables de plan (se rellenan en collect_plan)
FORMAT_EFI="no"
FORMAT_HOME="yes"
ENABLE_SWAP="yes"
AMD_CHOICE="0"
DESKTOP_CHOICE="0"
DO_AUDIO="yes"
DO_EXTRA_PKGS="no"

collect_plan() {
  header "Plan de instalación"
  step_banner "P" "Recopilar datos antes de instalar"

  info "Primero se recopilarán TODAS las decisiones. Luego se ejecutará la instalación completa."
  pause

  # Selección de particiones (solo recopila, no formatea ni monta)
  step_banner "P" "Seleccionar particiones"
  select_partition "EFI (FAT32, ~512MB-1GB)" EFI_PART 1
  select_partition "ROOT (/, ext4)" ROOT_PART 1
  select_partition "HOME (/home, ext4, opcional)" HOME_PART 0
  select_partition "SWAP (opcional, tamaño RAM)" SWAP_PART 0

  [[ -n "$ROOT_PART" ]] || error "ROOT es obligatorio"
  [[ -n "$EFI_PART" ]] || error "EFI es obligatorio para UEFI"

  # Formato EFI
  echo
  if confirm "¿Formatear EFI ($EFI_PART)? (No si dual-boot)"; then
    FORMAT_EFI="yes"
  else
    FORMAT_EFI="no"
  fi

  # Formato HOME si existe
  if [[ -n "$HOME_PART" ]]; then
    echo
    if confirm "¿Formatear HOME ($HOME_PART)?"; then
      FORMAT_HOME="yes"
    else
      FORMAT_HOME="no"
    fi
  else
    FORMAT_HOME="no"
  fi

  # Swap si existe
  if [[ -n "$SWAP_PART" ]]; then
    echo
    if confirm "¿Activar SWAP ($SWAP_PART)?"; then
      ENABLE_SWAP="yes"
    else
      ENABLE_SWAP="no"
    fi
  else
    ENABLE_SWAP="no"
  fi

  # Zona horaria
  echo
  echo "Zonas horarias sugeridas:"
  echo "  [1] America/Lima"
  echo "  [2] America/Mexico_City"
  echo "  [3] America/Bogota"
  echo "  [4] Europe/Madrid"
  echo "  [5] Personalizar"
  read -rp "→ Elige zona horaria [1]: " tz_opt
  case "${tz_opt:-1}" in
    1|"") TIMEZONE="America/Lima" ;;
    2) TIMEZONE="America/Mexico_City" ;;
    3) TIMEZONE="America/Bogota" ;;
    4) TIMEZONE="Europe/Madrid" ;;
    5) read -rp "Introduce zona horaria (ej: America/Santiago): " TIMEZONE ;;
  esac

  # Locale
  echo
  echo "Locales sugeridos:"
  echo "  [1] en_US.UTF-8"
  echo "  [2] es_PE.UTF-8"
  echo "  [3] es_ES.UTF-8"
  echo "  [4] es_MX.UTF-8"
  echo "  [5] Personalizar"
  read -rp "→ Elige locale [1]: " locale_opt
  case "${locale_opt:-1}" in
    1|"") LOCALE="en_US.UTF-8" ;;
    2) LOCALE="es_PE.UTF-8" ;;
    3) LOCALE="es_ES.UTF-8" ;;
    4) LOCALE="es_MX.UTF-8" ;;
    5) read -rp "Introduce locale (ej: es_AR.UTF-8): " LOCALE ;;
  esac

  # Hostname y usuario
  echo
  read -rp "→ Nombre para la PC (hostname) [arch]: " HOSTNAME
  HOSTNAME="${HOSTNAME:-arch}"
  read -rp "→ Nombre de usuario a crear [usuario]: " USERNAME
  USERNAME="${USERNAME:-usuario}"

  # Drivers AMD
  echo
  echo "¿Tu sistema tiene hardware AMD (CPU o GPU)?"
  echo "  [1] GPU AMD"
  echo "  [2] CPU AMD (microcode)"
  echo "  [3] Ambos"
  echo "  [0] Omitir"
  read -rp "→ Opción [0]: " amd_opt
  AMD_CHOICE="${amd_opt:-0}"

  # Escritorio
  echo
  echo "¿Deseas instalar un entorno de escritorio?"
  echo "  [1] Hyprland + greetd (Wayland)"
  echo "  [2] GNOME"
  echo "  [0] No (solo terminal)"
  read -rp "→ Opción [0]: " de_opt
  DESKTOP_CHOICE="${de_opt:-0}"

  # Audio
  if [[ "$DESKTOP_CHOICE" != "0" ]]; then
    echo
    if confirm "¿Instalar audio? (PipeWire si Hyprland, PulseAudio si GNOME)"; then
      DO_AUDIO="yes"
    else
      DO_AUDIO="no"
    fi
  else
    DO_AUDIO="no"
  fi

  # Paquetes adicionales
  if [[ "$DESKTOP_CHOICE" != "0" ]]; then
    echo
    if confirm "¿Instalar paquetes adicionales (firefox, gestor de archivos, utilidades)?"; then
      DO_EXTRA_PKGS="yes"
    else
      DO_EXTRA_PKGS="no"
    fi
  else
    DO_EXTRA_PKGS="no"
  fi

  # Resumen
  header "Plan listo"
  section "Resumen del plan"
  echo "Particiones:"
  echo "  EFI  : $EFI_PART (formatear: $FORMAT_EFI)"
  echo "  ROOT : $ROOT_PART (formatear: yes)"
  echo "  HOME : ${HOME_PART:-no usado} (formatear: $FORMAT_HOME)"
  echo "  SWAP : ${SWAP_PART:-no usado} (activar: $ENABLE_SWAP)"
  echo
  echo "Sistema:"
  echo "  Timezone: $TIMEZONE"
  echo "  Locale  : $LOCALE"
  echo "  Hostname: $HOSTNAME"
  echo "  Usuario : $USERNAME"
  echo
  echo "Opcionales:"
  echo "  AMD     : $AMD_CHOICE"
  echo "  Desktop : $DESKTOP_CHOICE"
  echo "  Audio   : $DO_AUDIO"
  echo "  Extras  : $DO_EXTRA_PKGS"
  echo
  confirm "¿Ejecutar la instalación con este plan?" || error "Instalación cancelada por el usuario"
}
