{ self, inputs, ... }:
{
  flake.nixosConfigurations.Ideapad = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      self.nixosModules.disko # fresh install with the shared disko layout (2026-11-22)
      self.nixosModules.hardware
      self.nixosModules.worker # always-on worker, Tailscale name nix8 (Lenovo IdeaPad L340-15IRH, 8 GB RAM)
      self.nixosModules.llm-cluster # llama.cpp RPC worker (GTX 1650 + Intel UHD)
      {
        networking.hostName = "Ideapad";
        asoldi.llm = {
          role = "worker";
          gpu = "nvidia";
          prime = {
            intelBusId = "PCI:0:2:0";
            nvidiaBusId = "PCI:1:0:0";
          };
        };
      }
    ];
  };
}
