# Asoldi NixOS laptops

One flake for every NixOS laptop. They all get the COSMIC desktop, Claude Code, Cursor, the GitHub CLI, Neovim, git, OpenSSH, and the users `damianhc` and `sofushl`.

Worker laptops also get the worker module:
- Tailscale, no sleep, Docker, Node and build tools;
- passwordless sudo for `damianhc`;
- automatic clean-up.

All laptops use the same pinned NixOS: nixos-unstable through `flake.lock`, 26.11 today.

| Host (OS name) | Tailscale name | Disk setup | Worker |
|---|---|---|---|
| `Eeto` | `nix32` | shared disko layout (`modules/hosts/disko.nix`) | yes |
| `Cospow` | `nix32-main` | shared disko layout | yes, the main worker (sofushl is not an admin here) |
| `Ideapad` | `nix8` | shared disko layout | yes |

Every `.nix` file under `modules/` is loaded automatically (flake-parts + import-tree). Paths with `/_` in them are skipped. That is how each host's generated `_hardware.nix` stays a plain NixOS module.

## Working from any laptop: handing out work, approvals and questions

Any of your computers can be the day-to-day one, and the others are workers. Nothing has to be set up per day-to-day computer.

- **Hand out work:** in Claude on the day-to-day computer, say which worker should do it, for example "run this on nix32-main". Claude connects with `ssh nix32-main` over Tailscale. On a NixOS laptop the worker module sets that up; on Windows or a Mac it needs this in `~/.ssh/config`:
  ```
  Host nix*
    User damianhc
  ```
- **No prompts on workers:** the worker module sets Claude Code's managed settings (`/etc/claude-code/managed-settings.json`):
  - auto mode by default;
  - Workflow launches pre-approved;
  - carry on automatically after a usage limit;
  - Remote Control in every session;
  - a phone notification (Claude app) when a question or approval is waiting.

  Normal work never stops for an approval. Auto mode's safety check still blocks risky actions on its own, without asking you.
- **Where questions and approvals show up:** open **claude.ai/code** in a browser on any computer, or the **Claude app** on your phone (Code). Worker sessions are in the session list under their names, for example "nix32-main Wave 6 manager". Questions and any approval request show up inside that session, and you answer them there. Workers also send a push notification when one is waiting.

## Update a laptop to what is on GitHub

```sh
cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake /etc/nixos
```

`nixos-rebuild` picks the config that matches the laptop's own hostname. The previous version stays in the boot menu, so you can undo a bad update by choosing the older entry at boot.

To move every laptop to a newer NixOS:
1. Run `nix flake update` on one machine.
2. Build, test, commit `flake.lock` and push.
3. Run the line above on each laptop.

## Add another laptop that already runs NixOS

Needs: an x86_64 laptop, UEFI boot with Secure Boot off, plugged in and online.

### 1. On the new laptop

Open a terminal and run:

```sh
curl -fsSLo /tmp/join.sh https://raw.githubusercontent.com/Asoldi-Media/nixos/main/scripts/join.sh && sudo sh /tmp/join.sh
```

Claude can give you the same line pinned to a commit. Then:
1. Type the laptop's password. If it says "not in the sudoers file", your account is not an admin on that laptop. Switch to an admin account in the same terminal (`su - <admin>`) and run `sudo sh /tmp/join.sh` again.
2. Open the Tailscale link it shows, or scan the QR code.
3. Sign in with the same Tailscale account as the Windows laptop.

At the end the script prints the laptop's Tailscale name and IP, for example `nix16 (100.x.y.z)`. Tell Claude both. If the name is taken, Tailscale adds `-1`. Nothing in the OS changes in this step. The laptop runs a temporary Tailscale and stays awake until the next reboot, even if you log out or close the lid.

### 2. From the Windows laptop

Claude does the rest as `root@<name>` over Tailscale SSH:
1. Checks that `hostname` and the machine are the new laptop, not an existing host. If it already is a host here (Cospow was `cosmic-power` from an older version of this repo), Claude updates that host instead of adding a new one.
2. Moves the old config to `/etc/nixos.before-asoldi` and clones this repo to `/etc/nixos`.
3. Runs `scripts/add-host.sh <HostName>` (with `TS_NAME=<name>`). It writes `modules/hosts/<HostName>/` from the running machine:
   - its own disk, encryption (LVM on LUKS included) and EFI setup;
   - its keyboard layout, which also sets the layout of the passphrase prompt;
   - the first-install `stateVersion`;
   - the people who log in today.

   It stops on setups it cannot handle safely: legacy BIOS, Secure Boot, a full EFI partition, or Wi-Fi without NetworkManager. It also prints REVIEW lines for every old setting that needs a decision.
4. Builds the new system, then compares it with the running one: packages, systemd units, initrd contents, firmware, fstab and kernel parameters. Runs `switch-to-configuration dry-activate` to see what would restart, and arms rescue timers (`systemd-run --on-active=15min ...`) that bring the temporary Tailscale back if the laptop is not reachable after the switch.
5. Commits the host folder on the laptop and fetches that commit to Windows, which pushes it. Workers never push. Afterwards a `git pull` on the laptop is a plain fast-forward.
6. Starts `scripts/switch-over.sh` with `systemd-run` (with `-E PATH=/run/wrappers/bin:/run/current-system/sw/bin` and bash called directly), so the switch survives the SSH session dropping. It:
   - keeps today's system as the boot entry `before-asoldi`;
   - copies Tailscale's SSH host keys to `/etc/ssh`, so the host key stays the same after the handover;
   - installs systemd-boot if GRUB was used;
   - switches, which hands Tailscale over to the permanent service with the same identity;
   - restarts the temporary Tailscale if the permanent one does not come up.
7. Reconnects and checks the log, `/var/log/asoldi-switch.log`.

On a laptop with Nix older than 2.18 (NixOS 23.05 or older), the pinned nixpkgs cannot be evaluated with its own Nix. First fetch a newer one, then pass it as `NIX=`:

```sh
nix-store --realise /nix/store/1p2387dqm0plf5ijzi79rzzqc7sk31gn-nix-2.35.6
```

Use `nix-shell -p git` if git is missing.

### 3. Afterwards

- **Test reboot, with someone at the laptop.** Do not press anything at the boot menu. The first entry, the newest "NixOS (Generation N)", is the default and starts by itself after 5 seconds. The other entries are older systems: "NixOS [before-asoldi]" is the system from before the switch. Pick one only to go back, and the choice lasts one boot. The old systems lack the new apps and the permanent Tailscale. A laptop with disk encryption asks for the passphrase at every boot, and a worker stays offline until someone types it.
- **Drop the old entries once the test reboot worked,** so nobody boots them by mistake (they also keep the old users and rights):
  `rm /nix/var/nix/profiles/system-profiles/before-asoldi*`, then `nix-env -p /nix/var/nix/profiles/system --delete-generations old`, then `/run/current-system/bin/switch-to-configuration boot`.
- **Turn off Tailscale key expiry.** In https://login.tailscale.com/admin/machines, open the new machine's `⋯` menu and choose `Disable key expiry`. Otherwise it drops off the network after 180 days.
- **Passwords.** Accounts that are new on that laptop (`damianhc`, `sofushl`) start locked: set a password with `sudo passwd <name>` when someone needs to sign in at the screen. Existing accounts keep their passwords.
- **Logins, when needed:** `claude`, `gh auth login`, `cursor-agent login`.

## Fresh install on an empty laptop (erases the disk)

1. Add a host that imports `self.nixosModules.disko` and `self.nixosModules.hardware`. Copy `modules/hosts/Cospow/`, change the name, then commit and push.
2. Boot the NixOS installer and run:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run github:nix-community/disko/latest#disko-install -- --write-efi-boot-entries --flake github:Asoldi-Media/nixos#<Host> --disk main /dev/nvme0n1
```
