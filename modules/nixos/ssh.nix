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

      # Fail the build, not the login: password auth is off, so a user without a key is locked out.
      assertions = [
        {
          assertion = config.users.users.sofushl.openssh.authorizedKeys.keys != [ ];
          message = "ssh: sofushl has no authorized key. Add one in modules/users/sofushl.nix.";
        }
      ];
    };
}
