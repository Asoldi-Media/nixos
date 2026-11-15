# PLACEHOLDER. Replace with: nixos-generate-config --show-hardware-config
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  nixpkgs.hostPlatform = "x86_64-linux";
}
