# User module: sofushl (admin). Published as flake.modules.nixos.sofushl
{
  flake.modules.nixos.sofushl = {
    users.users.sofushl = {
      isNormalUser = true;
      description = "sofushl";
      extraGroups = [ "wheel" "networkmanager" ];
      initialPassword = "changeme"; # CHANGE with `passwd` after first login
    };
    home-manager.users.sofushl.home.stateVersion = "25.05";
  };
}
