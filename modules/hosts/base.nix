{ self, ... }:
{
  # Everything a laptop in this repo runs: settings, desktop, tools and users.
  # Disk layout and hardware are per host: Cospow and Eeto were installed with
  # the shared disko layout (disko.nix + hardware.nix); a laptop added with
  # scripts/add-host.sh keeps its own generated _hardware.nix instead.
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
    ];
  };
}
