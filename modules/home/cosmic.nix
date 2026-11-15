# Home module: Windows-like COSMIC panel. Published as flake.homeModules.cosmic
# One bottom taskbar, no dock: Start button, app list left; tray and clock right.
{ inputs, ... }:
{
  flake.homeModules.cosmic = {
    imports = [ inputs.cosmic-manager.homeManagerModules.cosmic-manager ];

    wayland.desktopManager.cosmic = {
      enable = true;
      # One list entry = one panel. No "Dock" entry, so there is no dock.
      panels = [
        {
          name = "Panel";
          anchor = { __type = "enum"; variant = "Bottom"; };
          anchor_gap = false;
          margin = 0;
          expand_to_edges = true;
          size = { __type = "enum"; variant = "M"; };
          output = { __type = "enum"; variant = "All"; };
          plugins_center = { __type = "optional"; value = [ ]; };
          plugins_wings = {
            __type = "optional";
            value = {
              __type = "tuple";
              value = [
                [
                  "com.system76.CosmicPanelAppButton" # Start menu
                  "com.system76.CosmicAppList" # taskbar: pinned and open apps
                ]
                [
                  "com.system76.CosmicAppletStatusArea"
                  "com.system76.CosmicAppletInputSources"
                  "com.system76.CosmicAppletBluetooth"
                  "com.system76.CosmicAppletNetwork"
                  "com.system76.CosmicAppletAudio"
                  "com.system76.CosmicAppletBattery"
                  "com.system76.CosmicAppletNotifications"
                  "com.system76.CosmicAppletTime" # clock, far right
                ]
              ];
            };
          };
        }
      ];
    };
  };
}
