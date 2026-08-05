{ config, lib, pkgs, ... }:

let
  cfg = config.services.localWebHosting;

  tlsDirectory = "/var/lib/local-web-hosting/tls";
  caCertificate = "${tlsDirectory}/local-web-hosting-ca.crt";
  caPrivateKey = "${tlsDirectory}/local-web-hosting-ca.key";
  serverCertificate = "${tlsDirectory}/${cfg.hostName}.crt";
  serverPrivateKey = "${tlsDirectory}/${cfg.hostName}.key";

  applicationList = lib.mapAttrsToList (name: application: application // { inherit name; }) cfg.applications;
  applicationPaths = map (application: application.path) applicationList;
  portApplicationList = lib.mapAttrsToList (name: application: application // { inherit name; }) cfg.portApplications;
  portApplicationPorts = map (application: application.port) portApplicationList;
  dashboardEntryCount = builtins.length applicationList + builtins.length portApplicationList;

  proxyLocations = builtins.foldl' (
    locations: application:
    locations
    // {
      "= ${application.path}".return = "302 ${application.path}/";
      "${application.path}/" = {
        proxyPass = "${application.upstream}${lib.optionalString application.stripPrefix "/"}";
        proxyWebsockets = application.webSockets;
        recommendedProxySettings = true;
        extraConfig = application.extraConfig;
      };
    }
  ) { } applicationList;

  tlsLocations = lib.optionalAttrs cfg.tls.enable {
    "= ${cfg.tls.caDownloadPath}" = {
      alias = caCertificate;
      extraConfig = ''
        default_type application/x-x509-ca-cert;
        add_header Content-Disposition 'attachment; filename="local-web-hosting-ca.crt"';
      '';
    };
  };

  pathDashboardCards = lib.concatMapStrings (application: ''
    <a class="app" href="${application.path}/">
      <span class="name">${lib.escapeXML application.title}</span>
      <span class="path">${application.path}/</span>
      <span class="description">${lib.escapeXML application.description}</span>
    </a>
  '') applicationList;

  portDashboardCards = lib.concatMapStrings (application:
    let
      publicUrl = "${if application.tls then "https" else "http"}://${cfg.hostName}:${toString application.port}/";
    in
    ''
      <a class="app" href="${lib.escapeXML publicUrl}">
        <span class="name">${lib.escapeXML application.title}</span>
        <span class="path">:${toString application.port}</span>
        <span class="description">${lib.escapeXML application.description}</span>
      </a>
    ''
  ) portApplicationList;

  dashboardCards = pathDashboardCards + portDashboardCards;

  portApplicationVirtualHosts = builtins.listToAttrs (map (application: {
    name = "${cfg.hostName}-${application.name}-${toString application.port}";
    value = {
      serverName = cfg.hostName;
      listen = map (address: {
        addr = address;
        port = application.port;
        ssl = application.tls;
      }) application.listenAddresses;
      locations."/" = {
        proxyPass = application.upstream;
        proxyWebsockets = application.webSockets;
        recommendedProxySettings = true;
        extraConfig = application.extraConfig;
      };
      extraConfig = lib.optionalString application.tls ''
        # nginx uses status 497 when plain HTTP reaches an HTTPS listener.
        error_page 497 =301 https://$host:$server_port$request_uri;
      '';
    } // lib.optionalAttrs application.tls {
      # Explicit listen entries select the dedicated port; addSSL makes the
      # NixOS module emit the shared gateway certificate directives.
      addSSL = true;
      sslCertificate = serverCertificate;
      sslCertificateKey = serverPrivateKey;
    };
  }) portApplicationList);

  dashboardRoot = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="theme-color" content="#0b0c0f">
        <title>${lib.escapeXML cfg.title}</title>
        <style>
          :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #0b0c0f; color: #f4f5f7; }
          * { box-sizing: border-box; }
          body { margin: 0; min-height: 100vh; background: radial-gradient(circle at 50% -20%, #263044 0, transparent 36rem), #0b0c0f; }
          main { width: min(64rem, calc(100% - 2rem)); margin: 0 auto; padding: clamp(3rem, 10vw, 7rem) 0; }
          .eyebrow { margin: 0 0 .5rem; color: #8f98a7; font-size: .72rem; font-weight: 800; letter-spacing: .2em; text-transform: uppercase; }
          h1 { margin: 0; font-size: clamp(2.6rem, 9vw, 5.5rem); letter-spacing: -.055em; }
          .subtitle { max-width: 42rem; margin: 1rem 0 2.5rem; color: #aeb5c0; font-size: 1.05rem; line-height: 1.6; }
          .tls { max-width: 42rem; margin: -1.4rem 0 2.5rem; color: #8f98a7; font-size: .86rem; line-height: 1.5; }
          .tls a { color: #91d7ff; }
          .apps { display: grid; grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr)); gap: 1rem; }
          .app { display: grid; gap: .6rem; min-height: 11rem; padding: 1.4rem; border: 1px solid #303641; border-radius: 1.4rem; background: rgba(24, 27, 33, .86); color: inherit; text-decoration: none; transition: transform .15s ease, border-color .15s ease, background .15s ease; }
          .app:hover { transform: translateY(-2px); border-color: #596477; background: #20242c; }
          .name { font-size: 1.35rem; font-weight: 750; }
          .path { width: max-content; padding: .3rem .55rem; border-radius: .5rem; background: #101217; color: #91d7ff; font-family: ui-monospace, monospace; font-size: .78rem; }
          .description { align-self: end; color: #aeb5c0; line-height: 1.45; }
          footer { margin-top: 2rem; color: #727b89; font-size: .78rem; }
        </style>
      </head>
      <body>
        <main>
          <p class="eyebrow">${lib.escapeXML config.networking.hostName} · local network</p>
          <h1>${lib.escapeXML cfg.title}</h1>
          <p class="subtitle">One address for the services hosted on this machine.</p>
          ${lib.optionalString cfg.tls.enable ''
            <p class="tls">HTTPS is available after this device trusts the <a href="${cfg.tls.caDownloadPath}">local CA certificate</a>.</p>
          ''}
          <section class="apps" aria-label="Local applications">
            ${dashboardCards}
          </section>
          <footer>${toString dashboardEntryCount} application${lib.optionalString (dashboardEntryCount != 1) "s"} registered</footer>
        </main>
      </body>
    </html>
  '';
in
{
  options.services.localWebHosting = {
    enable = lib.mkEnableOption "the local nginx application gateway";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}.local";
      defaultText = lib.literalExpression ''"''${config.networking.hostName}.local"'';
      description = "mDNS hostname served by the local application gateway.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "LAN-facing HTTP port used by nginx.";
    };

    tls = {
      enable = lib.mkEnableOption "locally trusted HTTPS for the application gateway";

      port = lib.mkOption {
        type = lib.types.port;
        default = 443;
        description = "LAN-facing HTTPS port used by nginx.";
      };

      caDownloadPath = lib.mkOption {
        type = lib.types.strMatching "^/[A-Za-z0-9][A-Za-z0-9._-]*$";
        default = "/local-ca.crt";
        description = "HTTP path from which clients can download the public local CA certificate.";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the gateway port in the NixOS firewall.";
    };

    title = lib.mkOption {
      type = lib.types.str;
      default = "Local Services";
      description = "Title shown on the generated local application dashboard.";
    };

    applications = lib.mkOption {
      default = { };
      description = "Applications exposed below the local gateway hostname.";
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          title = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Human-readable application name shown on the dashboard.";
          };

          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Short application description shown on the dashboard.";
          };

          path = lib.mkOption {
            type = lib.types.strMatching "^/[A-Za-z0-9]([A-Za-z0-9/_-]*[A-Za-z0-9_-])?$";
            default = "/${name}";
            description = "Public URL path without a trailing slash.";
          };

          upstream = lib.mkOption {
            type = lib.types.strMatching "^https?://[^/]+$";
            example = "http://127.0.0.1:3000";
            description = "Loopback HTTP server receiving proxied requests, without a trailing slash.";
          };

          stripPrefix = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Strip the public path prefix before forwarding to the upstream server.";
          };

          webSockets = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable WebSocket upgrade forwarding for this application.";
          };

          extraConfig = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Additional nginx directives for this application's location.";
          };
        };
      }));
    };

    portApplications = lib.mkOption {
      default = { };
      description = "Applications exposed on dedicated gateway ports instead of URL paths.";
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          title = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Human-readable application name shown on the dashboard.";
          };

          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Short application description shown on the dashboard.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            description = "Dedicated LAN-facing port used by nginx for this application.";
          };

          listenAddresses = lib.mkOption {
            type = lib.types.nonEmptyListOf lib.types.str;
            default = [ "0.0.0.0" "[::]" ];
            description = "Addresses on which nginx listens for this application.";
          };

          upstream = lib.mkOption {
            type = lib.types.strMatching "^https?://[^/]+$";
            example = "http://127.0.0.1:3000";
            description = "HTTP server receiving the unmodified request path.";
          };

          tls = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Terminate HTTPS with the local gateway certificate.";
          };

          webSockets = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable WebSocket upgrade forwarding for this application.";
          };

          extraConfig = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Additional nginx directives for the dedicated proxy location.";
          };
        };
      }));
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.applications != { };
        message = "services.localWebHosting requires at least one registered application";
      }
      {
        assertion = lib.all (application: !(lib.hasInfix "//" application.path) && !(lib.hasInfix ".." application.path)) applicationList;
        message = "local web application paths cannot contain // or ..";
      }
      {
        assertion = builtins.length applicationPaths == builtins.length (lib.unique applicationPaths);
        message = "local web applications must use unique public paths";
      }
      {
        assertion = !cfg.tls.enable || cfg.tls.port != cfg.port;
        message = "services.localWebHosting HTTP and HTTPS ports must be different";
      }
      {
        assertion = builtins.length portApplicationPorts == builtins.length (lib.unique portApplicationPorts);
        message = "local web dedicated-port applications must use unique ports";
      }
      {
        assertion = lib.all (application: application.port != cfg.port && (!cfg.tls.enable || application.port != cfg.tls.port)) portApplicationList;
        message = "local web dedicated application ports cannot reuse the main HTTP or HTTPS port";
      }
      {
        assertion = lib.all (application: !application.tls || cfg.tls.enable) portApplicationList;
        message = "local web dedicated applications require services.localWebHosting.tls.enable for TLS";
      }
    ];

    systemd.services.local-web-hosting-tls = lib.mkIf cfg.tls.enable {
      description = "Issue the local web hosting TLS certificate";
      requiredBy = [ "nginx.service" ];
      before = [ "nginx.service" ];
      path = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.openssl
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "local-web-hosting";
        StateDirectoryMode = "0755";
        UMask = "0077";
      };

      script = ''
        set -eu

        tls_dir=${lib.escapeShellArg tlsDirectory}
        tls_host_name=${lib.escapeShellArg cfg.hostName}
        tls_short_name=${lib.escapeShellArg config.networking.hostName}
        ca_certificate=${lib.escapeShellArg caCertificate}
        ca_private_key=${lib.escapeShellArg caPrivateKey}
        server_certificate=${lib.escapeShellArg serverCertificate}
        server_private_key=${lib.escapeShellArg serverPrivateKey}

        install -d -m 0755 -o root -g root "$tls_dir"
        tls_work_dir="$(mktemp -d "$tls_dir/.issue.XXXXXX")"
        cleanup_tls_work_dir() {
          rm -rf -- "$tls_work_dir"
        }
        trap cleanup_tls_work_dir EXIT INT TERM

        ca_reissued=false
        if ! test -s "$ca_certificate" \
          || ! test -s "$ca_private_key" \
          || ! openssl x509 -checkend 2592000 -noout -in "$ca_certificate"; then
          openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 \
            -subj "/CN=$tls_short_name Local Services CA" \
            -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" \
            -keyout "$tls_work_dir/ca.key" \
            -out "$tls_work_dir/ca.crt"
          install -m 0600 -o root -g root "$tls_work_dir/ca.key" "$ca_private_key"
          install -m 0644 -o root -g root "$tls_work_dir/ca.crt" "$ca_certificate"
          ca_reissued=true
        fi

        if test "$ca_reissued" = true \
          || ! test -s "$server_certificate" \
          || ! test -s "$server_private_key" \
          || ! openssl x509 -checkend 2592000 -noout -in "$server_certificate" \
          || ! openssl x509 -checkhost "$tls_host_name" -noout -in "$server_certificate" \
          || ! openssl verify -CAfile "$ca_certificate" "$server_certificate"; then
          openssl req -new -newkey rsa:3072 -nodes -sha256 \
            -subj "/CN=$tls_host_name" \
            -keyout "$tls_work_dir/server.key" \
            -out "$tls_work_dir/server.csr"
          printf '%s\n' \
            'basicConstraints=critical,CA:FALSE' \
            'keyUsage=critical,digitalSignature,keyEncipherment' \
            'extendedKeyUsage=serverAuth' \
            'subjectKeyIdentifier=hash' \
            'authorityKeyIdentifier=keyid,issuer' \
            "subjectAltName=DNS:$tls_host_name,DNS:$tls_short_name" \
            > "$tls_work_dir/server.ext"
          openssl x509 -req -sha256 -days 365 \
            -in "$tls_work_dir/server.csr" \
            -CA "$ca_certificate" \
            -CAkey "$ca_private_key" \
            -CAcreateserial \
            -CAserial "$tls_dir/local-web-hosting-ca.srl" \
            -extfile "$tls_work_dir/server.ext" \
            -out "$tls_work_dir/server.crt"
          install -m 0640 -o root -g nginx "$tls_work_dir/server.key" "$server_private_key"
          install -m 0644 -o root -g root "$tls_work_dir/server.crt" "$server_certificate"
        fi
      '';
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;

      virtualHosts = {
        ${cfg.hostName} = {
          default = true;
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.port;
            }
            {
              addr = "[::]";
              port = cfg.port;
            }
          ] ++ lib.optionals cfg.tls.enable [
            {
              addr = "0.0.0.0";
              port = cfg.tls.port;
              ssl = true;
            }
            {
              addr = "[::]";
              port = cfg.tls.port;
              ssl = true;
            }
          ];
          locations = proxyLocations // tlsLocations // {
            "/" = {
              root = dashboardRoot;
              index = "index.html";
              tryFiles = "$uri $uri/ =404";
            };
          };
        } // lib.optionalAttrs cfg.tls.enable {
          # The explicit listen list controls the ports, while addSSL tells the
          # NixOS nginx module to emit the certificate directives.
          addSSL = true;
          sslCertificate = serverCertificate;
          sslCertificateKey = serverPrivateKey;
        };
      } // portApplicationVirtualHosts;
    };

    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall (
      lib.unique (
        [ cfg.port ]
        ++ lib.optionals cfg.tls.enable [ cfg.tls.port ]
        ++ portApplicationPorts
      )
    );
  };
}
