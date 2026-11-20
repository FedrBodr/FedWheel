import Toybox.Test;
import Toybox.Lang;

module HeartRateTest {
    (:test)
    function showsDashesWhenNoReading(logger as Logger) as Boolean {
        Test.assert(HeartRate.label(null).equals("--"));
        return true;
    }

    (:test)
    function showsBpmNumber(logger as Logger) as Boolean {
        Test.assert(HeartRate.label(92).equals("92"));
        return true;
    }
}
