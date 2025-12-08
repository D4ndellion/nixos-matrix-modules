{ nixpkgs, lib, matrix-lib, writeText, ... }:
let
  nixosConfig = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../../module.nix
      {
        system.stateVersion = "25.11";
        boot.isContainer = true;
        services.matrix-synapse-next = {
          enable = true;
          enableNginx = true;

          workers = {
            enableMetrics = true;

            federationSenders = 3;
            federationReceivers = 3;
            initialSyncers = 1;
            normalSyncers = 1;
            eventPersisters = 1;
            useUserDirectoryWorker = true;

            instances.auto-fed-receiver1.settings.worker_listeners = [
              {
                bind_addresses = [
                  "127.0.0.2"
                ];
                port = 1337;
                resources = [
                  { compress = false;
                    names = [ "federation" ];
                  }
                ];
              }
            ];
          };

          settings.server_name = "example.com";
        };
      }
    ];
  };

  inherit (nixosConfig.config.services.matrix-synapse-next.workers) instances;
in
  writeText "matrix-synapse-next-nginx-pipeline-test.txt" ''
    ${(lib.generators.toPretty {}) instances}

    ====================================================

    ${(lib.generators.toPretty {}) (matrix-lib.mapWorkersToUpstreamsByType instances)}
  ''
