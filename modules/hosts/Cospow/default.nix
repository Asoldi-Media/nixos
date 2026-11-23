{ self, inputs, ... }:
{
  flake.nixosConfigurations.Cospow = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      self.nixosModules.disko # installed with the shared disko layout
      self.nixosModules.hardware
      self.nixosModules.worker # always-on worker since 2026-11-21, Tailscale name nix32-main (the main worker)
      self.nixosModules.nas # the QNAP NAS on its own cable into the built-in Ethernet port (2026-11-23)
      self.nixosModules.llm-cluster # llama.cpp RPC coordinator (RTX 500 Ada, Vulkan)
      (
        { config, lib, ... }:
        let
          llmPort = toString config.asoldi.llm.serverPort;
        in
        {
          networking.hostName = "Cospow";
          asoldi.llm = {
            role = "coordinator";
            gpu = "vulkan";
          };
          # Core Ultra 7 155H: Intel NPU driver and firmware, as in the original install.
          hardware.cpu.intel.npu.enable = true;

          # damianhc is the only admin on this laptop. sofushl keeps a normal
          # account, without the usual ways around that:
          users.users.sofushl.extraGroups = lib.mkForce [ "networkmanager" ];
          users.users.sofushl.openssh.authorizedKeys.keys = lib.mkForce [ ]; # no SSH login here (there was none before)
          users.users.sofushl.uid = 1001; # its existing uid, pinned for the slice below
          # Nor may it open the local model's port while llama-server is down, which
          # would catch the agents' prompts (no stop rule needed: it is a cgroup setting).
          systemd.slices."user-${toString config.users.users.sofushl.uid}" = {
            overrideStrategy = "asDropin";
            sliceConfig.SocketBindDeny = [ "tcp:${llmPort}" ];
          };
          security.pam.services.su.requireWheel = true; # su only for admins
          boot.loader.systemd-boot.editor = false; # no kernel command-line edits in the boot menu
          # Tailscale SSH lets every device of the owner's account in as root, so a
          # non-admin here must not reach the tailnet at all (MagicDNS stays allowed).
          networking.firewall.extraCommands = ''
            ip46tables -N asoldi-no-tailnet 2>/dev/null || true
            ip46tables -F asoldi-no-tailnet
            iptables -A asoldi-no-tailnet -d 100.100.100.100 -p udp --dport 53 -j RETURN
            iptables -A asoldi-no-tailnet -d 100.100.100.100 -p tcp --dport 53 -j RETURN
            ip6tables -A asoldi-no-tailnet -d fd7a:115c:a1e0::53 -p udp --dport 53 -j RETURN
            ip6tables -A asoldi-no-tailnet -d fd7a:115c:a1e0::53 -p tcp --dport 53 -j RETURN
            ip46tables -A asoldi-no-tailnet -j REJECT
            ip46tables -C OUTPUT -o tailscale0 -m owner --uid-owner sofushl -j asoldi-no-tailnet 2>/dev/null ||
              ip46tables -A OUTPUT -o tailscale0 -m owner --uid-owner sofushl -j asoldi-no-tailnet
            # Nor the NAS cable (modules/nixos/nas.nix). No stop rule for it: it stays on reload.
            ip46tables -C OUTPUT -o enp0s31f6 -m owner --uid-owner sofushl -j REJECT 2>/dev/null ||
              ip46tables -A OUTPUT -o enp0s31f6 -m owner --uid-owner sofushl -j REJECT
            # Nor the local model's API (modules/nixos/llm-cluster.nix), which loopback would
            # otherwise reach. No stop rule for it either: it stays on reload.
            ip46tables -C OUTPUT -o lo -p tcp --dport ${llmPort} -m owner --uid-owner sofushl -j REJECT 2>/dev/null ||
              ip46tables -A OUTPUT -o lo -p tcp --dport ${llmPort} -m owner --uid-owner sofushl -j REJECT
          '';
          networking.firewall.extraStopCommands = ''
            ip46tables -D OUTPUT -o tailscale0 -m owner --uid-owner sofushl -j asoldi-no-tailnet 2>/dev/null || true
            ip46tables -F asoldi-no-tailnet 2>/dev/null || true
            ip46tables -X asoldi-no-tailnet 2>/dev/null || true
          '';
        }
      )
    ];
  };
}
