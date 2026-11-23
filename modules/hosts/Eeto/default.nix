{ self, inputs, ... }:
{
  flake.nixosConfigurations.Eeto = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      self.nixosModules.disko # installed with the shared disko layout
      self.nixosModules.hardware
      self.nixosModules.worker # always-on worker, Tailscale name nix32
      self.nixosModules.llm-cluster # llama.cpp RPC worker (Iris Xe)
      {
        networking.hostName = "Eeto";
        asoldi.llm = {
          role = "worker";
          gpu = "intel";
        };
      }
    ];
  };
}
