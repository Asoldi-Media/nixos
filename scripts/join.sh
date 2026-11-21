#!/bin/sh
# Connect this NixOS laptop to the owner's Tailscale network with Tailscale SSH,
# so Claude on the Windows laptop can finish the setup from there. Run it on the
# laptop with the command from README.md ("Add another laptop").
#
# It changes nothing in /etc/nixos. Until the next reboot it runs a temporary
# Tailscale as a system service (it survives closing the terminal and logging
# out) and keeps the laptop awake, lid closed included. When the worker config
# starts the permanent Tailscale, systemd stops the temporary one first; both use
# the same state file, so the laptop keeps its Tailscale identity.
#
# The Tailscale name is nix + the RAM size (a 16 GB laptop becomes nix16). If
# that name is taken, Tailscale adds -1; the script prints the real name.
# Pick another one with: sudo sh join.sh nix16b
set -eu

# Tailscale 1.104.6 from the nixpkgs in flake.lock (x86_64-linux), fetched by
# store path from cache.nixos.org. No nixpkgs evaluation, so any Nix version works.
TS_OUT=/nix/store/vng6r3d53ks2v6ymvp70xmdkb17lm0gd-tailscale-1.104.6
STATE=/var/lib/tailscale/tailscaled.state # the path services.tailscale uses
SOCK=/run/tailscale/tailscaled.sock
UNIT=asoldi-join-tailscaled
AWAKE=asoldi-join-awake

say() { echo "join: $*"; }
die() {
  echo "join: $*" >&2
  exit 1
}

self_field() { # value of a top-level string field of Self in `tailscale status --json`
  $ts status --json --peers=false 2>/dev/null | sed -n "s/^ *\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

main() {
  [ "$(id -u)" -eq 0 ] || die "run it with sudo"
  [ -e /etc/NIXOS ] || die "this is not NixOS"
  [ "$(uname -m)" = x86_64 ] || die "only x86_64 laptops are covered (this one is $(uname -m))"
  command -v systemd-run >/dev/null 2>&1 || die "systemd-run is missing"

  if [ $# -ge 1 ]; then
    name=$1
  else
    kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    gib=$(((kib + 1048575) / 1048576))
    size=$gib
    for s in 4 8 12 16 20 24 32 40 48 64 96 128; do
      if [ "$s" -ge "$gib" ]; then
        size=$s
        break
      fi
    done
    name=nix$size
  fi
  case $name in
    nix*) ;;
    *) die "the name must start with nix (got $name)" ;;
  esac
  case $name in
    *[!a-z0-9-]*) die "use only a-z, 0-9 and - in the name (got $name)" ;;
  esac

  if systemctl is-active --quiet tailscaled.service; then
    say "this laptop already runs Tailscale as a service; using it"
    ts=tailscale
  else
    if [ ! -x "$TS_OUT/bin/tailscaled" ]; then
      say "downloading Tailscale (about 30 MB)..."
      nix-store --realise "$TS_OUT" >/dev/null ||
        die "could not download Tailscale from cache.nixos.org (see the error above)"
    fi
    ts="$TS_OUT/bin/tailscale --socket=$SOCK"
    if ! systemctl is-active --quiet "$UNIT"; then
      systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true
      # Userspace networking: no network changes on the laptop. Tailscale SSH
      # still works, and that is all the setup needs.
      systemd-run -q --unit="$UNIT" --collect --description="Temporary Tailscale for the Asoldi worker setup" \
        -p Conflicts=tailscaled.service -p Before=tailscaled.service \
        -p RuntimeDirectory=tailscale -p StateDirectory=tailscale -p StateDirectoryMode=0700 \
        -E PATH=/run/wrappers/bin:/run/current-system/sw/bin \
        "$TS_OUT/bin/tailscaled" --state="$STATE" --socket="$SOCK" --tun=userspace-networking >/dev/null
    fi
    i=0
    until $ts status --json >/dev/null 2>&1; do
      i=$((i + 1))
      [ "$i" -le 30 ] || die "Tailscale did not start; see: journalctl -u $UNIT"
      sleep 1
    done
  fi

  # Stay awake until the next reboot, lid closed included. The worker config
  # turns sleep off for good.
  if ! systemctl is-active --quiet "$AWAKE" && command -v systemd-inhibit >/dev/null 2>&1; then
    systemctl reset-failed "$AWAKE" >/dev/null 2>&1 || true
    systemd-run -q --unit="$AWAKE" --collect --description="Keep awake during the Asoldi worker setup" \
      "$(command -v systemd-inhibit)" --what=sleep:idle:handle-lid-switch --who=asoldi-join \
      --why="Worker setup in progress" --mode=block "$(command -v sleep)" infinity >/dev/null || true
  fi

  # An older install may have left this laptop signed in to some other account:
  # then always ask for a fresh sign-in.
  flags="--reset --ssh --hostname=$name"
  if [ "$(self_field BackendState)" = Running ]; then
    flags="$flags --force-reauth"
  fi
  if $ts up --help 2>&1 | grep -q -- '--qr'; then
    flags="$flags --qr"
  fi

  echo
  say "open the link below (or scan the QR code with your phone) and sign in"
  say "with the SAME Tailscale account as the Windows laptop, then click Connect."
  echo
  # shellcheck disable=SC2086 # $ts and $flags are word lists on purpose
  $ts up $flags

  real=$(self_field DNSName)
  real=${real%%.*}
  ip=$($ts ip -4 2>/dev/null | head -n 1)
  echo
  [ -z "$real" ] || [ "$real" = "$name" ] || say "note: $name was taken, so Tailscale named this laptop $real"
  say "done. This laptop is on Tailscale as ${real:-$name} ($ip)."
  say "tell Claude on the Windows laptop: \"${real:-$name} ($ip) is online\". Keep it plugged in."
}

# Everything runs from here, so a half-downloaded script does nothing.
main "$@"
