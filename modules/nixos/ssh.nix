# Feature module: OpenSSH server, key login only, port 22 open.
# Published as flake.nixosModules.ssh
{
  flake.nixosModules.ssh =
    { config, ... }:
    {
      services.openssh = {
        enable = true;
        openFirewall = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };
    };
}
