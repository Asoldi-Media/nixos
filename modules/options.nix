# Declares flake outputs that flake-parts does not provide.
{ lib, ... }:
{
  options.flake.homeModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
    description = "Home-manager modules, usable on any system.";
  };
}
