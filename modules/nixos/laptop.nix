# Feature module: laptop power and input defaults, published as flake.modules.nixos.laptop
{
  flake.modules.nixos.laptop = {
    services.power-profiles-daemon.enable = true;
    services.upower.enable = true;
    services.libinput.enable = true;
    services.logind.settings.Login.HandleLidSwitch = "suspend";
  };
}
