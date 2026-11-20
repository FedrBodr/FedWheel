import Toybox.Test;
import Toybox.Lang;

// Connection beeps fire once per state change, never on repeats.
module NotifyTest {
    (:test)
    function beepsOnConnect(logger as Logger) as Boolean {
        Test.assert(Notify.transition(false, true) == :connected);
        Test.assert(Notify.transition(null, true) == :connected);
        return true;
    }

    (:test)
    function beepsOnDisconnect(logger as Logger) as Boolean {
        Test.assert(Notify.transition(true, false) == :disconnected);
        return true;
    }

    (:test)
    function silentWhenStateRepeats(logger as Logger) as Boolean {
        Test.assert(Notify.transition(true, true) == null);   // repeated port message
        Test.assert(Notify.transition(false, false) == null); // wheel still off
        return true;
    }

    (:test)
    function silentWhenNeverConnected(logger as Logger) as Boolean {
        Test.assert(Notify.transition(null, false) == null); // app start without wheel/phone
        return true;
    }
}
