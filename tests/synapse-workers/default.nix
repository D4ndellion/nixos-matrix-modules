{ pkgs, ... }:
{
  name = "matrix-synapse-workers";
  nodes = {
    server =
      {
        pkgs,
        nodes,
        ...
      }:
      {
        imports = [
          ../../synapse-module
        ];

        services.postgresql = {
          enable = true;
          initialScript = pkgs.writeText "synapse-init.sql" ''
            CREATE ROLE "matrix-synapse" WITH LOGIN PASSWORD 'synapse';
            CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
            TEMPLATE template0
            LC_COLLATE = "C"
            LC_CTYPE = "C";
          '';
        };

        services.matrix-synapse-next = {
          enable = true;

          workers.federationSenders = 1;
          workers.federationReceivers = 1;
          workers.initialSyncers = 1;
          workers.normalSyncers = 1;
          workers.eventPersisters = 1;
          workers.useUserDirectoryWorker = true;

          settings = {
            server_name = "example.com";
            database = {
              args.password = "synapse";
            };
          };
        };

        services.redis.servers."".enable = true;
      };
  };

  testScript = ''
    server.wait_for_unit("matrix-synapse.target");
  '';
}
