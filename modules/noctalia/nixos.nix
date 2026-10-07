{ config, lib, ... }:
let
  cfg = config.modules.noctalia;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.screenRecorder.convertToX.enable || cfg.screenRecorder.enable;
        message = "modules.noctalia.screenRecorder.convertToX.enable requires modules.noctalia.screenRecorder.enable.";
      }
    ];

    programs.gpu-screen-recorder.enable = lib.mkIf cfg.screenRecorder.convertToX.enable true;
  };
}
