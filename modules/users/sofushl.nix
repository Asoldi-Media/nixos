# User module: sofushl (admin). Published as flake.nixosModules.sofushl
{
  flake.nixosModules.sofushl = {
    users.users.sofushl = {
      isNormalUser = true;
      description = "sofushl";
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      initialPassword = "changeme"; # CHANGE with `passwd` after first login
    };
    home-manager.users.sofushl.home.stateVersion = "26.11";
  };
}
