# Host composition: nixosConfigurations.eeehhto
{ self, inputs, ... }:
{
  flake.nixosConfigurations.eeehhto = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.base
      self.nixosModules.laptop
      self.nixosModules.ssh
      self.nixosModules.etc-nixos
      self.nixosModules.cosmic
      self.nixosModules.sofushl
      self.nixosModules.damianhc
      self.nixosModules.eeehhto-disko
      ./_hardware.nix
      { networking.hostName = "eeehhto"; }
    ];
  };
}
