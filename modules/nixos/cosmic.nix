# Feature module: COSMIC desktop with a single top panel and no dock.
# Published as flake.modules.nixos.cosmic (system) and flake.modules.homeManager.cosmic (user).
{ inputs, config, ... }:
{
  flake.modules.nixos.cosmic = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "back";
      sharedModules = [ config.flake.modules.homeManager.cosmic ];
    };
  };

  flake.modules.homeManager.cosmic = {
    imports = [ inputs.cosmic-manager.homeManagerModules.cosmic-manager ];

    wayland.desktopManager.cosmic = {
      enable = true;
      # One list entry = one panel. No "Dock" entry, so there is no dock.
      panels = [
        {
          name = "Panel";
          anchor = { __type = "enum"; variant = "Top"; };
          anchor_gap = false;
          margin = 0;
          expand_to_edges = true;
          size = { __type = "enum"; variant = "M"; };
          output = { __type = "enum"; variant = "All"; };
        }
      ];
    };
  };
}
