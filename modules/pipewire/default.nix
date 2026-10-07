{ lib, ... }:
let
  inherit (lib) mkOption types;
  nullable =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };
in
{
  imports = [ ./nixos.nix ];

  options.modules.pipewire = {
    enable = lib.mkEnableOption "shared PipeWire audio support";

    virtualSinks = mkOption {
      default = { };
      description = "Virtual stereo null sinks, keyed by configuration name (99-<key>-sink).";
      type = types.attrsOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.nonEmptyStr;
              description = "PipeWire node.name, also usable as Sunshine audio_sink.";
            };
            description = mkOption {
              type = types.nonEmptyStr;
              description = "Human-readable node.description.";
            };
          };
        }
      );
    };

    alsaDevices = mkOption {
      default = { };
      description = "Consumer-owned ALSA device tuning, keyed by WirePlumber configuration name (20-<key>). Unset properties are omitted.";
      type = types.attrsOf (
        types.submodule {
          options = {
            deviceName = mkOption {
              type = types.nonEmptyStr;
              description = "Exact WirePlumber device.name to match.";
            };
            disableBatch = nullable types.bool "Whether to disable ALSA batch mode.";
            disableMmap = nullable types.bool "Whether to disable ALSA memory-mapped access.";
            periodNum = nullable types.ints.positive "ALSA period count.";
            periodSize = nullable types.ints.positive "ALSA period size in frames.";
            headroom = nullable types.ints.unsigned "ALSA headroom in frames.";
          };
        }
      );
    };

    loopbacks = mkOption {
      default = [ ];
      description = "Ordered PipeWire loopbacks from consumer-owned source nodes to a target or virtual audio source.";
      type = types.listOf (
        types.submodule {
          options = {
            name = nullable types.nonEmptyStr "Optional top-level loopback node.name.";
            description = mkOption {
              type = types.nonEmptyStr;
              description = "Loopback node.description.";
            };
            source = mkOption {
              type = types.nonEmptyStr;
              description = "Capture target.object (source node identity).";
            };
            target = nullable types.nonEmptyStr "Playback target.object; mutually exclusive with virtualSource.";
            capturePassive = mkOption {
              type = types.bool;
              default = false;
              description = "Set capture node.passive to true; false leaves the property unset.";
            };
            virtualSource = nullable (types.submodule {
              options = {
                name = mkOption {
                  type = types.nonEmptyStr;
                  description = "Playback node.name for the virtual Audio/Source.";
                };
                channels = mkOption {
                  type = types.listOf types.nonEmptyStr;
                  default = [
                    "FL"
                    "FR"
                  ];
                  description = "Virtual source audio.position channel names.";
                };
              };
            }) "Virtual Audio/Source playback node; mutually exclusive with target.";
          };
        }
      );
    };
  };
}
