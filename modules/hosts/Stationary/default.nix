{ self, inputs, ... }:
{
  flake.nixosConfigurations.Stationary = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      self.nixosModules.disko # fresh install with the shared disko layout (2026-11-23)
      self.nixosModules.hardware
      self.nixosModules.worker # always-on worker, Tailscale name nix8-1 (desktop: ASUS EX-A320M-GAMING, Ryzen 5 2600, 8 GB RAM, GTX 1650)
      (
        { lib, pkgs, ... }:
        {
          networking.hostName = "Stationary";

          # Two SATA drives, no NVMe. NixOS goes on the 240 GB Kingston; the 512 GB
          # drive is extra storage at /data (nofail, so a missing drive never blocks boot).
          disko.devices.disk.main.device = lib.mkForce "/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B738050F2D1";
          disko.devices.disk.storage = {
            type = "disk";
            device = "/dev/disk/by-id/ata-Vi550_S3_SSD_20022115900571";
            content = {
              type = "gpt";
              partitions.data = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/data";
                  mountOptions = [ "nofail" ];
                };
              };
            };
          };
          systemd.tmpfiles.rules = [ "d /data 0755 damianhc users -" ];
          boot.initrd.availableKernelModules = [ "ahci" ];

          # AMD Ryzen, not Intel.
          boot.kernelModules = [ "kvm-amd" ];
          hardware.cpu.amd.updateMicrocode = true;
          hardware.cpu.intel.updateMicrocode = false;

          # ASUS USB-AX56 Wi-Fi adapter. It starts as a driver CD (0bda:1a2b) until
          # usb-modeswitch switches it to 0b05:1997, and its driver (rtw89_8852au) is
          # missing from the 6.18 LTS kernel, so this host runs the newest kernel.
          hardware.usb-modeswitch.enable = true;
          boot.kernelPackages = pkgs.linuxPackages_latest;
        }
      )
    ];
  };
}
