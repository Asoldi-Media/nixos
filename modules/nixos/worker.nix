# Feature module: always-on worker. Eeto (Tailscale name nix32) uses it, and so does
# every laptop added with scripts/add-host.sh. Reachable over Tailscale SSH, never
# sleeps, passwordless sudo for damianhc, Docker and dev tools.
# Published as flake.nixosModules.worker. Cospow (nix32-main) uses it too.
{
  flake.nixosModules.worker =
    { pkgs, ... }:
    {
      # Claude Code works here without approval prompts (owner decision 2026-11-21:
      # "Auto mode + no prompts"). Managed settings apply to every session on this laptop:
      # - auto mode by default; its safety check still blocks risky actions without asking;
      # - Workflow launches pre-approved (a large workflow script cannot be approved in the
      #   dialog at all, so without this a worker waits forever);
      # - after a usage limit, wait for the reset and carry on;
      # - every session starts Remote Control, so it shows up at claude.ai/code;
      # - a phone notification (Claude app) when a question or prompt waits, or a task ends.
      environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
        permissions = {
          defaultMode = "auto";
          allow = [ "Workflow" ];
        };
        skipWorkflowUsageWarning = true;
        autoContinueAtUsageLimit = true;
        remoteControlAtStartup = true;
        inputNeededNotifEnabled = true;
        agentPushNotifEnabled = true;
        taskCompleteNotifEnabled = true;
        # Sub-agents and workflow agents keep their prompt cache for an hour instead of
        # 5 minutes (owner, 2026-11-22). They often wait on test runs or Grok jobs for longer
        # than 5 minutes; with the short cache each such wait re-wrote their whole context,
        # about a quarter of a week's Claude usage.
        subagentPromptCacheTtl = "1h";
      };
      # Managed instructions for every Claude session on this laptop
      environment.etc."claude-code/CLAUDE.md".text = ''
        # Asoldi worker laptop (managed by github.com/Asoldi-Media/nixos, modules/nixos/worker.nix)

        This laptop is one of the owner's always-on workers. Work runs here without approval
        prompts: auto mode is the default and Workflow launches are pre-approved. Do not ask the
        owner to approve routine steps; keep the questions for real decisions.

        When you need the owner (a decision, a login, something only he can do):
        1. Ask with AskUserQuestion in your own session. Sessions run with Remote Control, so the
           question shows up at claude.ai/code and in the Claude app, on whichever computer or
           phone he uses day to day.
        2. Also send a push notification (PushNotification) saying which session is waiting.
        3. In a long job, also write the question into the job's owner-items file, and keep
           working on everything that does not depend on the answer.

        Start long-running sessions in tmux, e.g.
        `tmux new -d -s <name> claude --remote-control "<host>: <name>"`, so they survive a
        closed SSH connection and can be opened from claude.ai/code.

        ## Model routing (2026-11-22)
        Route work by cost. Mechanical lookups go to `scout` (Haiku), long jobs and Grok runs to
        `runner` (Haiku), code search to `Explore` (Sonnet), medium work to Sonnet, code-writing
        to Grok through Cursor, plans to Opus at high, and reviews plus push or publish gates to
        `reviewer` (Opus at xhigh). Judgment never goes below Sonnet. Load the `model-routing`
        skill before delegating or writing a workflow; every workflow agent names a tier, also
        under ultracode.
      '';

      # Model routing (owner, 2026-11-22: make the shared Claude limit last). The sub-agents,
      # the routing skill and the usage scanners live in ./claude-code and are linked into
      # damianhc's ~/.claude, so every worker has the same copies. Opus effort and the
      # compaction point stay in ~/.claude/settings.json (modelSettings), so a machine or a
      # session can still tune them with /effort and /autocompact.
      systemd.tmpfiles.rules =
        let
          src = ../../claude-code;
          home = "/home/damianhc/.claude";
          link = rel: "L+ ${home}/${rel} - - - - ${src}/${rel}";
        in
        [
          # ~/.claude itself first, owned by damianhc. Without it a fresh install gets
          # ~/.claude created as root: Claude Code cannot save its login there, and
          # tmpfiles refuses the rules below (unsafe path), so nothing gets linked.
          "d ${home} 0755 damianhc users -"
          "d ${home}/agents 0755 damianhc users -"
          "d ${home}/skills 0755 damianhc users -"
          "d ${home}/skills/model-routing 0755 damianhc users -"
          "d ${home}/usage-tools 0755 damianhc users -"
        ]
        ++ map link [
          "agents/scout.md"
          "agents/runner.md"
          "agents/Explore.md"
          "agents/reviewer.md"
          "skills/model-routing/SKILL.md"
          "usage-tools/usage-scan.mjs"
          "usage-tools/cache-miss-scan.mjs"
          "usage-tools/context-scan.mjs"
        ];

      # Reach the other workers by their Tailscale name: `ssh nix32-main`, `ssh nix32`, ...
      # (Tailscale SSH; the user on every worker is damianhc)
      programs.ssh.extraConfig = ''
        Host nix*
          User damianhc
          StrictHostKeyChecking accept-new
          ServerAliveInterval 30
          ServerAliveCountMax 4
          ConnectTimeout 10
      '';

      # Recover from a crash without anyone at the laptop. nix32 froze on 2026-11-21 after a
      # kernel oops and stayed down until someone held the power button.
      boot.kernel.sysctl = {
        "kernel.panic_on_oops" = 1; # an oops leaves a half-dead kernel; panic instead
        "kernel.softlockup_panic" = 1; # a CPU stuck in the kernel: panic
        "kernel.panic" = 10; # reboot 10 seconds after a panic
      };
      # Hardware watchdog: if the kernel freezes completely, the board resets the laptop
      systemd.settings.Manager = {
        RuntimeWatchdogSec = "60s";
        RebootWatchdogSec = "10min";
      };

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

      # Always on the charger: spare the battery. Laptops with a charge threshold (the
      # ThinkPads) stop charging at 80%. Laptops without one, such as Lenovo IdeaPads
      # (nix8), get their long-life mode instead, which holds the battery at about 60%.
      # Skipped on hardware with neither.
      systemd.services.battery-charge-limit = {
        description = "Limit battery charging (80% threshold, or long-life mode)";
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExistsGlob = [
          "|/sys/class/power_supply/BAT*/charge_control_end_threshold"
          "|/sys/class/power_supply/BAT*/charge_types"
          "|/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          limited=no
          for bat in /sys/class/power_supply/BAT*; do
            if [ -e "$bat/charge_control_end_threshold" ]; then
              echo 80 > "$bat/charge_control_end_threshold"
              limited=yes
            elif [ -e "$bat/charge_types" ] && grep -qw Long_Life "$bat/charge_types"; then
              echo Long_Life > "$bat/charge_types"
              limited=yes
            fi
          done
          # Older kernels expose the IdeaPad switch only here (the same setting as Long_Life;
          # newer kernels log it as deprecated, so only use it when nothing above applied)
          if [ "$limited" = no ]; then
            for f in /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode; do
              if [ -e "$f" ]; then
                echo 1 > "$f"
              fi
            done
          fi
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
