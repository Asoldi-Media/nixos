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
# does not eat the machine's RAM twice: llama.cpp skips the coordinator's Arc by
# itself, and a worker hides its iGPU with asoldi.llm.vulkanDevice.
#
# The API needs a key (Authorization: Bearer <key>, from ~/.config/llm-cluster/api-key
# on the coordinator). Every prompt passes through the workers' memory as hidden
# states, so agents with client material use the cluster only with the owner's OK.
#
# Deploy from the coordinator (nixos-rebuild --target-host): llama.cpp is built here,
# not in a binary cache, and the 8 GB workers should not compile it themselves.
#
# The fifth machine is the owner's Windows laptop (desktop-mep9e9d, ThinkPad
# T14s Gen 3, 16 GB). It runs rpc-server.exe from llama.cpp's Windows Vulkan
# release (same RPC protocol version), bound to its Tailscale address, only when
# it is at home (it travels), so the cluster must work without it. The model files
# live on the coordinator's SSD, with the NAS (/mnt/nas/models) as the library.
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
          pkgs.bash # /dev/tcp probe of each worker
          pkgs.iproute2 # `ss` for the status check
        ];
        text = ''
          workers=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.workers})
          rpc_port=${toString cfg.rpcPort}
          server_port=${toString cfg.serverPort}
          default_model=${lib.escapeShellArg cfg.model}
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
                Uses every answering RPC worker (an offline one is reported and left
                out) plus this machine's discrete GPU; what does not fit stays on
                this machine's CPU, read from the SSD. $slots agent slots share one
                context, sized by --fit to the free memory unless you pass -c N.
                Later args win over these defaults.
                Clients send the key in LLM_API_KEY_FILE as "Authorization: Bearer <key>".
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
            LLM_API_KEY_FILE
                The API key, made on the first serve if missing.
                Default: ~/.config/llm-cluster/api-key
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

          # The answering RPC servers as host:port,... llama.cpp skips an offline one
          # silently, so each is probed first and a missing one is reported.
          rpc_backends() {
            local w extra list=""
            local -a endpoints=() more=()
            for w in "''${workers[@]}"; do
              endpoints+=("$w:$rpc_port")
            done
            extra="''${LLM_EXTRA_RPC:-}"
            extra="''${extra// /}"
            if [ -n "$extra" ]; then
              IFS=',' read -r -a more <<<"$extra"
              endpoints+=("''${more[@]}")
            fi
            for w in "''${endpoints[@]}"; do
              [ -n "$w" ] || continue
              # shellcheck disable=SC2016 # $1 and $2 belong to the inner bash
              if timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "''${w%:*}" "''${w##*:}" 2>/dev/null; then
                list="''${list:+$list,}$w"
              else
                echo "llm-cluster: $w is not answering, so it is left out" >&2
              fi
            done
            printf '%s\n' "$list"
          }

          run_serve() {
            local list model key_file
            list=$(rpc_backends)
            if [ -z "$list" ]; then
              echo "llm-cluster: no RPC worker is answering. Run llm-cluster start-workers first." >&2
              exit 1
            fi
            # Every request needs this key (Authorization: Bearer <key>); only /health is open.
            key_file="''${LLM_API_KEY_FILE:-$HOME/.config/llm-cluster/api-key}"
            if [ ! -s "$key_file" ]; then
              (
                umask 077
                mkdir -p "$(dirname "$key_file")"
                head -c 32 /dev/urandom | base64 | tr -d '/+=\n' >"$key_file"
              )
              echo "llm-cluster: new API key in $key_file" >&2
            fi
            model="''${LLM_MODEL:-$default_model}"
            # No -dev: llama.cpp puts the RPC workers first (fewer network hops), then this
            # machine's discrete GPU, and leaves out the Arc iGPU. --fit sizes each share.
            exec llama-server \
              -m "$model" \
              --rpc "$list" \
              --api-key-file "$key_file" \
              --no-slots \
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
        vulkanDevice = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "[0-9a-f]{4}:[0-9a-f]{4}");
          default = null;
          example = "10de:1f91";
          description = ''
            Worker only: PCI vendor:device id of the one GPU rpc-server offers
            (MESA_VK_DEVICE_SELECT with `!`, which hides the others). Null offers
            every GPU. Independent of Vulkan's device order.
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
            environment = {
              LLAMA_CACHE = "/var/cache/llama-rpc";
              # A DynamicUser has no home, so keep compiled shaders here between starts.
              MESA_SHADER_CACHE_DIR = "/var/cache/llama-rpc/mesa";
            }
            // lib.optionalAttrs (cfg.vulkanDevice != null) {
              MESA_VK_DEVICE_SELECT = "${cfg.vulkanDevice}!";
            };
            serviceConfig = {
              ExecStart = "${llama}/bin/rpc-server --host 0.0.0.0 --port ${toString cfg.rpcPort} --cache";
              # Second guard next to the firewall: only loopback and the tailnet.
              IPAddressDeny = "any";
              IPAddressAllow = [
                "localhost"
                "100.64.0.0/10"
                "fd7a:115c:a1e0::/48"
              ];
              ProtectHome = true;
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
