import Toybox.Lang;
import Toybox.Activity;

// Wrist heart rate for the home screen. The watch measures it itself, no phone needed.
module HeartRate {
    function label(bpm as Number or Null) as String {
        return bpm == null ? "--" : bpm.toString();
    }

    function current() as Number or Null {
        var info = Activity.getActivityInfo();
        return info == null ? null : info.currentHeartRate;
    }
}
