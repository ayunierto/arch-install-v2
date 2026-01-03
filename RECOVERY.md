# Guía de Recuperación: Error al montar /boot

## Problema Actual

Tu sistema Arch Linux no puede arrancar y muestra:

```
[FAILED] Failed to mount /boot.
[DEPEND] Dependency failed for Local File Systems.
You are in emergency mode.
```

## Causa

El archivo `/etc/fstab` (tabla de sistemas de archivos) tiene una entrada incorrecta o incompleta para `/boot`, lo que impide que el sistema monte la partición EFI durante el arranque.

## Solución Manual (Rápida)

Desde el modo de emergencia donde estás ahora:

### 1. Verificar el problema

```bash
# Ver el fstab actual
cat /etc/fstab

# Verificar qué particiones existen
lsblk -f
```

### 2. Identificar tu partición EFI

Busca la partición con `FSTYPE` = `vfat` o `FAT32` (normalmente la primera partición del disco, ej: `/dev/sda1`, `/dev/nvme0n1p1`).

### 3. Obtener el UUID correcto

```bash
# Reemplaza /dev/sdaX con tu partición EFI
blkid /dev/sdaX
```

Anota el `UUID="..."` que aparece.

### 4. Editar fstab

```bash
# Editar con nano (más fácil)
nano /etc/fstab

# O con vim
vim /etc/fstab
```

**Busca la línea de `/boot`**. Debería verse algo así:

```
UUID=XXXX-XXXX  /boot  vfat  defaults  0  2
```

**Si no existe**, agrégala manualmente. **Si existe pero el UUID es incorrecto**, corrígelo con el UUID que obtuviste en el paso 3.

Ejemplo de entrada correcta:

```
UUID=1234-5678  /boot  vfat  defaults,umask=0077  0  2
```

### 5. Guardar y salir

- **Nano**: `Ctrl+O` (guardar), `Enter`, `Ctrl+X` (salir)
- **Vim**: `Esc`, `:wq`, `Enter`

### 6. Reintentar montaje

```bash
# Intentar montar /boot
mount -a

# Verificar que se montó
mountpoint /boot

# Ver montajes actuales
lsblk
```

### 7. Salir del modo de emergencia

```bash
# Continuar el arranque
exit

# O reiniciar
systemctl reboot
```

## Solución Automática (Desde Live-ISO)

Si la solución manual no funciona o prefieres una reparación automática:

### 1. Arrancar desde el USB/ISO de Arch Linux

### 2. Conectarse a internet (si es necesario)

```bash
# Wi-Fi
iwctl
station wlan0 connect "TuRedWiFi"
exit

# Verificar conexión
ping -c 3 archlinux.org
```

### 3. Descargar y ejecutar el script de reparación

```bash
# Descargar
curl -O https://raw.githubusercontent.com/tu-repo/arch-install-v2/main/fix-boot-mount.sh

# O si lo tienes en el USB
# cp /ruta/al/fix-boot-mount.sh .

# Dar permisos
chmod +x fix-boot-mount.sh

# Ejecutar
./fix-boot-mount.sh
```

### 4. El script te guiará para:

- Identificar las particiones ROOT y EFI
- Montar el sistema instalado
- Diagnosticar problemas en fstab
- Regenerar fstab automáticamente
- Reinstalar GRUB si es necesario
- Verificar que todo esté correcto

## Prevención en Futuras Instalaciones

El script `install-unified.sh` ha sido actualizado con:

✅ **Validación de fstab**: Verifica que `/boot` esté incluido después de generar el fstab  
✅ **Verificación de montaje**: Confirma que `/boot` sea escribible antes de instalar GRUB  
✅ **Validación de GRUB**: Comprueba que todos los archivos necesarios existan  
✅ **Diagnóstico final**: Ejecuta una verificación completa antes de finalizar

## Solución de Problemas Adicionales

### Si `/boot` está vacío después de montar

La partición EFI puede estar corrupta o no se formateó correctamente:

```bash
# Desde live-ISO, montar tu sistema
mount /dev/sdaX /mnt        # ROOT
mount /dev/sdaY /mnt/boot   # EFI

# Reinstalar kernel e initramfs
arch-chroot /mnt
pacman -S linux
mkinitcpio -P
exit
```

### Si GRUB no se instaló correctamente

```bash
# Montar sistema
mount /dev/sdaX /mnt
mount /dev/sdaY /mnt/boot

# Reinstalar GRUB
arch-chroot /mnt
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg
exit
```

### Si el UUID de la partición EFI cambió

Puede pasar si reformateaste la partición EFI:

```bash
# Desde live-ISO
mount /dev/sdaX /mnt

# Regenerar fstab completamente
genfstab -U /mnt > /mnt/etc/fstab

# Verificar
cat /mnt/etc/fstab
```

## Notas Importantes

⚠️ **Dual Boot**: Si tienes Windows u otro SO, NO formatees la partición EFI durante la instalación. Usa la existente.

⚠️ **UUIDs vs PARTUUIDs**: El script usa UUIDs por defecto con `genfstab -U`. Si tienes problemas, puedes intentar con PARTUUIDs usando `genfstab -t PARTUUID`.

⚠️ **Partición EFI pequeña**: Asegúrate de que la partición EFI tenga al menos 512MB (recomendado 1GB si planeas dual boot).

## Contacto y Soporte

Si estas soluciones no resuelven tu problema:

1. Guarda el contenido de `/etc/fstab`
2. Ejecuta `lsblk -f > particiones.txt` y guarda el resultado
3. Ejecuta `blkid > uuids.txt` y guarda el resultado
4. Busca ayuda en:
   - [Arch Linux Forums](https://bbs.archlinux.org/)
   - [r/archlinux](https://reddit.com/r/archlinux)
   - [Arch Linux Wiki - Installation](https://wiki.archlinux.org/title/Installation_guide)
