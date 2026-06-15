# Lumen — a minimal Garmin watch face

An extremely simple, modern watch face for Garmin Connect IQ devices.

```
                84%

              9 : 41          <- white digits, teal accent colon
              ─────
            MON 15 JUN

             • 1,234
```

* True-black background (great for AMOLED battery life + burn-in).
* Large thin time, one accent colour (teal `#00E5C8`).
* Quiet date, battery and step readouts. No seconds → negligible power draw.
* Pure code rendering, so it adapts to round / semi-round / rectangular screens.

## Project layout

```
manifest.xml                 app id, type=watchface, supported devices
monkey.jungle                build config
resources/
  strings/strings.xml        app name
  drawables/drawables.xml     launcher icon reference
  drawables/launcher_icon.png launcher icon
source/
  LumenApp.mc                entry point (AppBase)
  LumenView.mc               the watch face (WatchUi.WatchFace)
```

## Build & run

The SDK is packaged in a self-contained **Nix dev shell** in this folder — no
global install, nothing added to the system config.

```bash
nix develop          # drops you in a shell with monkeyc, the SDK manager + JDK
# or, with direnv:
direnv allow         # auto-loads the shell on cd (uses ./.envrc -> `use flake`)
```

What the flake provides (all built + cached locally already):

* `connectiq` — `monkeyc` compiler, `monkeydo`, `connectiq` simulator launcher
* `connect-iq-sdk-manager-cli` — headless device/font downloader
* `jdk17`, `openssl`, `unzip`

### First-time setup (inside the shell)

```bash
# 1. developer key (signs every build)
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem \
    -out developer_key -nocrypt

# 2. the SDK ships NO device definitions — log in once and pull them.
#    This needs a (free) Garmin account; same login you'll publish with.
connect-iq-sdk-manager-cli login
connect-iq-sdk-manager-cli agreement accept
connect-iq-sdk-manager-cli device download --manifest manifest.xml --include-fonts

# 3. build a .prg (Venu 4 41mm; use venu445mm for the 45mm)
monkeyc -d venu441mm -f monkey.jungle -o bin/Lumen.prg -y developer_key
```

Device ids for the Venu 4 are `venu441mm` (41 mm) and `venu445mm` (45 mm) —
both are in `manifest.xml`. To target other watches, add their ids there and
re-run the `device download` step.

To ship a `.iq` store package:
`monkeyc -e -f monkey.jungle -o bin/Lumen.iq -y developer_key`.

### Simulator note

`monkeyc` / `monkeydo` / on-device builds work fully. The **GUI simulator**
(`connectiq`) links the long-removed `webkit2gtk-4.0` stack, so it is left
unresolved in the package and will not launch on current nixpkgs — develop
against a real watch, or flash and test on device. (See `connectiq.nix` for the
exact ignored sonames if you want to wire in an old webkit pin later.)

### VS Code (optional)

The **Monkey C** extension also works — point its SDK path at the one in the
shell: run `echo $CIQ_HOME` inside `nix develop` and set that as the SDK
location.

## Customising

* **Accent colour** — change `ACCENT` in `source/LumenView.mc`.
* **Devices** — edit `<iq:products>` in `manifest.xml`, or use VS Code's
  *Monkey C: Edit Products* to pick from your installed device list.
* **12/24h** — follows the watch's own setting automatically.
