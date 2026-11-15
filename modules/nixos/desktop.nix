# Feature module: COSMIC desktop (system side). Published as flake.nixosModules.cosmic
# The panel layout lives in modules/home/cosmic.nix (flake.homeModules.cosmic).
{
  flake.nixosModules.desktop = { pkgs, ... }: {
    services.desktopManager.cosmic.enable = true;
    programs.niri.enable = true;
    services.displayManager.cosmic-greeter.enable = true;
    environment.systemPackages = with pkgs; [
      librewolf
      btop
      claude-code
      cursor-cli
      code-cursor
    ];
  };
}
