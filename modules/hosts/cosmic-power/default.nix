# Host composition: nixosConfigurations.cosmic-power
{ self, inputs, ... }:
{
  flake.nixosConfigurations.cosmic-power = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.base
      self.nixosModules.laptop
      self.nixosModules.ssh
      self.nixosModules.cosmic
      self.nixosModules.sofushl
      self.nixosModules.damianhc
      self.nixosModules.cosmic-power-disko
      ./_hardware.nix
      { networking.hostName = "cosmic-power"; }
    ];
  };
}
