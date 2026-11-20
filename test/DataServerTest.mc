import Toybox.Test;
import Toybox.Lang;

// Pins compatibility with the stock WheelLog phone app (GarminConnectIQ.kt, /data/main).
// WheelLog sends speed/topSpeed/pwm/maxPwm as strings, battery/temp/speedLimit as numbers.
module DataServerTest {
    (:debug)
    function wheelLogMain(connected as Boolean, useMph as Boolean) as Dictionary {
        return {
            "speed" => "12.3",
            "topSpeed" => "25.1",
            "speedLimit" => 30,
            "useMph" => useMph,
            "battery" => 80,
            "temp" => 35,
            "pwm" => "07",
            "maxPwm" => "40",
            "connectedToWheel" => connected,
            "wheelModel" => "V8"
        };
    }

    (:test)
    function parsesMainFromWheelLog(logger as Logger) as Boolean {
        DataServer.parseOldProtocolData(:main, wheelLogMain(true, false));
        Test.assert(WheelData.currentSpeed.equals("12.3"));
        Test.assertEqual(WheelData.batteryPercentage, 80);
        Test.assertEqual(WheelData.speedLimit, 30);
        Test.assertEqual(WheelData.isWheelConnected, true);
        Test.assert(WheelData.wheelModel.equals("V8"));
        Test.assertEqual(WheelData.currentSpeed.toFloat(), 12.3f);
        return true;
    }

    (:test)
    function wheelDisconnectedKeepsRunning(logger as Logger) as Boolean {
        DataServer.parseOldProtocolData(:main, wheelLogMain(false, false));
        Test.assertEqual(WheelData.isWheelConnected, false);
        return true;
    }

    (:test)
    function phoneUnreachableDoesNotParse(logger as Logger) as Boolean {
        DataServer.updateUsingOldProtocol_main(-104, null);
        Test.assertEqual(AppStorage.runtimeDb["comm_lastResponseCode"], -104);
        return true;
    }

    (:test)
    function mphFlagStored(logger as Logger) as Boolean {
        DataServer.parseOldProtocolData(:main, wheelLogMain(true, true));
        Test.assertEqual(WheelData.useMph, true);
        return true;
    }
}
