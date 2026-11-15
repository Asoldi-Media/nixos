{
  flake.nixosModules.node =
    {
      pkgs,
      config,
      ...
    }:

    {
      programs.npm = {
        enable = true;
        package = pkgs.nodejs_26;
        npmrc = ''
          prefix = ''${HOME}/.npm
          init-license=PolyForm-Noncommercial-1.0.0
          init-author-name=Asoldi Media
          init-author-email=damian@asoldi.com
          color=true
          update-notifier=false
          fund=false
        '';
      };
    };
}
