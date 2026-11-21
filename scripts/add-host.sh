#!/usr/bin/env bash
# Add the laptop this runs on as a new host of this flake, with the same software
# as Eeto (nix32): the shared default bundle plus the worker module. Disk,
# encryption, keyboard and hardware are read from the running machine, so its
# partitions stay as they are (disko.nix is not used).
#
#   sudo scripts/add-host.sh <HostName> [old-config-dir]
#
# Run it from the repo root: normally /etc/nixos, after the laptop's old config
# was moved to /etc/nixos.before-asoldi (the default old-config-dir). It only
# writes modules/hosts/<HostName>/ and git-adds it (flakes see only files git
# knows about). It builds nothing. Read every REVIEW line, then follow the
# "next" steps it prints (README.md, "Add another laptop").
# Optional: TS_NAME=nix16 (Tailscale name, for the comment), STATE_VERSION=24.05,
# NIX=/nix/store/...-nix-2.35.6/bin/nix (a newer nix on old laptops).
set -euo pipefail

die() {
  echo "add-host: $*" >&2
  exit 1
}
say() { echo "add-host: $*"; }
review() { echo "add-host: REVIEW: $*"; }

host=${1:-}
old=${2:-/etc/nixos.before-asoldi}
NIX=${NIX:-nix}
[[ $host =~ ^[A-Za-z][A-Za-z0-9-]{0,62}$ ]] || die "usage: sudo scripts/add-host.sh <HostName> [old-config-dir]"
[ "$(id -u)" -eq 0 ] || die "run it with sudo (the hardware scan needs root)"
[ -f flake.nix ] && [ -d modules/hosts ] || die "run it from the repo root (where flake.nix is)"
command -v git >/dev/null || die "git is missing; run it inside: nix-shell -p git"
export NIX_CONFIG="extra-experimental-features = nix-command flakes" # old laptops may not have flakes on yet

# --- Is this the right machine, and can the shared boot setup work on it? -----
dir=modules/hosts/$host
me=$(hostname)
for d in modules/hosts/*/; do
  d=${d%/}
  [ "${d,,}" != "${dir,,}" ] || die "$d already exists (host names must differ in more than case)"
  [ "${d##*/}" != "$me" ] || die "this laptop already is host $me. To make it a worker, add self.nixosModules.worker to $d/default.nix instead"
done
[ -d /sys/firmware/efi ] || die "this laptop boots in legacy BIOS mode, but the shared config uses systemd-boot (UEFI only). Add a GRUB host by hand."
[ "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo 64)" = 64 ] || die "32-bit UEFI firmware: systemd-boot here needs a hand-made host"
sb=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ -e "$sb" ] && [ "$(od -An -t u1 -j4 -N1 "$sb" | tr -d ' ')" = 1 ]; then
  die "Secure Boot is on. Turn it off in the firmware setup first (or add lanzaboote to this host by hand)"
fi

esp=
for m in /boot /boot/efi /efi; do
  if [ "$(findmnt -n -o FSTYPE -M "$m" 2>/dev/null)" = vfat ]; then
    esp=$m
    break
  fi
done
[ -n "$esp" ] || die "no FAT EFI partition is mounted at /boot, /boot/efi or /efi"
if [ ! -e "$esp/EFI/systemd/systemd-bootx64.efi" ]; then
  avail=$(df -Pm "$esp" | awk 'NR==2 {print $4}')
  [ "$avail" -ge 250 ] || die "the EFI partition $esp has only ${avail} MB free; systemd-boot needs room for kernels (250 MB). Free space or add the host by hand"
  review "systemd-boot is not installed yet (GRUB today?). scripts/switch-over.sh installs it and puts it first in the firmware boot order; ${avail} MB free on $esp"
fi

# Wi-Fi run by something other than NetworkManager would drop at the switch.
if ! systemctl is-active --quiet NetworkManager.service; then
  for w in /sys/class/net/*/wireless; do
    [ -e "$w" ] || continue
    ifc=$(basename "$(dirname "$w")")
    if ip route show default | grep -q " dev $ifc "; then
      die "the network runs on Wi-Fi ($ifc) without NetworkManager, which the shared config uses. Wi-Fi would drop at the switch. Use a cable, or create a NetworkManager profile for this Wi-Fi first"
    fi
  done
  review "NetworkManager is not running today; the shared config turns it on (a cable connection comes up by itself)"
fi

# --- First-install release ----------------------------------------------------
sv=${STATE_VERSION:-}
if [ -z "$sv" ] && [ -d "$old" ]; then
  sv=$(grep -rhE --include='*.nix' 'system\.stateVersion[[:space:]]*=' "$old" | grep -vE '^[[:space:]]*#' |
    grep -oE '"[0-9]{2}\.[0-9]{2}"' | tr -d '"' | sort -u || true)
fi
[ -n "$sv" ] || die "no system.stateVersion found in $old. Pass the release this laptop was first installed with: sudo STATE_VERSION=24.05 scripts/add-host.sh $host"
[ "$(printf '%s\n' "$sv" | wc -l)" -eq 1 ] || die "several stateVersions in $old (${sv//$'\n'/ }). Pass the right one with STATE_VERSION=..."
[[ $sv =~ ^[0-9]{2}\.[0-9]{2}$ ]] || die "STATE_VERSION must look like 24.05 (got $sv)"

# --- Hardware scan --------------------------------------------------------------
mkdir -p "$dir"
# The scan lists everything mounted right now. Keep real disks only: drop
# container and runtime mounts (Docker overlays, tmpfs and the like), which are
# gone after a reboot and would stop the boot if they were required.
nixos-generate-config --show-hardware-config |
  awk '
    function flush() {
      if (keep) printf "%s", block
      else print "add-host: left out the temporary mount " mp > "/dev/stderr"
      inblock = 0; block = ""; dropblank = !keep
    }
    inblock {
      block = block $0 "\n"
      if ($0 ~ /fsType = "(overlay|tmpfs|squashfs|erofs|nsfs|autofs|fuse[^"]*)"/) keep = 0
      if ($0 ~ /^    };$/) flush()
      next
    }
    /^  fileSystems\."/ {
      mp = $0; sub(/^  fileSystems\."/, "", mp); sub(/".*/, "", mp)
      inblock = 1; block = $0 "\n"
      keep = (mp !~ /^\/(run|tmp|proc|sys|dev)(\/|$)/ && mp !~ /^\/var\/lib\/(docker|containers)\/.+/)
      next
    }
    dropblank && /^$/ { dropblank = 0; next }
    { dropblank = 0; print }
  ' >"$dir/_hardware.nix"
grep -q '^  fileSystems\."/" =' "$dir/_hardware.nix" || die "the hardware scan found no root filesystem; see $dir/_hardware.nix"
mounts=$(grep -oE '^  fileSystems\."[^"]+"' "$dir/_hardware.nix" | sed 's/.*"\(.*\)"/\1/' | tr '\n' ' ')

extra=() # lines for the host's inline module
[ "$esp" = /boot ] || extra+=("boot.loader.efi.efiSysMountPoint = \"$esp\";")

# Disks other than the system ones may be missing at boot: never block on them.
for mp in $mounts; do
  case $mp in / | /boot | /boot/* | /efi | /nix | /nix/* | /home | /var | /var/*) ;;
    *)
      extra+=("fileSystems.\"$mp\".options = [ \"nofail\" ];")
      review "extra disk $mp: mounted with nofail, so the laptop still boots without it"
      ;;
  esac
done

# Encrypted devices under the kept mounts and swap (the scan misses LUKS under
# LVM). Unlocked USB disks are not under them, so they are never added.
srcs=()
for mp in $mounts; do srcs+=("$(findmnt -n -o SOURCE -M "$mp" | sed 's/\[.*//')"); done
while read -r s _; do [ "$s" = Filename ] || srcs+=("$s"); done </proc/swaps
crypts=$(for s in "${srcs[@]}"; do [ -b "$s" ] && lsblk -s -r -n -o KNAME,TYPE "$s"; done | awk '$2 == "crypt" {print $1}' | sort -u)
for k in $crypts; do
  b=/sys/block/$k
  case $(cat "$b/dm/uuid") in CRYPT-LUKS*) ;; *) die "$k is encrypted without LUKS; add it by hand" ;; esac
  n=$(cat "$b/dm/name")
  grep -qF "\"$n\"" "$dir/_hardware.nix" && continue
  slaves=("$b"/slaves/*)
  [ "${#slaves[@]}" -eq 1 ] && [ -e "${slaves[0]}" ] || die "LUKS device $n has ${#slaves[@]} backing devices; add it by hand"
  luuid=$(blkid -s UUID -o value "/dev/$(basename "${slaves[0]}")")
  [ -n "$luuid" ] || die "no UUID for the LUKS device under $n; add it by hand"
  extra+=("boot.initrd.luks.devices.\"$n\".device = \"/dev/disk/by-uuid/$luuid\";")
  review "LUKS device $n was not in the scan (LVM on LUKS?); added it. Check old options like allowDiscards or keyFile"
done
if grep -rqE --include='*.nix' 'keyFile|crypto_keyfile|initrd\.secrets' "$old" 2>/dev/null; then
  review "the old config unlocks something with a key file (initrd.secrets/keyFile). Copy that by hand, or the boot asks for the passphrase more than once"
fi

# Keyboard: the console keymap is also the layout of the LUKS passphrase prompt.
km=$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null | tr -d '"' | head -n 1)
xl=$(localectl status 2>/dev/null | sed -n 's/^ *X11 Layout: //p' | head -n 1)
xv=$(localectl status 2>/dev/null | sed -n 's/^ *X11 Variant: //p' | head -n 1)
[[ $xl =~ ^[a-z,]*$ ]] || xl=
[[ $xv =~ ^[a-z0-9_,-]*$ ]] || xv=
if [ -n "$xl" ] && [ "$xl" != us ]; then
  extra+=("services.xserver.xkb.layout = \"$xl\";")
  [ -z "$xv" ] || extra+=("services.xserver.xkb.variant = \"$xv\";")
fi
case $km in
  "" | us) ;;
  /nix/store/*) [ -z "$xl" ] || extra+=("console.useXkbConfig = true;") ;;
  *) [[ $km =~ ^[A-Za-z0-9_.-]+$ ]] && extra+=("console.keyMap = \"$km\";") ;;
esac

# People who log in on this laptop today. A user the old config declared and the
# new one does not would be removed at the switch, so keep each one (same uid,
# home and password; only the groups below are kept).
kept=
while IFS=: read -r u _ uid _ _ home shell; do
  [ "$uid" -ge 1000 ] && [ "$uid" -lt 30000 ] || continue
  case $shell in */nologin | */false) continue ;; esac
  case $u in damianhc | sofushl) continue ;; esac # already in the shared config
  [[ $u =~ ^[a-z_][a-z0-9_-]*$ ]] || die "unexpected user name '$u' in /etc/passwd; add it by hand"
  [[ $home =~ ^/[A-Za-z0-9_./-]*$ ]] || die "unexpected home '$home' for $u; add it by hand"
  groups=
  for g in $(id -nG "$u"); do
    case $g in wheel | networkmanager | video | audio | docker) groups="$groups \"$g\"" ;; esac
  done
  extra+=("users.users.$u = { isNormalUser = true; home = \"$home\"; extraGroups = [$groups ]; };")
  kept="$kept $u"
done </etc/passwd

# Shared accounts that do not exist here yet start locked instead of with the
# public default password: set one with `sudo passwd <name>` when needed.
for u in damianhc sofushl; do
  if ! getent passwd "$u" >/dev/null; then
    extra+=("users.users.$u = { initialPassword = lib.mkForce null; initialHashedPassword = \"!\"; };")
    review "account $u is new here and starts locked (no password). SSH keys and Tailscale SSH still work"
  fi
done

body=
for l in "${extra[@]}"; do body="$body
          $l"; done

cat >"$dir/default.nix" <<EOF
# Host $host, added with scripts/add-host.sh on $(date +%F).
# Same software as Eeto (nix32): the shared default bundle plus the worker module.
# Disk, encryption and hardware come from this laptop's own _hardware.nix
# (nixos-generate-config). The leading _ keeps import-tree from loading it as a
# flake module.
{ self, inputs, ... }:
{
  flake.nixosConfigurations.$host = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      ./_hardware.nix
      self.nixosModules.worker # always-on worker, Tailscale name ${TS_NAME:-see WORKER.md}
      (
        { lib, ... }:
        {
          networking.hostName = "$host";
          system.stateVersion = "$sv"; # first install's release; never change it
          boot.loader.systemd-boot.configurationLimit = 10; # keeps the EFI partition from filling up$body
        }
      )
    ];
  };
}
EOF
if command -v nixfmt >/dev/null; then nixfmt "$dir/default.nix" || true; fi
git add "$dir"
say "wrote $dir/default.nix and $dir/_hardware.nix (stateVersion $sv, EFI at $esp, mounts: ${mounts% }${kept:+, kept users:$kept})"

# --- What the old config did that the new one may not ----------------------------
echo
if [ ! -d "$old" ]; then
  review "no old config at $old. Find the real one (a flake under /home? check nixos-version --json) and rerun with it as the second argument"
else
  review "settings in $old that the new config does not copy (check each one; comment lines left out):"
  grep -rnE --include='*.nix' \
    'boot\.|hardware\.|videoDrivers|nvidia|fileSystems|swapDevices|services\.|virtualisation\.|programs\.|users\.|security\.|networking\.|console\.|xkb|i18n\.|time\.|nix\.|environment\.|lanzaboote|swraid' \
    "$old" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v '/hardware-configuration\.nix:' || echo "  (none found)"
  if [ -f "$old/hardware-configuration.nix" ]; then
    echo
    review "old hardware-configuration.nix compared with the new scan (- old, + new):"
    { diff -u "$old/hardware-configuration.nix" "$dir/_hardware.nix" || true; } | sed -n '3,$p' | grep -E '^[-+]' || echo "  (same)"
  fi
fi
echo

drv=$("$NIX" eval --raw ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath") ||
  die "the new host does not evaluate (on Nix older than 2.18, pass NIX= a newer nix; see README)"
say "evaluates: $drv"
say "next: $NIX build .#nixosConfigurations.$host.config.system.build.toplevel  (makes ./result)"
say "      nix store diff-closures /run/current-system ./result ; diff the unit lists too"
say "      git commit the host folder here, then: systemd-run --unit=asoldi-switch --collect $PWD/scripts/switch-over.sh $host \"\$(readlink -f result)\""
