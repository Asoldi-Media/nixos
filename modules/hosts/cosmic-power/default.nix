# Host composition: nixosConfigurations.cosmic-power
{ inputs, config, ... }:
{
  flake.nixosConfigurations.cosmic-power = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      config.flake.modules.nixos.base
      config.flake.modules.nixos.laptop
      config.flake.modules.nixos.cosmic
      config.flake.modules.nixos.sofushl
      config.flake.modules.nixos.damianhc
      ./_hardware.nix
      { networking.hostName = "cosmic-power"; }
    ];
  };
}
