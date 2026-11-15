{ self, ... }:
{
  flake.nixosModules.default = {
    imports = [
      self.nixosModules.base
      self.nixosModules.laptop
      self.nixosModules.ssh
      self.nixosModules.git
      self.nixosModules.neovim
      self.nixosModules.desktop
      self.nixosModules.sofushl
      self.nixosModules.damianhc
      self.nixosModules.disko
      self.nixosModules.hardware
    ];
  };
}
