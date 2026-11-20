import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

enum VoiceState {
    VS_IDLE,       // overlay hidden, dashboard as usual
    VS_NOPORT,     // "Голос: телефон не готов" (brief)
    VS_REC,        // capturing
    VS_FINISHING,  // capture stopped, waiting for the last data
    VS_SENDING,    // /voice/start, /voice/chunk..., /voice/end
    VS_THINKING,   // polling /voice/result (also after /voice/confirm)
    VS_RESULT,     // reply shown for RESULT_MS, then back to the dashboard
    VS_CONFIRM,    // "START — да, BACK — нет"
    VS_ERROR       // shown for RESULT_MS; START retries
}

// Push-to-talk state machine: recording -> upload -> poll -> result/confirm -> dashboard.
// Adapted from FedVoice src/Controller.mc. The port comes from WheelData.voicePort
// (set by phoneAppMessageHandler on ["fv", port]).
class VoiceController {
    const MAX_REC_S = 15;
    const MAX_BYTES = 300000;
    const FINISH_FALLBACK_MS = 1500;
    const RESULT_MS = 6000;
    const NOPORT_MS = 3000;
    const CONFIRM_MS = 30000;

    var state as VoiceState = VS_IDLE;
    var text as String = "";
    var reply as String = "";
    var errMsg as String = "";
    var recSeconds as Number = 0;
    var seq as Number = 0;
    var nChunks as Number = 0;

    private var _rec as VoiceRecorder;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _timerKind as Symbol = :none;
    private var _gen as Number = 0;
    private var _audio as ByteArray? = null;
    private var _sid as String? = null;
    private var _pollStart as Number = 0;
    private var _recStart as Number = 0;
    private var _retry as Symbol = :record;
    private var _confirmYes as Boolean = false;

    function initialize() {
        _rec = new VoiceRecorder(self);
    }

    // ---------- buttons ----------
    function onStartKey() as Void {
        switch (state) {
            case VS_IDLE:
            case VS_NOPORT:
            case VS_RESULT:
                startRecording();
                break;
            case VS_REC:
                stopRecording();
                break;
            case VS_CONFIRM:
                sendConfirm(true);
                break;
            case VS_ERROR:
                retry();
                break;
            default:
                break; // busy: ignore
        }
    }

    // Returns false when idle so the dashboard handles BACK as before.
    function onBackKey() as Boolean {
        switch (state) {
            case VS_IDLE:
                return false;
            case VS_CONFIRM:
                sendConfirm(false);
                return true;
            case VS_REC:
                _rec.stop();
                _rec.takeAudio();
                goIdle();
                return true;
            default:
                goIdle();
                return true;
        }
    }

    function shutdown() as Void {
        _gen++;
        _timer.stop();
        _rec.stop();
    }

    // ---------- recording ----------
    private function startRecording() as Void {
        _gen++;
        _timer.stop();
        _audio = null;
        _sid = null;
        text = "";
        reply = "";
        if (WheelData.voicePort == null) {
            state = VS_NOPORT;
            sayHello();
            vibrate(200);
            schedule(:dismiss, NOPORT_MS, false);
            WatchUi.requestUpdate();
            return;
        }
        var err = _rec.start();
        if (err != null) {
            fail(err == :format ? rez(Rez.Strings.Voice_ErrFormat) : rez(Rez.Strings.Voice_ErrMic), :record);
            return;
        }
        state = VS_REC;
        recSeconds = 0;
        _recStart = System.getTimer();
        vibrate(60);
        schedule(:tick, 1000, true);
        WatchUi.requestUpdate();
    }

    private function stopRecording() as Void {
        _timer.stop();
        state = VS_FINISHING;
        _rec.stop();
        // Capture delivers remaining data then onComplete; fall back if it never comes.
        schedule(:finish, FINISH_FALLBACK_MS, false);
        WatchUi.requestUpdate();
    }

    function onRecComplete() as Void {
        if (state == VS_FINISHING || state == VS_REC) {
            finishRecording();
        }
    }

    function onRecError(code as Number) as Void {
        if (state == VS_REC || state == VS_FINISHING) {
            _rec.takeAudio();
            fail(rez(Rez.Strings.Voice_ErrMic) + " (" + code + ")", :record);
        }
    }

    private function finishRecording() as Void {
        _timer.stop();
        var audio = _rec.takeAudio();
        System.println("FedWheel voice: recorded " + audio.size() + " bytes");
        if (audio.size() == 0) {
            fail(rez(Rez.Strings.Voice_ErrEmpty), :record);
            return;
        }
        _audio = audio;
        beginUpload();
    }

    // ---------- upload ----------
    private function beginUpload() as Void {
        _gen++;
        state = VS_SENDING;
        seq = 0;
        nChunks = 0;
        _retry = :upload;
        WatchUi.requestUpdate();
        if (WheelData.voicePort == null) {
            fail(rez(Rez.Strings.Voice_NoPhone), :upload);
            return;
        }
        post(:start, "/voice/start", {});
    }

    private function sendNextChunk() as Void {
        var audio = _audio as ByteArray;
        if (seq < nChunks) {
            post(:chunk, "/voice/chunk", VoiceProto.chunkBody(_sid as String, seq, VoiceProto.chunkAt(audio, seq, VoiceProto.CHUNK_MAX)));
        } else {
            post(:end, "/voice/end", {"id" => _sid});
        }
        WatchUi.requestUpdate();
    }

    // ---------- result / confirm ----------
    private function startPolling() as Void {
        state = VS_THINKING;
        _retry = :poll;
        _pollStart = System.getTimer();
        schedule(:poll, VoiceProto.POLL_MS, false);
        WatchUi.requestUpdate();
    }

    private function sendConfirm(yes as Boolean) as Void {
        _gen++;
        _timer.stop();
        _confirmYes = yes;
        _retry = :confirm;
        state = VS_THINKING;
        _pollStart = System.getTimer(); // a pending confirm answer continues as polling
        WatchUi.requestUpdate();
        post(:confirm, "/voice/confirm", {"id" => _sid, "yes" => yes});
    }

    private function handleResult(code as Number, data as Object?) as Void {
        var r = VoiceProto.parseResult(code, data);
        var kind = r[:kind];
        if (kind == :pending) {
            if (state != VS_THINKING) {
                startPolling();
            } else if (VoiceProto.timedOut(_pollStart, System.getTimer(), VoiceProto.POLL_TIMEOUT_MS)) {
                fail(rez(Rez.Strings.Voice_ErrTimeout), :poll);
            } else {
                schedule(:poll, VoiceProto.POLL_MS, false);
            }
            return;
        }
        if (kind == :error) {
            if (code != 200) {
                fail(netError(code), _retry);
            } else {
                var msg = r[:reply] as String;
                text = r[:text] as String;
                // server-side failure: retrying re-sends the same recording
                fail(msg.length() > 0 ? msg : rez(Rez.Strings.Voice_ErrServer), _audio != null ? :upload : :record);
            }
            return;
        }
        text = r[:text] as String;
        reply = r[:reply] as String;
        if (kind == :confirm) {
            state = VS_CONFIRM;
            schedule(:dismiss, CONFIRM_MS, false);
        } else {
            state = VS_RESULT;
            _audio = null; // done; free memory
            schedule(:dismiss, RESULT_MS, false);
        }
        vibrate(40);
        WatchUi.requestUpdate();
    }

    // ---------- network ----------
    private function post(kind as Symbol, path as String, body as Dictionary) as Void {
        var opts = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        request(kind, path, body, opts);
    }

    private function request(kind as Symbol, path as String, params as Dictionary?, opts as Dictionary) as Void {
        var req = new VoiceRequest(self, _gen, kind);
        try {
            Communications.makeWebRequest("http://127.0.0.1:" + WheelData.voicePort + path, params, opts, req.method(:onResponse));
        } catch (e instanceof Lang.Exception) {
            System.println("FedWheel voice: makeWebRequest threw " + e.getErrorMessage());
            fail(rez(Rez.Strings.Voice_ErrNet), _retry);
        }
    }

    function onResponse(gen as Number, kind as Symbol, code as Number, data as Object?) as Void {
        if (gen != _gen) {
            return; // stale (cancelled flow)
        }
        if (code != 200) {
            System.println("FedWheel voice: " + kind + " -> " + code);
        }
        if (kind == :start) {
            var sid = VoiceProto.parseSid(code, data);
            if (sid == null) {
                fail(code == 200 ? rez(Rez.Strings.Voice_ErrServer) : netError(code), :upload);
                return;
            }
            _sid = sid;
            seq = 0;
            nChunks = VoiceProto.chunkCount((_audio as ByteArray).size(), VoiceProto.CHUNK_MAX);
            sendNextChunk();
        } else if (kind == :chunk) {
            if (!VoiceProto.isOk(code, data)) {
                fail(code == 200 ? rez(Rez.Strings.Voice_ErrServer) : netError(code), :upload);
                return;
            }
            seq++;
            sendNextChunk();
        } else if (kind == :end) {
            if (!VoiceProto.isOk(code, data)) {
                fail(code == 200 ? rez(Rez.Strings.Voice_ErrServer) : netError(code), :upload);
                return;
            }
            startPolling();
        } else if (kind == :poll || kind == :confirm) {
            handleResult(code, data);
        }
    }

    private function netError(code as Number) as String {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE || code == Communications.BLE_HOST_TIMEOUT) {
            return rez(Rez.Strings.Voice_ErrPhone) + " (" + code + ")";
        }
        return rez(Rez.Strings.Voice_ErrNet) + " (" + code + ")";
    }

    // ---------- timer ----------
    private function schedule(kind as Symbol, ms as Number, repeat as Boolean) as Void {
        _timer.stop();
        _timerKind = kind;
        _timer.start(method(:onTimer), ms, repeat);
    }

    function onTimer() as Void {
        var k = _timerKind;
        if (k == :tick && state == VS_REC) {
            recSeconds = (System.getTimer() - _recStart) / 1000;
            if (recSeconds >= MAX_REC_S || _rec.bytes() > MAX_BYTES) {
                stopRecording();
                return;
            }
            WatchUi.requestUpdate();
        } else if (k == :finish && state == VS_FINISHING) {
            finishRecording();
        } else if (k == :poll && state == VS_THINKING) {
            request(:poll, "/voice/result", {"id" => _sid}, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            });
        } else if (k == :dismiss && (state == VS_RESULT || state == VS_ERROR || state == VS_NOPORT || state == VS_CONFIRM)) {
            goIdle();
        }
    }

    // ---------- helpers ----------
    private function retry() as Void {
        if (_retry == :upload && _audio != null) {
            beginUpload();
        } else if (_retry == :poll && _sid != null) {
            _gen++;
            startPolling();
        } else if (_retry == :confirm && _sid != null) {
            sendConfirm(_confirmYes);
        } else {
            startRecording();
        }
    }

    private function fail(msg as String, retryOp as Symbol) as Void {
        _gen++;
        _timer.stop();
        errMsg = msg;
        _retry = retryOp;
        state = VS_ERROR;
        vibrate(200);
        schedule(:dismiss, RESULT_MS, false);
        WatchUi.requestUpdate();
    }

    private function goIdle() as Void {
        _gen++;
        _timer.stop();
        _audio = null;
        state = VS_IDLE;
        WatchUi.requestUpdate();
    }

    // Ask the phone bridge to (re-)announce ["fv", port] now instead of on its next backoff.
    private function sayHello() as Void {
        try {
            Communications.transmit(["fv-hello"], null, new ActionConnectionListener());
        } catch (e instanceof Lang.Exception) {
        }
    }

    private function vibrate(ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, ms)]);
        }
    }

    function rez(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }
}
