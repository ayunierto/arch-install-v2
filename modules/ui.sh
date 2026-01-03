#!/usr/bin/env bash
# shellcheck shell=bash
# Utilidades de UI y mensajes con soporte de color

setup_colors() {
  if [[ -t 1 ]]; then
    COLOR_BLUE="\033[1;34m"
    COLOR_CYAN="\033[1;36m"
    COLOR_GREEN="\033[1;32m"
    COLOR_YELLOW="\033[1;33m"
    COLOR_RED="\033[1;31m"
    COLOR_GRAY="\033[0;37m"
    COLOR_RESET="\033[0m"
  else
    COLOR_BLUE=""; COLOR_CYAN=""; COLOR_GREEN=""; COLOR_YELLOW=""; COLOR_RED=""; COLOR_GRAY=""; COLOR_RESET=""
  fi
}

pause() {
  echo
  read -rp "Presiona ENTER para continuar..." _
}

confirm() {
  local prompt="${1:-¿Continuar?}"
  local ans
  read -rp "$prompt [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

header() {
  local title="${1:-Instalador Arch Linux (UEFI)}"
  clear
  echo -e "${COLOR_CYAN}╔════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
  printf "${COLOR_CYAN}║%-62s║\n${COLOR_RESET}" "  $title"
  echo -e "${COLOR_CYAN}╚════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
  echo
}

section() {
  local title="$1"
  echo
  echo -e "${COLOR_BLUE}┌────────────────────────────────────────────────────────────────┐${COLOR_RESET}"
  printf "${COLOR_BLUE}│ %-62s│\n${COLOR_RESET}" "$title"
  echo -e "${COLOR_BLUE}└────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
  echo
}

info() {
  echo -e "${COLOR_CYAN}→${COLOR_RESET} $1"
}

warn() {
  echo -e "${COLOR_YELLOW}!${COLOR_RESET} $1"
}

success() {
  echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

error() {
  echo -e "${COLOR_RED}✗ ERROR:${COLOR_RESET} $1" >&2
  exit 1
}

line() {
  echo -e "${COLOR_GRAY}────────────────────────────────────────────────────────────────────${COLOR_RESET}"
}

step_banner() {
  # Muestra un banner compacto para cada paso
  local step_num="$1"
  local label="$2"
  echo -e "${COLOR_CYAN}≫ Paso ${step_num}:${COLOR_RESET} $label"
  line
}
