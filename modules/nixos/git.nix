# Feature module: system-wide git config, plus /etc/nixos writable by group wheel.
# Published as flake.nixosModules.git
{
  flake.nixosModules.git = {
    programs.git = {
      enable = true;
      lfs.enable = true;
      config = {
        init.defaultBranch = "main";
        pull.rebase = true;
        push = {
          autoSetupRemote = true;
          followTags = true;
        };
        fetch = {
          prune = true;
          pruneTags = true;
        };
        help.autocorrect = "prompt";
        core.editor = "nvim";
        # The wheel group shares /etc/nixos, owned by root.
        safe.directory = "/etc/nixos";
        alias = {
          st = "status -sb";
          co = "checkout";
          sw = "switch";
          br = "branch";
          ci = "commit";
          lg = "log --graph --oneline --decorate";
          last = "log -1 HEAD --stat";
          unstage = "restore --staged";
        };
      };
    };

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
