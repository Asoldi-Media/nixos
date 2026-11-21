{ self, inputs, ... }:
{
  flake.nixosConfigurations.Cospow = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      self.nixosModules.disko # installed with the shared disko layout
      self.nixosModules.hardware
      { networking.hostName = "Cospow"; }
    ];
  };
}
