import Toybox.Lang;

// Port of the phone voice bridge (separate local HTTP server, see src-voice/).
// Phone -> watch message ["fv", port]; same contract as the standalone FedVoice app.
module VoicePort {
    const MSG_TAG = "fv";

    // Returns the port, or null for anything that is not a valid ["fv", port].
    function parse(data) {
        if (!(data instanceof Lang.Array)) {
            return null;
        }
        if (data.size() < 2 || !(data[0] instanceof Lang.String) || !data[0].equals(MSG_TAG)) {
            return null;
        }
        var p = data[1];
        if (!(p instanceof Lang.Number) && !(p instanceof Lang.Long)) {
            return null;
        }
        var port = p.toNumber();
        if (port < 1 || port > 65535) {
            return null;
        }
        return port;
    }
}
