# Feature module: COSMIC desktop (system side). Published as flake.nixosModules.cosmic
# The panel layout lives in modules/home/cosmic.nix (flake.homeModules.cosmic).
{
  flake.nixosModules.cosmic = { pkgs, ... }: {
    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;
    environment.systemPackages = with pkgs; [
      librewolf
    ];
  };
}
