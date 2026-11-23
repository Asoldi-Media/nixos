# Feature module: one model split across the machines with llama.cpp RPC,
# published as flake.nixosModules.llm-cluster.
#
# Cospow (Tailscale name nix32-main, ThinkPad P14s Gen 5, Arc graphics) is the
# coordinator: it runs llama-server and sends each worker its share. The workers
# run the RPC server, started and stopped by the coordinator over SSH, not at
# boot: Eeto (nix32, ThinkPad T14s Gen 3, Iris Xe), Ideapad (nix8, IdeaPad L340,
# GTX 1650 and Intel UHD) and Stationary (nix8-1, desktop, GTX 1650 only).
#
# The fifth machine is the owner's Windows laptop (desktop-mep9e9d, ThinkPad
# T14s Gen 3, 16 GB). It runs rpc-server.exe from llama.cpp's Windows Vulkan
# release only when it is at home (it travels), so the cluster must work
# without it. The model files live on the coordinator's SSD, with the NAS
# (/mnt/nas/models) as the library.
{ inputs, ... }:
{
  flake.nixosModules.llm-cluster =
    { config, lib, pkgs, ... }:
    let
      cfg = config.asoldi.llm;
      # useCuda / useVulkan are this package only. nixpkgs.config.cudaSupport
      # stays unset: that flag would rebuild the whole system with CUDA.
      llama = (
        pkgs.llamaPackages.llama-cpp.override {
          useRpc = true;
          useVulkan = cfg.gpu == "intel";
          useCuda = cfg.gpu == "nvidia";
        }
      ).overrideAttrs (old: {
        # This pin installs the worker as ggml-rpc-server. The unit calls rpc-server.
        postInstall =
          (old.postInstall or "")
          + ''
            if [ ! -x "$out/bin/ggml-rpc-server" ]; then
              echo "llama.cpp did not install bin/ggml-rpc-server" >&2
              exit 1
            fi
            if [ ! -e "$out/bin/rpc-server" ]; then
              ln -s ggml-rpc-server "$out/bin/rpc-server"
            fi
          '';
      });
      llmCluster = pkgs.writeShellApplication {
        name = "llm-cluster";
        runtimeInputs = [
          llama
          pkgs.openssh
          pkgs.coreutils
          pkgs.iproute2 # `ss` for the status check
        ];
        text = ''
          workers=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.workers})
          rpc_port=${toString cfg.rpcPort}
          server_port=${toString cfg.serverPort}
          default_model=${lib.escapeShellArg cfg.model}

          usage() {
            cat <<EOF
          Usage: llm-cluster <command>

          Commands:
            start-workers
                On each worker: ssh -n -o ConnectTimeout=10 <worker> sudo systemctl start llama-rpc
                Reports each result and continues if a worker is offline.
            stop-workers
                Same as start-workers, with systemctl stop.
            status
                For each worker, prints systemctl is-active llama-rpc.
                Also reports whether llama-server is listening on port $server_port.
            serve [extra llama-server args...]
                Run llama-server here and send each worker its share of the model.
            help
                Show this help.

          Environment:
            LLM_MODEL
                GGUF to load. Default: $default_model
            LLM_EXTRA_RPC
                Adds machines that are not in the flake, as a comma-separated
                list of host:port. The Windows laptop is one of these, and only
                when it is at home. Example: LLM_EXTRA_RPC=desktop-mep9e9d:$rpc_port
                The cluster works without it.
          EOF
          }

          systemctl_workers() {
            local action="$1"
            local w failed=0
            for w in "''${workers[@]}"; do
              if ssh -n -o ConnectTimeout=10 "$w" sudo systemctl "$action" llama-rpc; then
                echo "$w: $action ok"
              else
                echo "$w: $action failed (offline or error)" >&2
                failed=1
              fi
            done
            return "$failed"
          }

          show_status() {
            local w state
            local listening
            for w in "''${workers[@]}"; do
              if state=$(ssh -n -o ConnectTimeout=10 "$w" systemctl is-active llama-rpc); then
                echo "$w: $state"
              elif [ -n "$state" ]; then
                echo "$w: $state"
              else
                echo "$w: unreachable" >&2
              fi
            done
            if listening=$(ss -H -ltn sport = ":$server_port"); then
              if [ -n "$listening" ]; then
                echo "llama-server: listening on port $server_port"
              else
                echo "llama-server: not listening on port $server_port"
              fi
            else
              echo "llama-server: could not check port $server_port" >&2
              return 1
            fi
          }

          rpc_backends() {
            local w list=""
            for w in "''${workers[@]}"; do
              if [ -n "$list" ]; then
                list="$list,$w:$rpc_port"
              else
                list="$w:$rpc_port"
              fi
            done
            if [ -n "''${LLM_EXTRA_RPC:-}" ]; then
              if [ -n "$list" ]; then
                list="$list,$LLM_EXTRA_RPC"
              else
                list="$LLM_EXTRA_RPC"
              fi
            fi
            printf '%s\n' "$list"
          }

          run_serve() {
            local list model
            list=$(rpc_backends)
            if [ -z "$list" ]; then
              echo "llm-cluster: no RPC backends. Set asoldi.llm.workers or LLM_EXTRA_RPC." >&2
              exit 1
            fi
            model="''${LLM_MODEL:-$default_model}"
            exec llama-server \
              -m "$model" \
              --rpc "$list" \
              -ngl 999 \
              --host 0.0.0.0 \
              --port "$server_port" \
              --jinja \
              --temp 1.0 \
              --top-p 0.95 \
              --top-k 20 \
              --min-p 0.0 \
              "$@"
          }

          main() {
            local cmd="''${1:-}"
            case "$cmd" in
              start-workers)
                systemctl_workers start
                ;;
              stop-workers)
                systemctl_workers stop
                ;;
              status)
                show_status
                ;;
              serve)
                shift
                run_serve "$@"
                ;;
              "" | help | -h | --help)
                usage
                ;;
              *)
                usage >&2
                exit 1
                ;;
            esac
          }

          main "$@"
        '';
      };
    in
    {
      options.asoldi.llm = {
        role = lib.mkOption {
          type = lib.types.enum [
            "coordinator"
            "worker"
          ];
          description = ''
            coordinator runs llama-server and hands each worker its share of the
            model. worker runs the RPC server, which is not started at boot.
          '';
        };
        gpu = lib.mkOption {
          type = lib.types.enum [
            "none"
            "intel"
            "nvidia"
          ];
          default = "none";
          description = ''
            Which GPU this machine's llama.cpp is built for.
            intel is Vulkan (Mesa), nvidia is CUDA, none is CPU.
          '';
        };
        rpcPort = lib.mkOption {
          type = lib.types.port;
          default = 50052;
          description = ''
            Port the RPC server listens on. The coordinator uses the same port
            in the worker list. Not opened in the firewall.
          '';
        };
        prime = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                intelBusId = lib.mkOption {
                  type = lib.types.str;
                  example = "PCI:0:2:0";
                  description = "PCI bus id of the Intel GPU.";
                };
                nvidiaBusId = lib.mkOption {
                  type = lib.types.str;
                  example = "PCI:1:0:0";
                  description = "PCI bus id of the NVIDIA GPU.";
                };
              };
            }
          );
          default = null;
          description = ''
            Intel + NVIDIA graphics on one laptop (PRIME offload).
            Null when the machine has a single GPU.
          '';
        };
        workers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "nix32"
            "nix8"
            "nix8-1"
          ];
          description = ''
            Tailscale names of the NixOS workers. Used by the coordinator.
            The Windows laptop is not in this list; set LLM_EXTRA_RPC for it.
          '';
        };
        serverPort = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Port for llama-server's OpenAI-compatible API.";
        };
        model = lib.mkOption {
          type = lib.types.str;
          default = "/home/damianhc/models/qwen3.8-flash-next/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf";
          description = ''
            GGUF file the coordinator loads. LLM_MODEL overrides it for one run.
          '';
        };
      };

      config = lib.mkMerge [
        {
          nixpkgs.overlays = [ inputs.llama-cpp.overlays.default ];
          environment.systemPackages = [ llama ];
        }
        (lib.mkIf (cfg.gpu == "intel") {
          # Mesa's Vulkan driver comes with this.
          hardware.graphics.enable = true;
        })
        (lib.mkIf (cfg.gpu == "nvidia") {
          # GTX 1650 is Turing. One architecture keeps the CUDA build short.
          nixpkgs.config.cudaCapabilities = [ "7.5" ];
          hardware.graphics.enable = true;
          services.xserver.videoDrivers =
            if cfg.prime != null then
              [
                "modesetting"
                "nvidia"
              ]
            else
              [ "nvidia" ];
          hardware.nvidia = {
            open = true;
            modesetting.enable = true;
            nvidiaSettings = false;
            package = config.boot.kernelPackages.nvidiaPackages.latest;
          }
          // lib.optionalAttrs (cfg.prime != null) {
            prime = {
              offload.enable = true;
              offload.enableOffloadCmd = true;
              intelBusId = cfg.prime.intelBusId;
              nvidiaBusId = cfg.prime.nvidiaBusId;
            };
          };
        })
        (lib.mkIf (cfg.role == "worker") {
          # rpc-server has no authentication, so this port must never be opened
          # on any interface other than Tailscale. tailscale0 is already a
          # trusted interface (worker.nix); that is the only path the
          # coordinator uses.
          systemd.services.llama-rpc = {
            description = "llama.cpp RPC server (started by the coordinator over SSH, not at boot)";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment.LLAMA_CACHE = "/var/cache/llama-rpc";
            serviceConfig = {
              ExecStart = "${llama}/bin/rpc-server --host 0.0.0.0 --port ${toString cfg.rpcPort} --cache";
              DynamicUser = true;
              CacheDirectory = "llama-rpc";
              SupplementaryGroups = [
                "render"
                "video"
              ];
              Restart = "on-failure";
              Nice = -5;
              LimitMEMLOCK = "infinity";
            };
          };
        })
        (lib.mkIf (cfg.role == "coordinator") {
          # No llama-server service yet: the first runs are by hand.
          environment.systemPackages = [ llmCluster ];
        })
      ];
    };
}
