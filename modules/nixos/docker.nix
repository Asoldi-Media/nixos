{
  flake.nixosModules.docker =
    { pkgs, userconf, ... }:

    {
      virtualisation.docker.rootless = {
        enable = true;
        setSocketVariable = true;
        daemon.settings = {
          default-address-pools = [
            {
              base = "172.17.0.0/16";
              size = 24;
            }
          ];
        };
      };

      environment.systemPackages = with pkgs; [
        docker
        docker-compose
        gnumake
      ];
    };

  flake.homeModules.docker = {
    programs.docker-cli.enable = true;
    programs.lazydocker.enable = true;
  };
}
