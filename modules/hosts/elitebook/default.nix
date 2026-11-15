# Host composition: picks feature modules and builds nixosConfigurations.elitebook
{ self, inputs, ... }:
{
  flake.nixosConfigurations.elitebook = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.base
      ./_hardware.nix # "_" prefix: skipped by import-tree, imported explicitly
      { networking.hostName = "elitebook"; }
    ];
  };
}
