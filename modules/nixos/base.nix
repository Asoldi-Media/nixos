# Feature module: shared NixOS settings, published as flake.nixosModules.base
{
  flake.nixosModules.base =
    { pkgs, lib, ... }:
    {
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      nixpkgs.config.allowUnfree = true;
      time.timeZone = "Europe/Oslo";
      i18n.defaultLocale = "en_US.UTF-8";
      networking.networkmanager.enable = true;
      environment.systemPackages = [ pkgs.git ];
      system.stateVersion = lib.mkDefault "26.11";
    };
}
