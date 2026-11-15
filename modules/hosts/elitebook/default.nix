# Host composition: picks feature modules and builds nixosConfigurations.elitebook
{ inputs, config, ... }:
{
  flake.nixosConfigurations.elitebook = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      config.flake.modules.nixos.base
      ./_hardware.nix # "_" prefix: skipped by import-tree, imported explicitly
      { networking.hostName = "elitebook"; }
    ];
  };
}
