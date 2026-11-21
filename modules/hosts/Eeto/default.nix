{ self, inputs, ... }:
{
  flake.nixosConfigurations.Eeto = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      self.nixosModules.disko # installed with the shared disko layout
      self.nixosModules.hardware
      self.nixosModules.worker # always-on worker, Tailscale name nix32
      { networking.hostName = "Eeto"; }
    ];
  };
}
