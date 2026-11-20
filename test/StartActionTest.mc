import Toybox.Test;
import Toybox.Lang;

module StartActionTest {
    (:test)
    function defaultSettingIsVoice(logger as Logger) as Boolean {
        Test.assertEqual(StartAction.DEFAULT, StartAction.VOICE);
        Test.assertEqual(AppStorage.getSetting("StartButtonAction"), StartAction.VOICE);
        return true;
    }

    (:test)
    function voiceWhenSupported(logger as Logger) as Boolean {
        Test.assert(StartAction.resolve(StartAction.VOICE, 3, true) == :voice);
        Test.assert(StartAction.resolve(null, 3, true) == :voice);
        return true;
    }

    (:test)
    function voiceFallsBackToHornWithoutMic(logger as Logger) as Boolean {
        Test.assert(StartAction.resolve(StartAction.VOICE, 3, false) == :horn);
        Test.assert(StartAction.resolve(null, null, false) == :horn);
        return true;
    }

    (:test)
    function oldOptionsStillWork(logger as Logger) as Boolean {
        Test.assert(StartAction.resolve(StartAction.HORN, 3, true) == :horn);
        Test.assert(StartAction.resolve(StartAction.LIGHT, 3, true) == :light);
        // front light needs protocol v3+, horn otherwise (legacy behaviour)
        Test.assert(StartAction.resolve(StartAction.LIGHT, 2, true) == :horn);
        Test.assert(StartAction.resolve(StartAction.LIGHT, null, true) == :horn);
        return true;
    }
}
