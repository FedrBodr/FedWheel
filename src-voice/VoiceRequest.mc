import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;

// One in-flight web request. Carries the controller generation so that
// responses to cancelled flows are dropped.
class VoiceRequest {
    private var _ctl as VoiceController;
    private var _gen as Number;
    private var _kind as Symbol;

    function initialize(ctl as VoiceController, gen as Number, kind as Symbol) {
        _ctl = ctl;
        _gen = gen;
        _kind = kind;
    }

    function onResponse(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        _ctl.onResponse(_gen, _kind, code, data);
    }
}
