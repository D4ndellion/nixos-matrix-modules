{ pkgs, lib, config, ... }:
let
  cfg = config.services.matrix-synapse-next;

  matrix-lib = (import ../lib.nix { inherit lib; });

  resolveListeners = matrix-lib.resolveSystemdListeners cfg.socketDir;

  workerUpstreams = matrix-lib.mapWorkersToUpstreamsByType (
    lib.mapAttrs (_: worker: lib.recursiveUpdate worker {
      settings.worker_listeners = resolveListeners worker.settings.worker_listeners;
    }) cfg.workers.instances
  );
  listenerUpstreams = matrix-lib.mapListenersToUpstreamsByType (
    resolveListeners cfg.settings.listeners
  );
in
{
  config = lib.mkIf cfg.enableNginx {
    services.nginx.commonHttpConfig = ''
      # No since argument means its initialSync
      map $arg_since $synapse_unknown_sync {
        default synapse_normal_sync;
        ''' synapse_initial_sync;
      }

      map $uri $synapse_uri_group {
        # Sync requests
        ~^/_matrix/client/(r0|v3)/sync$ $synapse_unknown_sync;
        ~^/_matrix/client/(api/v1|r0|v3)/event$ synapse_normal_sync;
        ~^/_matrix/client/(api/v1|r0|v3)/initialSync$ synapse_initial_sync;
        ~^/_matrix/client/(api/v1|r0|v3)/rooms/[^/]+/initialSync$ synapse_initial_sync;

        # Federation requests
        ~^/_matrix/federation/v1/version$ synapse_federation;
        ~^/_matrix/federation/v1/event/ synapse_federation;
        ~^/_matrix/federation/v1/state/ synapse_federation;
        ~^/_matrix/federation/v1/state_ids/ synapse_federation;
        ~^/_matrix/federation/v1/backfill/ synapse_federation;
        ~^/_matrix/federation/v1/get_missing_events/ synapse_federation;
        ~^/_matrix/federation/v1/publicRooms synapse_federation;
        ~^/_matrix/federation/v1/query/ synapse_federation;
        ~^/_matrix/federation/v1/make_join/ synapse_federation;
        ~^/_matrix/federation/v1/make_leave/ synapse_federation;
        ~^/_matrix/federation/(v1|v2)/send_join/ synapse_federation;
        ~^/_matrix/federation/(v1|v2)/send_leave/ synapse_federation;
        ~^/_matrix/federation/v1/make_knock/ synapse_federation;
        ~^/_matrix/federation/v1/send_knock/ synapse_federation;
        ~^/_matrix/federation/(v1|v2)/invite/ synapse_federation;
        ~^/_matrix/federation/v1/event_auth/ synapse_federation;
        ~^/_matrix/federation/v1/timestamp_to_event/ synapse_federation;
        ~^/_matrix/federation/v1/exchange_third_party_invite/ synapse_federation;
        ~^/_matrix/federation/v1/user/devices/ synapse_federation;
        ~^/_matrix/key/v2/query synapse_federation;
        ~^/_matrix/federation/v1/hierarchy/ synapse_federation;

        # Inbound federation transaction request
        ~^/_matrix/federation/v1/send/ synapse_federation_transaction;

        # Client API requests
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/createRoom$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/publicRooms$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/joined_members$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/context/.*$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/members$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/state$ synapse_client_interaction;
        ~^/_matrix/client/v1/rooms/.*/hierarchy$ synapse_client_interaction;
        ~^/_matrix/client/(v1|unstable)/rooms/.*/relations/ synapse_client_interaction;
        ~^/_matrix/client/v1/rooms/.*/threads$ synapse_client_interaction;
        ~^/_matrix/client/unstable/im.nheko.summary/rooms/.*/summary$ synapse_client_interaction;
        ~^/_matrix/client/(r0|v3|unstable)/account/3pid$ synapse_client_interaction;
        ~^/_matrix/client/(r0|v3|unstable)/account/whoami$ synapse_client_interaction;
        ~^/_matrix/client/(r0|v3|unstable)/account/deactivate$ synapse_client_interaction;
        ~^/_matrix/client/(r0|v3)/delete_devices$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/devices(/|$) synapse_client_interaction;
        ~^/_matrix/client/versions$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/voip/turnServer$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/event/ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/joined_rooms$ synapse_client_interaction;
        ~^/_matrix/client/v1/rooms/.*/timestamp_to_event$ synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable/.*)/rooms/.*/aliases synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/search$ synapse_client_interaction;
        ~^/_matrix/client/(r0|v3|unstable)/user/.*/filter(/|$) synapse_client_interaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/directory/room/.*$ synapse_client_interaction;
        ~^/_matrix/client/(r0|v3|unstable)/capabilities$ synapse_client_interaction;
        ~^/_matrix/client/(r0|v3|unstable)/notifications$ synapse_client_interaction;

        # Encryption requests
        ~^/_matrix/client/(r0|v3|unstable)/keys/query$ synapse_client_encryption;
        ~^/_matrix/client/(r0|v3|unstable)/keys/changes$ synapse_client_encryption;
        ~^/_matrix/client/(r0|v3|unstable)/keys/claim$ synapse_client_encryption;
        ~^/_matrix/client/(r0|v3|unstable)/room_keys/ synapse_client_encryption;
        ~^/_matrix/client/(r0|v3|unstable)/keys/upload/ synapse_client_encryption;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/keys/device_signing/upload$ synapse_client_encryption;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/keys/signatures/upload$ synapse_client_encryption;

        # Registration/login requests
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/login$ synapse_client_login;
        ~^/_matrix/client/(r0|v3|unstable)/register$ synapse_client_login;
        ~^/_matrix/client/(r0|v3|unstable)/register/available$ synapse_client_login;
        ~^/_matrix/client/v1/register/m.login.registration_token/validity$ synapse_client_login;
        ~^/_matrix/client/(r0|v3|unstable)/password_policy$ synapse_client_login;

        # Event sending requests
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/redact synapse_client_transaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/send synapse_client_transaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/state/ synapse_client_transaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/(join|invite|leave|ban|unban|kick)$ synapse_client_transaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/join/ synapse_client_transaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/knock/ synapse_client_transaction;
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/profile/ synapse_client_transaction;

        # Account data requests
        ~^/_matrix/client/(r0|v3|unstable)/.*/tags synapse_client_data;
        ~^/_matrix/client/(r0|v3|unstable)/.*/account_data synapse_client_data;

        # Receipts requests
        ~^/_matrix/client/(r0|v3|unstable)/rooms/.*/receipt synapse_client_interaction;
        ~^/_matrix/client/(r0|v3|unstable)/rooms/.*/read_markers synapse_client_interaction;

        # Presence requests
        ~^/_matrix/client/(api/v1|r0|v3|unstable)/presence/ synapse_client_presence;

        # User directory search requests;
        ~^/_matrix/client/(r0|v3|unstable)/user_directory/search$ synapse_client_user-dir;
      }

      #Plugboard for url -> workers
      map $synapse_uri_group $synapse_backend {
        default synapse_master;

        synapse_initial_sync synapse_worker_initial_sync;
        synapse_normal_sync  synapse_worker_normal_sync;

        synapse_federation synapse_worker_federation;
        synapse_federation_transaction synapse_worker_federation;

        synapse_client_user-dir synapse_worker_user-dir;
      }

      # from https://github.com/tswfi/synapse/commit/b3704b936663cc692241e978dce4ac623276b1a6
      map $arg_access_token $accesstoken_from_urlparam {
        # Defaults to just passing back the whole accesstoken
        default   $arg_access_token;
        # Try to extract username part from accesstoken URL parameter
        "~syt_(?<username>.*?)_.*"           $username;
      }

      map $http_authorization $mxid_localpart {
        # Defaults to just passing back the whole accesstoken
        default                              $http_authorization;
        # Try to extract username part from accesstoken header
        "~Bearer syt_(?<username>.*?)_.*"    $username;
        # if no authorization-header exist, try mapper for URL parameter "access_token"
        ""                                   $accesstoken_from_urlparam;
      }
    '';

    services.nginx.upstreams.synapse_master.servers = let
      mainListeners = builtins.intersectAttrs
        (listenerUpstreams.client.http or { })
        (listenerUpstreams.federation.http or { });
    in
      assert lib.assertMsg (mainListeners != { })
        "No catch-all listener configured, or listener is not bound to an address";
        mainListeners;


    services.nginx.upstreams.synapse_worker_federation = {
      servers = workerUpstreams.fed-receiver.federation.http or config.services.nginx.upstreams.synapse_master.servers;
      extraConfig = ''
        ip_hash;
      '';
    };


    services.nginx.upstreams.synapse_worker_initial_sync = {
      servers = workerUpstreams.initial-sync.client.http or config.services.nginx.upstreams.synapse_master.servers;
      extraConfig = ''
        hash $mxid_localpart consistent;
      '';
    };


    services.nginx.upstreams.synapse_worker_normal_sync = {
      servers = workerUpstreams.normal-sync.client.http or config.services.nginx.upstreams.synapse_master.servers;
      extraConfig = ''
        hash $mxid_localpart consistent;
      '';
    };


    services.nginx.upstreams.synapse_worker_user-dir = {
      servers = workerUpstreams.user-dir.client.http or config.services.nginx.upstreams.synapse_master.servers;
    };

    services.nginx.virtualHosts."${cfg.public_baseurl}" = {
      enableACME = lib.mkDefault true;
      forceSSL = true;
      locations."/_matrix" = {
        proxyPass = "http://$synapse_backend";
        recommendedProxySettings = true;
        extraConfig = ''
          add_header X-debug-backend $synapse_backend;
          add_header X-debug-group $synapse_uri_group;
          client_max_body_size ${cfg.settings.max_upload_size};
          proxy_read_timeout 10m;
        '';
      };
      locations."~ ^/_matrix/client/(r0|v3)/sync$" = {
        proxyPass = "http://$synapse_backend";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_read_timeout 1h;
        '';
      };
      locations."~ ^/_matrix/client/(api/v1|r0|v3)/initialSync$" = {
        proxyPass = "http://synapse_worker_initial_sync";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_read_timeout 1h;
        '';
      };
      locations."~ ^/_matrix/client/(api/v1|r0|v3)/rooms/[^/]+/initialSync$" = {
        proxyPass = "http://synapse_worker_initial_sync";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_read_timeout 1h;
        '';
      };
      locations."/_synapse/client" = {
        proxyPass = "http://$synapse_backend";
        recommendedProxySettings = true;
      };
      locations."/.well-known/matrix" = {
        proxyPass = "http://$synapse_backend";
        recommendedProxySettings = true;
      };
    };
  };
}
