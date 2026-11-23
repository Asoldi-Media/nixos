# Feature module: the QNAP NAS on its own cable, published as flake.nixosModules.nas.
# Cospow (Tailscale name nix32-main) uses it. The NAS (QNAP TS-1635, 12 x 8 TB) is cabled
# straight into this laptop's built-in Ethernet port, with nothing else on that cable.
#
# - Fixed addresses: this laptop is 10.77.0.1 and hands the NAS 10.77.0.2 by DHCP (a
#   reservation on the NAS's MAC address, no address pool), so the NAS keeps its factory
#   network settings and gets the same address after a reset. No gateway and no DNS are
#   handed out, and nothing is forwarded for it: the NAS only ever talks to this laptop.
# - The NAS's NFS shares (models, agents, git, backups) mount under /mnt/nas on first use.
#   /mnt/nas is for admins (wheel) only.
# - Tailscale offers 10.77.0.0/24 as a subnet route, so the owner's own devices reach the
#   NAS from anywhere once the route is approved in the Tailscale admin console.
# - Tailscale and Docker both rewrite their traffic to come from this laptop (10.77.0.1),
#   the one host the NFS exports trust. So everything addressed to the NAS that does not
#   come from this laptop itself is dropped, except SMB (445), the web page (8080) and ping
#   from the tailnet.
{
  flake.nixosModules.nas =
    { lib, ... }:
    let
      port = "enp0s31f6"; # built-in Ethernet of the ThinkPad P14s Gen 5
      self4 = "10.77.0.1";
      nas = "10.77.0.2";
      nasMac = "24:5e:be:0e:ab:fe";
      shares = [
        "models"
        "agents"
        "git"
        "backups"
      ];
    in
    {
      networking.networkmanager.unmanaged = [ port ];
      networking.interfaces.${port}.ipv4.addresses = [
        {
          address = self4;
          prefixLength = 24;
        }
      ];
      networking.hosts.${nas} = [ "nas" ];
      networking.firewall.interfaces.${port}.allowedUDPPorts = [ 67 ]; # DHCP requests from the NAS

      # DHCP for the NAS only: no pool, so if this port is ever plugged into another network,
      # Kea answers nobody but the NAS's MAC address.
      services.kea.dhcp4 = {
        enable = true;
        settings = {
          interfaces-config = {
            interfaces = [ port ];
            service-sockets-max-retries = 60;
            service-sockets-retry-wait-time = 5000;
          };
          multi-threading.enable-multi-threading = false;
          lease-database = {
            type = "memfile";
            persist = true;
            name = "/var/lib/kea/dhcp4.leases";
          };
          valid-lifetime = 86400;
          subnet4 = [
            {
              id = 1;
              subnet = "10.77.0.0/24";
              interface = port; # match by port, not by the port's first address
              reservations = [
                {
                  hw-address = nasMac;
                  ip-address = nas;
                  hostname = "nas";
                }
              ];
            }
          ];
        };
      };
      systemd.services.kea-dhcp4-server = {
        wants = [ "network-addresses-${port}.service" ];
        after = [ "network-addresses-${port}.service" ];
      };

      # Hard mounts (the default) for git and restic. nolock: this laptop is the only NFS
      # client, and the NAS's lock callbacks could not get through the firewall anyway.
      fileSystems = lib.genAttrs (map (s: "/mnt/nas/${s}") shares) (mountPoint: {
        device = "${nas}:/${baseNameOf mountPoint}";
        fsType = "nfs";
        options = [
          "nfsvers=3"
          "nolock"
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
          "x-systemd.mount-timeout=20"
          "x-systemd.after=network-addresses-${port}.service"
          "nofail"
          "_netdev"
        ];
      });
      systemd.tmpfiles.rules = [ "d /mnt/nas 0750 root wheel -" ];

      services.tailscale = {
        useRoutingFeatures = "server";
        extraSetFlags = [ "--advertise-routes=10.77.0.0/24" ];
      };
      # Only an IPv4 route is offered; keep IPv6 forwarding off.
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkForce false;

      # In the raw table, so it runs before Docker's and Tailscale's own rules, which accept
      # and rewrite traffic from docker0 and tailscale0. No extraStopCommands on purpose: a
      # firewall reload or stop leaves these rules in place (fails closed).
      networking.firewall.extraCommands = ''
        iptables -t raw -N asoldi-nas-in 2>/dev/null || true
        iptables -t raw -F asoldi-nas-in
        iptables -t raw -A asoldi-nas-in -i lo -j RETURN
        iptables -t raw -A asoldi-nas-in -i tailscale0 -p tcp -m multiport --dports 445,8080 -j RETURN
        iptables -t raw -A asoldi-nas-in -i tailscale0 -p icmp -j RETURN
        iptables -t raw -A asoldi-nas-in -j DROP
        iptables -t raw -C PREROUTING -d 10.77.0.0/24 ! -i ${port} -j asoldi-nas-in 2>/dev/null ||
          iptables -t raw -A PREROUTING -d 10.77.0.0/24 ! -i ${port} -j asoldi-nas-in

        # The NAS may talk to this laptop (DHCP included), never through it.
        iptables -t raw -N asoldi-nas-out 2>/dev/null || true
        iptables -t raw -F asoldi-nas-out
        iptables -t raw -A asoldi-nas-out -d 255.255.255.255 -p udp --dport 67 -j RETURN
        iptables -t raw -A asoldi-nas-out -m addrtype --dst-type LOCAL -j RETURN
        iptables -t raw -A asoldi-nas-out -j DROP
        iptables -t raw -C PREROUTING -i ${port} -j asoldi-nas-out 2>/dev/null ||
          iptables -t raw -A PREROUTING -i ${port} -j asoldi-nas-out
      '';
    };
}
