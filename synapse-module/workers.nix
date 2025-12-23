{ matrix-synapse-common-config,
  matrix-lib,
  wrapped,
  throw',
  format
}:
{ pkgs, lib, config, ... }: let

  cfg = config.services.matrix-synapse-next;
  wcfg = config.services.matrix-synapse-next.workers;

  # Used to generate proper defaultTexts.
  cfgText = "config.services.matrix-synapse-next";
  wcfgText = "config.services.matrix-synapse-next.workers";

  inherit (lib) types mkOption mkEnableOption mkIf mkMerge literalExpression;

  mkWorkerCountOption = workerType: mkOption {
    type = types.ints.unsigned;
    description = "How many automatically configured ${workerType} workers to set up";
    default = 0;
  };

  genAttrs' = items: f: g: builtins.listToAttrs (map (i: lib.nameValuePair (f i) (g i)) items);

  mainReplicationListener = matrix-lib.firstListenerOfType "replication" cfg.settings.listeners;
in {
  # See https://github.com/matrix-org/synapse/blob/develop/docs/workers.md for more info
  options.services.matrix-synapse-next.workers = let
    workerInstanceType = types.submodule ({ config, ... }: {
      options = {
        isAuto = mkOption {
          type = types.bool;
          internal = true;
          default = false;
        };

        index = mkOption {
          internal = true;
          type = types.ints.positive;
        };

        # The custom string type here is mainly for the name to use
        # for the metrics of custom worker types
        type = mkOption {
          type = types.str;
          # TODO: add description and possibly default value?
        };

        settings = mkOption {
          type = workerSettingsType config;
          default = { };
        };
      };
    });

    workerSettingsType = instanceCfg: types.submodule {
      freeformType = format.type;
      
      options = {
        worker_app = mkOption {
          type = types.enum [
            "synapse.app.generic_worker"
            "synapse.app.appservice"
            "synapse.app.media_repository"
            "synapse.app.user_dir"
          ];
          description = "The type of worker application";
          default = "synapse.app.generic_worker";
        };

        worker_listeners = mkOption {
          type = types.listOf (workerListenerType instanceCfg);
          description = "Listener configuration for the worker, similar to the main synapse listener";
          default = [ ];
        };
      };
    };

    workerListenerType = instanceCfg: types.submodule {
      options = {
        type = mkOption {
          type = types.enum [ "http" "metrics" ];
          description = "The type of the listener";
          default = "http";
        };

        port = mkOption {
          type = with types; nullOr port;
          default = null;
          description = "The TCP port to bind to";
        };

        path = mkOption {
          type = with types; nullOr path;
          default = null;
          description = "The UNIX socket to bind to";
        };

        bind_addresses = mkOption {
          type = with types; listOf str;
          description = "A list of local addresses to listen on";
          default = [ wcfg.defaultListenerAddress ];
          defaultText = literalExpression "[ ${wcfgText}.defaultListenerAddress ]";
        };

        tls = mkOption {
          type = types.bool;
          description = ''
            Whether to enable TLS for this listener.
            Will use the TLS key/cert specified in tls_private_key_path / tls_certificate_path.
          '';
          default = false;
          example = true;
        };

        x_forwarded = mkOption {
          type = types.bool;
          description = ''
            Whether to use the X-Forwarded-For HTTP header as the client IP.

            This option is only valid for an 'http' listener.
            It is useful when Synapse is running behind a reverse-proxy.
          '';
          default = true;
          example = false;
        };

        resources = let
          typeToResources = t: {
            "fed-receiver"  = [ "federation" ];
            "fed-sender"    = [ ];
            "initial-sync"  = [ "client" ];
            "normal-sync"   = [ "client" ];
            "event-persist" = [ "replication" ];
            "user-dir"      = [ "client" ];
          }.${t};
        in mkOption {
          type = types.listOf (types.submodule {
            options = {
              names = mkOption {
                type = with types; listOf (enum [
                  "client"
                  "consent"
                  "federation"
                  "keys"
                  "media"
                  "metrics"
                  "openid"
                  "replication"
                  "static"
                  "webclient"
                ]);
                description = "A list of resources to host on this port";
                default = lib.optionals instanceCfg.isAuto (typeToResources instanceCfg.type);
                defaultText = ''
                  If the worker is generated from other config, the resource type will
                  be determined automatically.
                '';
              };

              compress = mkEnableOption "HTTP compression for this resource";
            };
          });
          default = [{ }];
        };
      };
    };
  in {
    mainReplicationHost = mkOption {
      type = with types; nullOr str;
      default = let
        host = (matrix-lib.connectionInfo mainReplicationListener).host;
      in
        # To avoid connecting to 0.0.0.0 and so on
        if builtins.elem host [ "0.0.0.0" "::" ]
          then "127.0.0.1"
          else host;
      # TODO: add defaultText
      description = "Host of the main synapse instance's replication listener";
    };

    mainReplicationPort = mkOption {
      type = with types; nullOr port;
      default = mainReplicationListener.port;
      # TODO: add defaultText
      description = "Port for the main synapse instance's replication listener";
    };

    mainReplicationPath = mkOption {
      type = with types; nullOr path;
      default = mainReplicationListener.path;
      # TODO: add defaultText
      description = "Path to the UNIX socket of the main synapse instance's replication listener";
    };

    defaultListenerAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "The default listener address for the worker";
    };

    workersUsePath = mkOption {
      type = types.bool;
      description = "Whether to enable UNIX sockets for all automatically generated workers";
      default = true;
      example = false;
    };

    workerStartingPort = mkOption {
      type = types.port;
      description = "What port should the automatically configured workers start enumerating from";
      default = 8083;
    };

    enableMetrics = mkOption {
      type = types.bool;
      default = cfg.settings.enable_metrics;
      defaultText = literalExpression "${cfgText}.settings.enable_metrics";
      # TODO: add description
    };

    metricsStartingPort = mkOption {
      type = types.port;
      default = 18083;
      # TODO: add description
    };

    federationSenders = mkWorkerCountOption "federation-sender";
    federationReceivers = mkWorkerCountOption "federation-reciever";
    initialSyncers = mkWorkerCountOption "initial-syncer";
    normalSyncers = mkWorkerCountOption "sync";
    eventPersisters = mkWorkerCountOption "event-persister";

    useUserDirectoryWorker = mkEnableOption "user directory worker";

    instances = mkOption {
      type = types.attrsOf workerInstanceType;
      default = { };
      description = "Worker configuration";
      example = {
        "federation_sender1" = {
          settings = {
            worker_name = "federation_sender1";
            worker_app = "synapse.app.generic_worker";

            worker_replication_host = "127.0.0.1";
            worker_replication_http_port = 9093;
            worker_listeners = [ ];
          };
        };
      };
    };
  };

  config = {
    assertions = [ ]
      ++ (lib.concatMap (worker:
        (map (l: {
          assertion = l.path == null -> (l.bind_addresses != [ ] && l.port != null);
          message = "At least one worker listener is missing either a socket path or a bind_address + port to listen on";
        }) worker.settings.worker_listeners)
      ) (lib.attrValues wcfg.instances));

    services.matrix-synapse-next.settings = {
      federation_sender_instances =
        lib.genList (i: "auto-fed-sender${toString (i + 1)}") wcfg.federationSenders;

      instance_map = (lib.mkIf (cfg.workers.instances != { }) ({
        main = if wcfg.mainReplicationPath != null then {
          path = wcfg.mainReplicationPath;
        } else {
          host = wcfg.mainReplicationHost;
          port = wcfg.mainReplicationPort;
        };
      } // genAttrs' (lib.lists.range 1 wcfg.eventPersisters)
        (i: "auto-event-persist${toString i}")
        (i: let
          wRL = matrix-lib.firstListenerOfType "replication" wcfg.instances."auto-event-persist${toString i}".settings.worker_listeners;
        in if wRL.path != null then {
          inherit (wRL) path;
        } else matrix-lib.connectionInfo wRL)));

      stream_writers.events =
        mkIf (wcfg.eventPersisters > 0)
        (lib.genList (i: "auto-event-persist${toString (i + 1)}") wcfg.eventPersisters); 

      update_user_directory_from_worker =
        mkIf wcfg.useUserDirectoryWorker "auto-user-dir";
    };

    services.matrix-synapse-next.workers.instances = let
      sum = lib.foldl lib.add 0;
      workerListenersWithMetrics = portOffset: name:
        [(if wcfg.workersUsePath
          then {
            path = "${cfg.socketDir}/matrix-synapse-worker-${name}.sock";
          }
          else {
            port = wcfg.workerStartingPort + portOffset - 1;
          }
        )]
        ++ lib.optional wcfg.enableMetrics {
          port = wcfg.metricsStartingPort + portOffset;
          resources = [ { names = [ "metrics" ]; } ];
        };

      makeWorkerInstances = {
        type,
        numberOfWorkers,
        portOffset ? 0,
        nameFn ? i: "auto-${type}${toString i}",
        workerListenerFn ? i: name: workerListenersWithMetrics (portOffset + i) name
      }: genAttrs'
        (lib.lists.range 1 numberOfWorkers)
        nameFn
        (i: {
          isAuto = true;
          inherit type;
          index = i;
          settings.worker_listeners = workerListenerFn i (nameFn i);
        });

      workerInstances = {
        "fed-sender" = wcfg.federationSenders;
        "fed-receiver" = wcfg.federationReceivers;
        "initial-sync" = wcfg.initialSyncers;
        "normal-sync" = wcfg.normalSyncers;
        "event-persist" = wcfg.eventPersisters;
      } // (lib.optionalAttrs wcfg.useUserDirectoryWorker {
        "user-dir" = {
          numberOfWorkers = 1;
          nameFn = _: "auto-user-dir";
        };
      });

      coerceWorker = { name, value }: if builtins.isInt value then {
        type = name;
        numberOfWorkers = value;
      } else { type = name; } // value;

      # Like foldl, but keeps all intermediate values
      #
      # (b -> a -> b) -> b -> [a] -> [b]
      scanl = f: x1: list: let
        x2 = lib.head list;
        x1' = f x1 x2;
      in if list == [] then [] else [x1'] ++ (scanl f x1' (lib.tail list));

      f = { portOffset, numberOfWorkers, ... }: x: x // { portOffset = portOffset + numberOfWorkers; };
      init = { portOffset = 0; numberOfWorkers = 0; };
    in lib.pipe workerInstances [
      (lib.mapAttrsToList lib.nameValuePair)
      (map coerceWorker)
      (scanl f init)
      (map makeWorkerInstances)
      mkMerge
    ];

    systemd.services = let
      workerList = lib.mapAttrsToList lib.nameValuePair wcfg.instances;
      workerConfig = worker:
        format.generate "matrix-synapse-worker-${worker.name}-config.yaml"
        (worker.value.settings // {
          worker_name = worker.name;
          worker_listeners =
            map (lib.filterAttrsRecursive (_: v: v != null)) worker.value.settings.worker_listeners;
        });
    in builtins.listToAttrs (lib.flip map workerList (worker: {
      name = "matrix-synapse-worker-${worker.name}";
      value = {
        description = "Synapse Matrix Worker";
        partOf = [ "matrix-synapse.target" ];
        wantedBy = [ "matrix-synapse.target" ];
        after = [ "matrix-synapse.service" ];
        requires = [ "matrix-synapse.service" ];

        environment = lib.optionalAttrs cfg.withJemalloc {
          LD_PRELOAD = "${pkgs.jemalloc}/lib/libjemalloc.so";
          PYTHONMALLOC = "malloc";
        };

        serviceConfig = {
          Type = "notify";
          User = "matrix-synapse";
          Group = "matrix-synapse";
          Slice = "system-matrix-synapse.slice";
          WorkingDirectory = cfg.dataDir;
          RuntimeDirectory = "matrix-synapse";
          StateDirectory = "matrix-synapse";
          ExecStartPre = pkgs.writers.writeBash "wait-for-synapse" ''
            # From https://md.darmstadt.ccc.de/synapse-at-work
            while ! systemctl is-active -q matrix-synapse.service; do
                sleep 1
            done
          '';
          ExecStart = let
            flags = lib.cli.toCommandLineShellGNU {} {
              config-path = [ matrix-synapse-common-config (workerConfig worker) ] ++ cfg.extraConfigFiles;
              keys-directory = cfg.dataDir;
            };
          in "${wrapped}/bin/synapse_worker ${flags}";

          AmbientCapabilities = [ "" ];
          CapabilityBoundingSet = [ "" ];
          LockPersonality = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          PrivateUsers = true;
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          ReadWritePaths = [
            cfg.dataDir
            cfg.settings.media_store_path
          ]
          ++ (map (listener: dirOf listener.path) (
            lib.filter (listener: listener.path != null) cfg.settings.listeners
          ));
          RemoveIPC = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SocketBindAllow = lib.pipe worker.value.settings.worker_listeners [
            (map (lib.filterAttrsRecursive (_: v: v != null)))
            (lib.catAttrs "port")
          ];
          SocketBindDeny = "any";
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@resources"
            "~@privileged"
          ];
          UMask = "0027";
        };
      };
    }));
  };
}
