# Modified from https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/tests/matrix/synapse.nix

{ pkgs, lib, ... }:
let
  mailerCerts = import /${pkgs.path}/nixos/tests/common/acme/server/snakeoil-certs.nix;
  mailerDomain = mailerCerts.domain;

  registrationSharedSecret = "unsecure123";
  testUser = "alice";
  testPassword = "alicealice";
  testEmail = "alice@example.com";
in
{
  name = "matrix-synapse";
  nodes = {
    # Since 0.33.0, matrix-synapse doesn't allow underscores in server names
    server =
      {
        pkgs,
        nodes,
        config,
        ...
      }:
      let
        mailserverIP = nodes.mailserver.networking.primaryIPAddress;
      in
      {
        imports = [
          ../../synapse-module
        ];

        services.matrix-synapse-next = {
          enable = true;
          settings = {
            registration_shared_secret = registrationSharedSecret;
            server_name = "example.com";
            public_baseurl = "https://example.com";

            database = {
              args.password = "synapse";
            };

            redis = {
              enabled = true;
              host = "localhost";
              port = config.services.redis.servers.matrix-synapse.port;
            };

            email = {
              smtp_host = mailerDomain;
              smtp_port = 25;
              require_transport_security = true;
              notif_from = "matrix <matrix@${mailerDomain}>";
              app_name = "Matrix";
            };

            listeners = [
              {
                port = 8448;
                bind_addresses = [
                  "127.0.0.1"
                  "::1"
                ];
                type = "http";
                x_forwarded = false;
                resources = [
                  {
                    names = [
                      "client"
                    ];
                    compress = true;
                  }
                  {
                    names = [
                      "federation"
                    ];
                    compress = false;
                  }
                ];
              }
            ];
          };
        };

        services.postgresql = {
          enable = true;

          # The database name and user are configured by the following options:
          #   - services.matrix-synapse.database_name
          #   - services.matrix-synapse.database_user
          #
          # The values used here represent the default values of the module.
          initialScript = pkgs.writeText "synapse-init.sql" ''
            CREATE ROLE "matrix-synapse" WITH LOGIN PASSWORD 'synapse';
            CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
              TEMPLATE template0
              LC_COLLATE = "C"
              LC_CTYPE = "C";
          '';
        };

        services.redis.servers.matrix-synapse = {
          enable = true;
          port = 6380;
        };

        networking.extraHosts = ''
          ${mailserverIP} ${mailerDomain}
        '';

        security.pki.certificateFiles = [
          mailerCerts.ca.cert
        ];

        environment.systemPackages =
          let
            sendTestMailStarttls = pkgs.writeScriptBin "send-testmail-starttls" ''
              #!${pkgs.python3.interpreter}
              import smtplib
              import ssl

              ctx = ssl.create_default_context()

              with smtplib.SMTP('${mailerDomain}') as smtp:
                smtp.ehlo()
                smtp.starttls(context=ctx)
                smtp.ehlo()
                smtp.sendmail('matrix@${mailerDomain}', '${testEmail}', 'Subject: Test STARTTLS\n\nTest data.')
                smtp.quit()
            '';

            obtainTokenAndRegisterEmail =
              let
                # adding the email through the API is quite complicated as it involves more than one step and some
                # client-side calculation
                insertEmailForAlice = pkgs.writeText "alice-email.sql" ''
                  INSERT INTO user_threepids (user_id, medium, address, validated_at, added_at)
                  VALUES ('${testUser}@server', 'email', '${testEmail}', '1629149927271', '1629149927270');
                '';
              in
              pkgs.writeScriptBin "obtain-token-and-register-email" ''
                #!${pkgs.runtimeShell}
                set -o errexit
                set -o pipefail
                set -o nounset
                su postgres -c "psql -d matrix-synapse -f ${insertEmailForAlice}"
                curl --fail -XPOST -v 'http://localhost:8448/_matrix/client/r0/account/password/email/requestToken' --json '${builtins.toJSON {
                  email = testEmail;
                  client_secret = "foobar";
                  send_attempt = 1;
                }}'
              '';
          in
          [
            sendTestMailStarttls
            pkgs.matrix-synapse
            obtainTokenAndRegisterEmail
          ];
      };

    # test mail delivery
    mailserver = args: {
      security.pki.certificateFiles = [
        mailerCerts.ca.cert
      ];

      networking.firewall.enable = false;

      services.postfix = {
        enable = true;
        enableSubmission = true;

        # blackhole transport
        transport = "example.com discard:silently";

        settings.main = {
          myhostname = "${mailerDomain}";
          # open relay for subnet
          mynetworks_style = "subnet";
          debug_peer_level = "10";
          smtpd_relay_restrictions = [
            "permit_mynetworks"
            "reject_unauth_destination"
          ];

          # disable obsolete protocols, something old versions of twisted are still using
          smtpd_tls_protocols = "TLSv1.3, TLSv1.2, !TLSv1.1, !TLSv1, !SSLv2, !SSLv3";
          smtpd_tls_mandatory_protocols = "TLSv1.3, TLSv1.2, !TLSv1.1, !TLSv1, !SSLv2, !SSLv3";
          smtpd_tls_chain_files = [
            "${mailerCerts.${mailerDomain}.key}"
            "${mailerCerts.${mailerDomain}.cert}"
          ];
        };
      };
    };
  };

  testScript = ''
    start_all()
    mailserver.wait_for_unit("postfix.service")
    server.succeed("send-testmail-starttls")
    server.wait_for_unit("matrix-synapse.service")
    server.wait_until_succeeds(
        "curl --fail -L http://localhost:8448/"
    )
    server.wait_until_succeeds(
        "journalctl -u matrix-synapse.service | grep -q 'Connected to redis'"
    )
    server.require_unit_state("postgresql.target")
    server.succeed("register_new_matrix_user -u ${testUser} -p ${testPassword} -a -k ${registrationSharedSecret} 'http://localhost:8448/'")
    server.succeed("obtain-token-and-register-email")
  '';
}
