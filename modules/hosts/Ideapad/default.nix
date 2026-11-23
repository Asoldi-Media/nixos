{ self, inputs, ... }:
{
  flake.nixosConfigurations.Ideapad = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      self.nixosModules.disko # fresh install with the shared disko layout (2026-11-22)
      self.nixosModules.hardware
      self.nixosModules.worker # always-on worker, Tailscale name nix8 (Lenovo IdeaPad L340-15IRH, 8 GB RAM)
      self.nixosModules.llm-cluster # llama.cpp RPC worker (GTX 1650, Vulkan)
      {
        networking.hostName = "Ideapad";
        asoldi.llm = {
          role = "worker";
          gpu = "vulkan";
          rpcDevices = "Vulkan1"; # the GTX 1650 only; the Intel UHD would take the 8 GB of system RAM
        };
      }
    ];
  };
}
