#!/usr/bin/env bash
# Make a built host config live on a laptop that joined with scripts/join.sh,
# without losing remote access. Run it as its own service, so it keeps going when
# the Tailscale SSH session drops at the handover:
#
#   systemd-run -q --unit=asoldi-switch --collect /etc/nixos/scripts/switch-over.sh <Host> "$(readlink -f result)"
#
# Then reconnect after a minute or two and read /var/log/asoldi-switch.log.
# What it does:
#  1. keeps today's system as the boot entry "before-asoldi" (garbage collection
#     never removes it);
#  2. makes the new system the default and activates it. On a laptop without
#     systemd-boot yet (GRUB) it installs systemd-boot and puts it first in the
#     firmware boot order;
#  3. when the permanent tailscaled starts, systemd stops the temporary one
#     (join.sh set Conflicts=); both share the state file, so the identity stays;
#  4. if the permanent Tailscale is not running after 90 s, it starts the
#     temporary one again, so Claude can get back in and look.
# Undo: /nix/var/nix/profiles/system-profiles/before-asoldi/bin/switch-to-configuration boot,
# then reboot (or pick "before-asoldi" in the boot menu).
set -uo pipefail

TS_OUT=/nix/store/vng6r3d53ks2v6ymvp70xmdkb17lm0gd-tailscale-1.104.6 # same as join.sh
STATE=/var/lib/tailscale/tailscaled.state
SOCK=/run/tailscale/tailscaled.sock
UNIT=asoldi-join-tailscaled
LOG=/var/log/asoldi-switch.log

exec >>"$LOG" 2>&1
log() { echo "$(date '+%F %T') $*"; }

host=${1:-}
new=${2:-}
case $new in
  /nix/store/*-nixos-system-"$host"-*) ;;
  *)
    log "refusing: '$new' is not a built $host system"
    exit 1
    ;;
esac
[ -x "$new/bin/switch-to-configuration" ] || {
  log "refusing: $new has no switch-to-configuration"
  exit 1
}
old=$(readlink -f /run/current-system)
log "switch-over to $host"
log "old: $old"
log "new: $new"

# 1. Fallback entry.
if [ ! -e /nix/var/nix/profiles/system-profiles/before-asoldi ]; then
  mkdir -p /nix/var/nix/profiles/system-profiles
  nix-env -p /nix/var/nix/profiles/system-profiles/before-asoldi --set "$old" &&
    log "kept the old system as boot entry before-asoldi"
fi

# 2. New default, then activate.
esp=
for m in /boot /boot/efi /efi; do
  if [ "$(findmnt -n -o FSTYPE -M "$m" 2>/dev/null)" = vfat ]; then
    esp=$m
    break
  fi
done
if [ -n "$esp" ] && [ ! -e "$esp/EFI/systemd/systemd-bootx64.efi" ]; then
  export NIXOS_INSTALL_BOOTLOADER=1
  log "systemd-boot is not installed yet: installing it"
fi
nix-env -p /nix/var/nix/profiles/system --set "$new" || {
  log "could not set the system profile; nothing changed"
  exit 1
}
"$new/bin/switch-to-configuration" switch
rc=$?
log "switch-to-configuration exited with $rc (0 = ok, 4 = some unit failed to start)"

# 3./4. Remote access check.
st=
for _ in $(seq 45); do
  st=$("$TS_OUT/bin/tailscale" --socket="$SOCK" status --json --peers=false 2>/dev/null |
    sed -n 's/^ *"BackendState": *"\([^"]*\)".*/\1/p')
  [ "$st" = Running ] && break
  sleep 2
done
if [ "$st" = Running ] && systemctl is-active --quiet tailscaled.service; then
  log "permanent Tailscale is running"
  systemctl stop asoldi-join-awake.service 2>/dev/null || true
else
  log "permanent Tailscale is NOT running (state '$st'); starting the temporary one again"
  systemctl stop tailscaled.service 2>/dev/null || true
  systemctl reset-failed "$UNIT" 2>/dev/null || true
  [ -x "$TS_OUT/bin/tailscaled" ] || nix-store --realise "$TS_OUT" >/dev/null
  systemd-run -q --unit="$UNIT" --collect --description="Temporary Tailscale for the Asoldi worker setup" \
    -p Conflicts=tailscaled.service -p Before=tailscaled.service \
    -p RuntimeDirectory=tailscale -p StateDirectory=tailscale -p StateDirectoryMode=0700 \
    -E PATH=/run/wrappers/bin:/run/current-system/sw/bin \
    "$TS_OUT/bin/tailscaled" --state="$STATE" --socket="$SOCK" --tun=userspace-networking &&
    log "temporary Tailscale started again"
fi
command -v efibootmgr >/dev/null && efibootmgr | grep -E '^Boot(Current|Order)' | sed "s/^/$(date '+%F %T') firmware: /"
log "done"
