# Garmin Connect IQ SDK (monkeyc compiler + device simulator), pinned to 9.2.0.
#
# Unfree prebuilt binary blob from Garmin. The `monkeyc` compiler and the other
# command-line tools are pure-Java wrappers; `simulator` and `shell` are native
# ELF binaries. The GUI simulator links the old webkit2gtk-4.0 / libsoup-2.4
# stack, which only still exists in nixpkgs 23.11 — so this whole derivation is
# meant to be built from a 23.11 pkgs set (see flake.nix) so the simulator's
# entire library closure is internally consistent (one glibc, one GTK, etc.).
#
# The SDK ships with NO device definitions. Use connect-iq-sdk-manager-cli to log
# in and download device files + fonts into ~/.Garmin/ConnectIQ before building.
{ lib
, stdenv
, fetchurl
, unzip
, autoPatchelfHook
, makeWrapper
, jdk17
, glib
, gtk3
, gdk-pixbuf
, pango
, cairo
, atk
, freetype
, fontconfig
, libpng
, libjpeg
, libjpeg8
, expat
, zlib
, libsecret
, libusb1
, systemdLibs
, libxkbcommon
, xorg
, webkitgtk
, libsoup
, glib-networking
, wrapGAppsHook
, librsvg
, gsettings-desktop-schemas
, adwaita-icon-theme
, hicolor-icon-theme
, shared-mime-info
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "connectiq";
  version = "9.2.0";

  src = fetchurl {
    url = "https://developer.garmin.com/downloads/connect-iq/sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip";
    hash = "sha256-SQfYRVtlHFoAqGXjZMxPGSHAVbknnHyGNMenpnc7VZM=";
  };

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook
  ];

  # We only want the GTK runtime env on the simulator wrapper, not on the
  # symlinked compiler tools — so wrap it ourselves in postFixup.
  dontWrapGApps = true;

  buildInputs = [
    stdenv.cc.cc.lib # libstdc++.so.6, libgcc_s.so.1
    glib
    gtk3
    gdk-pixbuf
    pango
    cairo
    atk
    freetype
    fontconfig
    libpng
    libjpeg # libjpeg.so.62 (gdk-pixbuf etc.)
    libjpeg8 # libjpeg.so.8 (the ABI Garmin's simulator was built against)
    expat
    zlib
    libsecret
    libusb1
    systemdLibs # libudev.so.1
    libxkbcommon
    xorg.libX11
    xorg.libXext
    xorg.libXxf86vm
    xorg.libSM
    xorg.libICE
    webkitgtk # libwebkit2gtk-4.0.so.37 + libjavascriptcoregtk-4.0.so.18
    libsoup # libsoup-2.4.so.1
    glib-networking # GIO TLS backend (libgiognutls) — needed for sim login/HTTPS
    # GTK runtime data the GUI simulator needs to actually render:
    librsvg # SVG pixbuf loader (symbolic icons)
    gsettings-desktop-schemas
    adwaita-icon-theme
    hicolor-icon-theme
    shared-mime-info
  ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir sdk
    unzip -q "$src" -d sdk
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/opt/connectiq" "$out/bin" "$out/libexec"
    cp -r sdk/* "$out/opt/connectiq/"
    chmod -R u+w "$out/opt/connectiq"

    # compiler-side tools (need the writable default.jungle mirror, see below)
    compilerTools="monkeyc monkeydo monkeydoc monkeygraph monkeym barrelbuild barreltest mdd era"

    for s in $compilerTools connectiq; do
      [ -f "$out/opt/connectiq/bin/$s" ] && chmod +x "$out/opt/connectiq/bin/$s"
    done

    # Shared launcher for the compiler tools. The compiler writes a generated
    # default.jungle next to monkeybrains.jar, but the store is read-only; so
    # mirror the SDK bin into a writable per-build cache (jar *copied* — a
    # symlinked jar gets canonicalised back to the store path — everything else
    # symlinked) and exec the real tool there. Tool identity comes from $0.
cat > "$out/libexec/ciq-launch" <<'CIQEOF'
#!${stdenv.shell}
tool=$(basename "$0")
export PATH="${jdk17}/bin:$PATH"
store="${placeholder "out"}/opt/connectiq/bin"
cache="''${XDG_CACHE_HOME:-$HOME/.cache}/connectiq/$(basename "${placeholder "out"}")/bin"
if [ ! -e "$cache/.ready" ]; then
  mkdir -p "$cache"
  for f in "$store"/*; do
    n=$(basename "$f")
    if [ "$n" = monkeybrains.jar ]; then
      cp -f "$f" "$cache/$n"
    else
      ln -sfn "$f" "$cache/$n"
    fi
  done
  touch "$cache/.ready"
fi
exec "$cache/$tool" "$@"
CIQEOF
    chmod +x "$out/libexec/ciq-launch"

    for tool in $compilerTools; do
      [ -f "$out/opt/connectiq/bin/$tool" ] && ln -s ../libexec/ciq-launch "$out/bin/$tool"
    done

    runHook postInstall
  '';

  # Wrap the GUI simulator with the full GTK runtime env that wrapGAppsHook
  # assembled (GDK_PIXBUF_MODULE_FILE, GSETTINGS_SCHEMA_DIR, XDG_DATA_DIRS for
  # icons/mime, GIO modules) — without this the window opens but renders blank.
  #
  # This is an old wxGTK app that doesn't render properly on native Wayland, so
  # pin it to X11/XWayland: set GDK_BACKEND=x11 AND unset WAYLAND_DISPLAY so GTK
  # can't half-initialise on Wayland and end up never mapping a window.
  # GIO_EXTRA_MODULES is pinned to the 23.11 glib-networking instead of being
  # inherited from the host: it must NOT pull in the host's newer-glib gio
  # modules (the 23.11 glib rejects them), but it DOES need glib-networking's
  # TLS backend (libgiognutls) or the simulator has no SSL and can't log in
  # ("TLS/SSL support not available"). The simulator runs from the read-only
  # store dir.
  postFixup = ''
    makeWrapper "$out/opt/connectiq/bin/connectiq" "$out/bin/connectiq" \
      --prefix PATH : ${lib.makeBinPath [ jdk17 ]} \
      --set GDK_BACKEND x11 \
      --unset WAYLAND_DISPLAY \
      --set GIO_EXTRA_MODULES "${glib-networking}/lib/gio/modules" \
      "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "Garmin Connect IQ SDK — monkeyc compiler and device simulator";
    homepage = "https://developer.garmin.com/connect-iq/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [
      binaryNativeCode
      binaryBytecode
    ];
    mainProgram = "monkeyc";
  };
})
