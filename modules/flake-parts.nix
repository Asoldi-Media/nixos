{ inputs, ... }:
{
  # Provides the `flake.modules.<class>.<name>` option used by all feature modules.
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [ "x86_64-linux" ];
}
