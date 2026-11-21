# Feature module: always-on worker "nix32" (Tailscale name). Reachable over
# Tailscale SSH, never sleeps, passwordless sudo for damianhc, Docker and dev tools.
# Published as flake.nixosModules.worker. Imported by Eeto only (not Cospow).
{
  flake.nixosModules.worker =
    { pkgs, ... }:
    {
      # Reach this laptop from all my devices, from anywhere (Tailscale SSH)
      services.tailscale = {
        enable = true;
        openFirewall = true; # UDP 41641: direct peer-to-peer links instead of DERP relays
      };
      networking.firewall.trustedInterfaces = [ "tailscale0" ];

      # Full access without passwords: this laptop is a dedicated worker.
      # Scoped to damianhc only; sofushl (also wheel) still needs a password.
      # For every wheel member instead: security.sudo.wheelNeedsPassword = false;
      security.sudo.extraRules = [
        {
          users = [ "damianhc" ];
          commands = [
            {
              command = "ALL";
              options = [
                "NOPASSWD"
                "SETENV" # keep sudo -E working, same as the %wheel rule
              ];
            }
          ];
        }
      ];
      # wheel and networkmanager come from users/damianhc.nix; lists merge.
      users.users.damianhc.extraGroups = [ "docker" ];
      # User services (Remote Control, workers) start at boot and keep running without a login
      users.users.damianhc.linger = true;
      # More open files for builds, file watchers and test suites. Soft limit only:
      # the hard limit stays at systemd's 524288 ("-" would lower it to 65536).
      security.pam.loginLimits = [
        {
          domain = "damianhc";
          type = "soft";
          item = "nofile";
          value = "65536";
        }
      ];
      # inotify: NixOS already sets fs.inotify.max_user_instances/watches to 524288; no override.

      # Never sleep. Lid closed = keep running. The screen may go dark; that is fine.
      systemd.targets.sleep.enable = false;
      systemd.targets.suspend.enable = false;
      systemd.targets.hibernate.enable = false;
      systemd.targets.hybrid-sleep.enable = false;
      services.logind.settings.Login = {
        HandleLidSwitch = "ignore"; # overrides the mkDefault "suspend" in laptop.nix
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
        HandleSuspendKey = "ignore";
        IdleAction = "ignore";
      };
      # Default is HybridSleep, which is masked above and would fail; shut down
      # cleanly at critical battery (e.g. charger unplugged) instead of dying hard.
      services.upower.criticalPowerAction = "PowerOff";

      # Always on the charger: stop charging at 80% to spare the battery.
      # Skipped on hardware without a charge limit.
      systemd.services.battery-charge-limit = {
        description = "Stop battery charging at 80%";
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExistsGlob = "/sys/class/power_supply/BAT*/charge_control_end_threshold";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
            echo 80 > "$f"
          done
        '';
      };

      # Compressed swap in RAM (up to 25% of it): headroom for big builds and test runs
      zramSwap = {
        enable = true;
        memoryPercent = 25;
      };

      # Steadier, lower-latency Wi-Fi
      networking.networkmanager.wifi.powersave = false;

      # Tools
      environment.systemPackages = with pkgs; [
        git
        gh
        nodejs_24
        ripgrep
        jq
        curl
        wget
        rsync
        tmux
        htop
        unzip
        gnumake
        gcc
        python3 # also node-gyp builds
        zip
        file
        lsof
        dos2unix # CRLF files from Windows
      ];
      virtualisation.docker.enable = true;
      # Sundays: drop stopped containers, unused networks and dangling images/cache older than 7 days
      virtualisation.docker.autoPrune = {
        enable = true;
        dates = "Sun 04:30";
        flags = [
          "--filter"
          "until=168h"
        ];
      };
      programs.nix-ld.enable = true; # lets downloaded Linux programs run (Claude Code, Cursor CLI, npm binaries)
      environment.localBinInPath = true; # puts ~/.local/bin on PATH

      # Keep the disk from filling up
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
      nix.settings.auto-optimise-store = true;
    };
}
