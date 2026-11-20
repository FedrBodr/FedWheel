import Toybox.Test;
import Toybox.Lang;

// Phone voice bridge announces its port as ["fv", port] (contract shared with FedVoice).
module VoicePortTest {
    (:debug)
    class FakeMessage {
        var data;
        function initialize(d) {
            data = d;
        }
    }

    (:test)
    function parsesPortMessage(logger as Logger) as Boolean {
        Test.assertEqual(VoicePort.parse(["fv", 8123]), 8123);
        return true;
    }

    (:test)
    function ignoresForeignMessages(logger as Logger) as Boolean {
        Test.assert(VoicePort.parse(null) == null);
        Test.assert(VoicePort.parse(8080) == null);
        Test.assert(VoicePort.parse(["c", 8080]) == null);
        Test.assert(VoicePort.parse(["fv"]) == null);
        Test.assert(VoicePort.parse(["fv", "8080"]) == null);
        Test.assert(VoicePort.parse(["fv", 0]) == null);
        Test.assert(VoicePort.parse(["fv", 70000]) == null);
        Test.assert(VoicePort.parse({"fv" => 8080}) == null);
        return true;
    }

    (:test)
    function acceptsLongPort(logger as Logger) as Boolean {
        Test.assertEqual(VoicePort.parse(["fv", 9000l]), 9000);
        return true;
    }

    (:test)
    function handlerStoresVoicePortOnly(logger as Logger) as Boolean {
        WheelData.voicePort = null;
        var wheelPort = WheelData.webServerPort;
        var connected = WheelData.isAppConnected;
        phoneAppMessageHandler(new FakeMessage(["fv", 8123]));
        Test.assertEqual(WheelData.voicePort, 8123);
        // no side effects on the WheelLog connection
        Test.assert(WheelData.webServerPort == wheelPort);
        Test.assert(WheelData.isAppConnected == connected);
        return true;
    }

    (:test)
    function handlerIgnoresBadVoiceMessages(logger as Logger) as Boolean {
        WheelData.voicePort = 8123;
        phoneAppMessageHandler(new FakeMessage(["fv"]));
        phoneAppMessageHandler(new FakeMessage(["fv", "x"]));
        phoneAppMessageHandler(new FakeMessage(["fv", -1]));
        Test.assertEqual(WheelData.voicePort, 8123);
        return true;
    }
}
