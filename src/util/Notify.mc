import Toybox.Attention;
import Toybox.Lang;

// Connection beeps: once per state change (was -> now), never repeated.
// Wheel alarms from the phone (Alarms.alarmHandler) are separate and unchanged.
module Notify {
    // Returns :connected, :disconnected or null (no change / never connected).
    function transition(was, now) {
        if (now == true && was != true) {
            return :connected;
        }
        if (now != true && was == true) {
            return :disconnected;
        }
        return null;
    }

    function tone(t) {
        if (Attention has :playTone) {
            Attention.playTone(t);
        }
    }

    // Loud beep + long vibration for a lost wheel / lost phone.
    function lostAlert() {
        tone(Attention.TONE_LOUD_BEEP);
        if (Attention has :vibrate) {
            Attention.vibrate([ new Attention.VibeProfile(100, 600), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 600) ]);
        }
    }
}
