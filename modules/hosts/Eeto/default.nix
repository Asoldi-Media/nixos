{ self, inputs, ... }:
{
  flake.nixosConfigurations.Eeto = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      { networking.hostName = "Eeto"; }
    ];
  };
}
