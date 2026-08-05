# Local web hosting

`local-web-hosting.nix` turns nginx into a declarative gateway for applications running on Bonhart. It provides:

- one memorable hostname, `http://bonhart.local`
- optional locally trusted HTTPS at `https://bonhart.local`
- one path per application
- automatic `/path` to `/path/` redirects
- a generated dashboard at `/`
- WebSocket forwarding when requested
- a single firewall opening for the gateway

## Register another server

Import `local-web-hosting.nix` once on the host, then add an application:

```nix
services.localWebHosting.applications.my-app = {
  title = "My App";
  description = "A short description for the dashboard.";
  path = "/my-app";
  upstream = "http://127.0.0.1:3000";
};
```

The application becomes available at `http://bonhart.local/my-app/`. By default nginx removes `/my-app/` before forwarding the request, so the upstream can continue serving from `/`.

If an application already understands its public prefix, retain it while proxying:

```nix
services.localWebHosting.applications.prefix-aware-app = {
  upstream = "http://127.0.0.1:8080";
  stripPrefix = false;
};
```

For development servers and other applications that use WebSockets:

```nix
services.localWebHosting.applications.live-app = {
  upstream = "http://127.0.0.1:5173";
  webSockets = true;
};
```

The upstream should listen on `127.0.0.1`, not `0.0.0.0`. nginx is the only service that needs to accept LAN connections.

## Applications that need their own port

Some applications assume they own `/` and use root-relative assets, so placing them below a path such as `/my-app/` would break them. Register those with a dedicated port:

```nix
services.localWebHosting.portApplications.my-app = {
  title = "My App";
  description = "An application that needs the URL root.";
  port = 3773;
  upstream = "http://127.0.0.1:3000";
  tls = true;
  webSockets = true;
};
```

This example becomes available at `https://bonhart.local:3773/` and is linked from the generated dashboard. With TLS enabled, a plain HTTP request to that port is redirected to HTTPS. `listenAddresses` can restrict nginx to one interface address when another process already owns the same port on Tailscale or another interface.

The gateway does not add authentication to a dedicated-port application. Its upstream authentication still applies, but otherwise every device on the permitted LAN can reach it; expose development tools only on a trusted network.

## HTTPS on the local network

Enable the gateway's private certificate authority and HTTPS listener:

```nix
services.localWebHosting.tls.enable = true;
```

Public certificate authorities cannot issue a certificate for the mDNS-only `.local` namespace. The gateway therefore creates a private CA and a one-year server certificate for the configured hostname. It renews the server certificate automatically during boot or activation when less than 30 days remain.

After activation, first open `http://bonhart.local` and download `local-ca.crt`. Install that public CA certificate once on each phone or computer that should trust the gateway; then use `https://bonhart.local`. On iOS, install the downloaded profile and also enable full trust under **Settings → General → About → Certificate Trust Settings**. Android exposes CA installation under its security or credential settings, depending on the vendor.

The CA private key stays root-only in `/var/lib/local-web-hosting/tls` and is never served. Before trusting the certificate on another device, its SHA-256 fingerprint can be checked locally with:

```bash
sudo openssl x509 \
  -in /var/lib/local-web-hosting/tls/local-web-hosting-ca.crt \
  -noout -sha256 -fingerprint
```

Plain HTTP remains enabled so a new device can retrieve the CA certificate. Applications are available over both schemes.

## Add the systemd service

The gateway only handles HTTP routing. Each repository should define its own systemd service so its runtime, working directory, writable paths, and restart policy remain explicit. `tv-remotes.nix` is the first complete example.

After adding an application, validate and activate with:

```bash
nix --extra-experimental-features 'nix-command flakes' flake check \
  --offline --no-build --no-write-lock-file "path:$PWD"
sudo nixos-rebuild switch --flake "path:$PWD#bonhart"
```
