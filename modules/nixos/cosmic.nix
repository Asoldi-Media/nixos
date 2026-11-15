# Feature module: COSMIC desktop (system side). Published as flake.nixosModules.cosmic
# The panel layout lives in modules/home/cosmic.nix (flake.homeModules.cosmic).
{ self, inputs, ... }:
{
  flake.nixosModules.cosmic = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "back";
      sharedModules = [ self.homeModules.cosmic ];
    };
  };
}
