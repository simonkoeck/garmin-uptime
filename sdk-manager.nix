# Headless Connect IQ SDK Manager (community CLI by @lindell).
#
# Used to log in with a Garmin account and download the per-device definition
# files + fonts the SDK needs but does not ship:
#
#   connect-iq-sdk-manager login
#   connect-iq-sdk-manager device download --manifest manifest.xml
#
# Files land in ~/.Garmin/ConnectIQ where monkeyc and the simulator look for them.
{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule (finalAttrs: {
  pname = "connect-iq-sdk-manager-cli";
  version = "0.8.4";

  src = fetchFromGitHub {
    owner = "lindell";
    repo = "connect-iq-sdk-manager-cli";
    rev = "v${finalAttrs.version}";
    hash = "sha256-NEzy+lvBAvrapR6lq7k8b/3N4Os3Q7Wx4Vfv5qcjJiU=";
  };

  vendorHash = "sha256-hkYgYVOYx18GMF8RpiRBmNtwd+uhZn197LlpdwfqW8c=";

  ldflags = [ "-s" "-w" "-X main.version=${finalAttrs.version}" ];

  # The repo's `tests/` package is a live end-to-end story that needs network,
  # a writable $HOME, and the built binary on $PATH — none available in the
  # sandbox. Unit-testable logic lives in the internal packages.
  doCheck = false;

  meta = {
    description = "Headless Garmin Connect IQ SDK Manager (download SDKs, devices, fonts)";
    homepage = "https://github.com/lindell/connect-iq-sdk-manager-cli";
    license = lib.licenses.mit;
    mainProgram = "connect-iq-sdk-manager-cli";
    platforms = lib.platforms.linux;
  };
})
