# Host composition: nixosConfigurations.eeehhto
{ self, inputs, ... }:
{
  flake.nixosConfigurations.Eeto = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.base
      self.nixosModules.laptop
      self.nixosModules.ssh
      self.nixosModules.git
      self.nixosModules.neovim
      self.nixosModules.desktop
      self.nixosModules.sofushl
      self.nixosModules.damianhc
      self.nixosModules.eeehhto-disko
      ./_hardware.nix
      { networking.hostName = "Eeto"; }
    ];
  };
}
