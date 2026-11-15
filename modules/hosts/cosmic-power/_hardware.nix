# PLACEHOLDER. Replace with: nixos-generate-config --show-hardware-config
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  nixpkgs.hostPlatform = "x86_64-linux";
}
