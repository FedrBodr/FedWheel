import Toybox.Lang;

// Values of the "StartButtonAction" setting and what a START press does.
module StartAction {
    const HORN = 0;
    const LIGHT = 1;
    const VOICE = 2;
    const DEFAULT = VOICE; // keep in sync with resources/settings/properties.xml

    // Returns :voice, :horn or :light.
    // Voice falls back to the horn on watches without a microphone API;
    // The front light works on every protocol (v2 phones: POST /actions/toggleFrontLight).
    function resolve(setting, protocolVersion, voiceAvailable) {
        if (setting == null) {
            setting = DEFAULT;
        }
        if (setting == VOICE) {
            return voiceAvailable ? :voice : :horn;
        }
        if (setting == LIGHT) {
            return :light;
        }
        return :horn;
    }
}
