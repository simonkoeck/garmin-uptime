{
  description = "Lumen — Garmin Connect IQ watch face, with a self-contained SDK dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The Connect IQ GUI simulator links the old webkit2gtk-4.0 / libsoup-2.4
    # stack, which only still exists here. The SDK package is built entirely from
    # this pin so its native library closure is internally consistent.
    nixpkgs-ciq.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, nixpkgs-ciq, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; # Connect IQ SDK is an unfree binary blob
        };
        pkgsCiq = import nixpkgs-ciq {
          inherit system;
          config.allowUnfree = true;
        };

        # Built from the 23.11 pin so the simulator's webkit2gtk-4.0 closure is consistent.
        connectiq = pkgsCiq.callPackage ./connectiq.nix {
          # In 23.11 this attribute still lives under the `gnome` set.
          adwaita-icon-theme = pkgsCiq.gnome.adwaita-icon-theme;
        };
        sdk-manager = pkgs.callPackage ./sdk-manager.nix { };
      in
      {
        packages = {
          inherit connectiq sdk-manager;
          default = connectiq;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            connectiq # monkeyc, monkeydo, connectiq (simulator launcher)
            sdk-manager # connect-iq-sdk-manager-cli — pull device defs/fonts
            pkgs.jdk17 # runtime for the Java tools
            pkgs.openssl # generate the developer key
            pkgs.unzip
            pkgs.watchexec # file watcher for ./dev.sh hot-reload
          ];

          shellHook = ''
            export CIQ_HOME="${connectiq}/opt/connectiq"
            echo "Connect IQ SDK ${connectiq.version} ready — 'monkeyc --version' to check."
            echo
            echo "First-time setup:"
            echo "  1. openssl genrsa -out developer_key.pem 4096 \\"
            echo "       && openssl pkcs8 -topk8 -inform PEM -outform DER \\"
            echo "          -in developer_key.pem -out developer_key -nocrypt"
            echo "  2. connect-iq-sdk-manager-cli login                                   # once"
            echo "  3. connect-iq-sdk-manager-cli agreement accept"
            echo "  4. connect-iq-sdk-manager-cli device download --manifest manifest.xml --include-fonts"
            echo "  5. monkeyc -d venu441mm -f monkey.jungle -o bin/Lumen.prg -y developer_key"
          '';
        };
      }
    );
}
