# Feature module: one model split across the machines with llama.cpp RPC,
# published as flake.nixosModules.llm-cluster.
#
# Cospow (Tailscale name nix32-main, ThinkPad P14s Gen 5, Arc graphics plus an
# RTX 500 Ada) is the coordinator: it runs llama-server and sends each worker its
# share. The workers run the RPC server, started and stopped by the coordinator
# over SSH, never at boot: Eeto (nix32, ThinkPad T14s Gen 3, Iris Xe), Ideapad
# (nix8, IdeaPad L340, GTX 1650 and Intel UHD) and Stationary (nix8-1, desktop,
# GTX 1650 only). Nothing runs until `llm-cluster start-workers` and `serve`.
#
# Every GPU is driven through Vulkan (Mesa): the Intel ones by ANV, the NVIDIA ones
# by NVK on the open nouveau driver. No proprietary NVIDIA driver or CUDA build is
# needed (tested 2026-11-23: both GTX 1650s and the RTX 500 show up in llama.cpp).
# Shared-memory iGPUs are left out where a dedicated card exists, so the model
# does not eat the machine's RAM twice.
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
      llama = (
        pkgs.llamaPackages.llama-cpp.override {
          useRpc = true;
          useWebUi = false; # upstream's Nix build of the browser UI fails at b12655; agents use the API
          useVulkan = cfg.gpu == "vulkan";
          useCuda = false;
        }
      ).overrideAttrs (old: {
        webui = null; # upstream keeps the UI build as an attribute even with useWebUi = false
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
          local_devices=${lib.escapeShellArg cfg.serverDevices}
          slots=${toString cfg.parallel}

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
                Uses this machine's devices ($local_devices) plus every RPC worker;
                what does not fit stays on this machine's CPU, read from the SSD.
                $slots agent slots share one context, sized by --fit to the free
                memory unless you pass -c N. Later args win over these defaults.
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

          # Devices for -dev: this machine's own (asoldi.llm.serverDevices), then RPC0..RPCn-1,
          # which llama.cpp names in the order of the --rpc list.
          device_list() {
            local list="$1" devs="$local_devices" n i
            IFS=',' read -r -a entries <<<"$list"
            n=''${#entries[@]}
            for ((i = 0; i < n; i++)); do
              if [ -n "$devs" ]; then
                devs="$devs,RPC$i"
              else
                devs="RPC$i"
              fi
            done
            printf '%s\n' "$devs"
          }

          run_serve() {
            local list model devs
            list=$(rpc_backends)
            if [ -z "$list" ]; then
              echo "llm-cluster: no RPC backends. Set asoldi.llm.workers or LLM_EXTRA_RPC." >&2
              exit 1
            fi
            devs=$(device_list "$list")
            model="''${LLM_MODEL:-$default_model}"
            # --fit (on by default) sizes each device's share to its free memory.
            exec llama-server \
              -m "$model" \
              --rpc "$list" \
              -dev "$devs" \
              -np "$slots" \
              --kv-unified \
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
            "vulkan"
          ];
          default = "none";
          description = ''
            vulkan builds llama.cpp for Vulkan (Mesa: ANV for Intel, NVK for NVIDIA);
            none is CPU only.
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
        rpcDevices = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "Vulkan1";
          description = ''
            Worker only: devices rpc-server offers, comma separated, as
            `llama-server --list-devices` names them. Empty offers them all.
          '';
        };
        serverDevices = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "Vulkan1";
          description = ''
            Coordinator only: this machine's own devices used next to the RPC
            workers, comma separated. Empty uses only the workers (and the CPU).
          '';
        };
        parallel = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4;
          description = ''
            Coordinator only: agent slots in llama-server. They share one KV
            cache (--kv-unified), whose size --fit picks from the free memory
            unless `serve -c N` sets it.
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
        (lib.mkIf (cfg.gpu == "vulkan") {
          # Mesa's Vulkan drivers (ANV, NVK) come with this.
          hardware.graphics.enable = true;
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
              ExecStart =
                "${llama}/bin/rpc-server --host 0.0.0.0 --port ${toString cfg.rpcPort} --cache"
                + lib.optionalString (cfg.rpcDevices != "") " --device ${cfg.rpcDevices}";
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
