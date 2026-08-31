# crates.io's download API (https://crates.io/api/v1/crates/<name>/<version>/download)
# answers 403 from some networks and CDN edges, which fails every Rust build at
# the point where it fetches its vendored registry crates. The content-addressed
# host static.crates.io serves byte-identical tarballs and is not affected.
#
# fetchurl tries `urls` in order, so listing the static host first sidesteps the
# blocked endpoint while keeping the original URL as a fallback for the day the
# block lifts. This is safe to apply unconditionally: a fixed-output derivation's
# store path is derived only from (name, hash, hashMode), never from `urls`, so
# adding a mirror changes no output path and triggers no rebuild.
#
# Scope: this reaches every crate fetched through *this* configuration's nixpkgs.
# It cannot reach a flake that ships its own nixpkgs and that we consume through
# its `packages.<system>` output (codex-desktop-linux is one), because that
# package set is evaluated with its own overlays. Use
# scripts/seed-crates-from-static.sh for those; it works below the flake
# boundary, on the store itself.
final: prev:

let
  inherit (builtins)
    elemAt
    filter
    isAttrs
    map
    match
    removeAttrs
    ;

  staticMirror =
    url:
    let
      parts = match "https://crates\\.io/api/v1/crates/([^/]+)/([^/]+)/download" url;
    in
    if parts == null then
      null
    else
      let
        name = elemAt parts 0;
        version = elemAt parts 1;
      in
      "https://static.crates.io/crates/${name}/${name}-${version}.crate";

  withMirrors =
    args:
    let
      urls = args.urls or (if args ? url then [ args.url ] else [ ]);
      mirrors = filter (url: url != null) (map staticMirror urls);
    in
    if mirrors == [ ] then
      args
    else
      removeAttrs args [ "url" ] // { urls = mirrors ++ urls; };
in

{
  fetchurl = args: prev.fetchurl (if isAttrs args then withMirrors args else args);
}
