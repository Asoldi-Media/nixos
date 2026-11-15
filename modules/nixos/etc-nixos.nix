# Feature module: /etc/nixos owned by group wheel, writable by all admins.
# Published as flake.nixosModules.etc-nixos
{
  flake.nixosModules.etc-nixos = {
    # Applied at every boot and on every switch, so the setting persists.
    systemd.tmpfiles.rules = [
      # Directory: root:wheel, setgid so new files inherit group wheel.
      "d /etc/nixos 2775 root wheel -"
      # Recursively fix the group of existing files.
      "Z /etc/nixos - root wheel -"
      # Default ACL: new files stay group-writable whatever the user's umask.
      "A+ /etc/nixos - - - - group:wheel:rwX,default:group:wheel:rwX"
    ];
  };
}
