# Feature module: laptop power and input defaults, published as flake.nixosModules.laptop
{
  flake.nixosModules.laptop =
    { lib, ... }:
    {
      services.power-profiles-daemon.enable = true;
      services.upower.enable = true;
      services.libinput.enable = true;
      # mkDefault so a host module (worker.nix on Eeto) can override it.
      services.logind.settings.Login.HandleLidSwitch = lib.mkDefault "suspend";
    };
}
