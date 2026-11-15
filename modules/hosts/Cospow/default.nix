# Host composition: nixosConfigurations.cosmic-power
{ self, inputs, ... }:
{
  flake.nixosConfigurations.Cospow = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.base
      self.nixosModules.laptop
      self.nixosModules.ssh
      self.nixosModules.git
      self.nixosModules.neovim
      self.nixosModules.desktop
      self.nixosModules.sofushl
      self.nixosModules.damianhc
      self.nixosModules.cosmic-power-disko
      ./_hardware.nix
      { networking.hostName = "Cospow"; }
    ];
  };
}
