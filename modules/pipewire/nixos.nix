{ config, lib, ... }:
let
  cfg = config.modules.pipewire;
  deviceRule = device: {
    matches = [ { "device.name" = device.deviceName; } ];
    actions."update-props" = lib.filterAttrs (_: value: value != null) {
      "api.alsa.disable-batch" = device.disableBatch;
      "api.alsa.disable-mmap" = device.disableMmap;
      "api.alsa.period-num" = device.periodNum;
      "api.alsa.period-size" = device.periodSize;
      "api.alsa.headroom" = device.headroom;
    };
  };
  loopbackModule = loopback: {
    name = "libpipewire-module-loopback";
    args = {
      "node.description" = loopback.description;
      "capture.props" = {
        "target.object" = loopback.source;
      }
      // lib.optionalAttrs loopback.capturePassive { "node.passive" = true; };
      "playback.props" =
        lib.optionalAttrs (loopback.target != null) { "target.object" = loopback.target; }
        // lib.optionalAttrs (loopback.virtualSource != null) {
          "node.name" = loopback.virtualSource.name;
          "media.class" = "Audio/Source";
          "audio.position" = loopback.virtualSource.channels;
        };
    }
    // lib.optionalAttrs (loopback.name != null) { "node.name" = loopback.name; };
  };
in
{
  config = lib.mkIf cfg.enable {
    assertions = map (loopback: {
      assertion = loopback.target == null || loopback.virtualSource == null;
      message = "modules.pipewire.loopbacks: '${loopback.description}' cannot set both target and virtualSource.";
    }) cfg.loopbacks;

    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.extraConfig = lib.mapAttrs' (
        key: device: lib.nameValuePair "20-${key}" { "monitor.alsa.rules" = [ (deviceRule device) ]; }
      ) cfg.alsaDevices;
      extraConfig.pipewire = lib.mkIf (cfg.loopbacks != [ ]) {
        "99-loopbacks"."context.modules" = map loopbackModule cfg.loopbacks;
      };
    };
  };
}
