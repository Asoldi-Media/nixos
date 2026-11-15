# User module: damianhc (standard user, no sudo). Published as flake.nixosModules.damianhc
{
  flake.nixosModules.damianhc = {
    users.users.damianhc = {
      isNormalUser = true;
      description = "damianhc";
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      initialPassword = "changeme"; # CHANGE with `passwd` after first login
    };
  };
}
