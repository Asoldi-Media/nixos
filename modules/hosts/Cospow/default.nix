{ self, inputs, ... }:
{
  flake.nixosConfigurations.Cospow = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      { networking.hostName = "Cospow"; }
    ];
  };
}
