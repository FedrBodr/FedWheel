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

// Push-to-talk state machine: record while streaming the audio to the phone -> /voice/end ->
// poll -> result/confirm -> dashboard. Adapted from FedVoice src/Controller.mc. The port comes from
// WheelData.voicePort (set by phoneAppMessageHandler on ["fv", port]).
class VoiceController {
    const MAX_REC_S = 60;
    const MAX_UNSENT = 200000;      // bytes the phone has not acknowledged yet: stop recording beyond this
    const FINISH_FALLBACK_MS = 1500;
    const PORT_WAIT_MS = 10000;
    const RESULT_MS = 6000;
    const NOPORT_MS = 3000;
    const CONFIRM_MS = 30000;

    var state as VoiceState = VS_IDLE;
    var text as String = "";
    var reply as String = "";
    var errMsg as String = "";
    var recSeconds as Number = 0;
    var sent as Number = 0;         // slices acknowledged by the phone
    var total as Number = 0;        // slices so far
    var peakUsed as Number = 0;     // memory high-water mark of this recording (logged)

    private var _rec as VoiceRecorder;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _timerKind as Symbol = :none;
    private var _gen as Number = 0;
    private var _up as VoiceUpload? = null;
    private var _sid as String? = null;
    private var _pollStart as Number = 0;
    private var _recStart as Number = 0;
    private var _stopAt as Number = 0;
    private var _noPortSince as Number = 0;
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
            case VS_FINISHING:
                _rec.stop();
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

    // ---------- recording + streaming upload ----------
    private function startRecording() as Void {
        _gen++;
        _timer.stop();
        _up = null;
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
        _up = new VoiceUpload(VoiceProto.CHUNK_MAX);
        peakUsed = 0;
        var err = _rec.start();
        if (err != null) {
            _up = null;
            fail(err == :format ? rez(Rez.Strings.Voice_ErrFormat) : rez(Rez.Strings.Voice_ErrMic), :record);
            return;
        }
        state = VS_REC;
        recSeconds = 0;
        _recStart = System.getTimer();
        _noPortSince = 0;
        _retry = :upload;
        vibrate(60);
        schedule(:tick, 1000, true);
        pump(); // the session is created right away
        WatchUi.requestUpdate();
    }

    private function stopRecording() as Void {
        state = VS_FINISHING;
        _stopAt = System.getTimer();
        _rec.stop();
        // Capture delivers remaining data then onComplete; the tick falls back if it never comes.
        WatchUi.requestUpdate();
    }

    function onRecData(bytes as ByteArray) as Void {
        var up = _up;
        if (up == null) {
            return;
        }
        up.append(bytes);
        if (state == VS_REC && up.unsent() > MAX_UNSENT) {
            System.println("FedWheel voice: upload lags (" + up.unsent() + " B unsent), stopping");
            stopRecording();
        }
        pump();
    }

    function onRecComplete() as Void {
        if (state == VS_FINISHING || state == VS_REC) {
            finishRecording();
        }
    }

    function onRecError(code as Number) as Void {
        if (state == VS_REC || state == VS_FINISHING) {
            _up = null;
            fail(rez(Rez.Strings.Voice_ErrMic) + " (" + code + ")", :record);
        }
    }

    private function finishRecording() as Void {
        var up = _up;
        if (up == null) {
            return;
        }
        System.println("FedWheel voice: recorded " + up.bytes() + " bytes, " + up.acked() + " slices already sent, peak mem " + peakUsed);
        if (up.bytes() == 0) {
            _up = null;
            fail(rez(Rez.Strings.Voice_ErrEmpty), :record);
            return;
        }
        up.finish();
        state = VS_SENDING;
        pump();
        WatchUi.requestUpdate();
    }

    // Sends the next start/chunk/end request when nothing is in flight.
    private function pump() as Void {
        var up = _up;
        if (up == null || WheelData.voicePort == null
                || (state != VS_REC && state != VS_FINISHING && state != VS_SENDING)) {
            return;
        }
        var a = up.next();
        progress();
        if (a == null) {
            return;
        }
        var k = a[:kind];
        if (k == :start) {
            post(:start, "/voice/start", {});
        } else if (k == :chunk) {
            post(:chunk, "/voice/chunk", VoiceProto.chunkBody(up.sid as String, a[:seq] as Number, a[:data] as ByteArray));
        } else {
            post(:end, "/voice/end", {"id" => up.sid});
        }
    }

    private function onUploadResponse(kind as Symbol, code as Number, data as Object?) as Void {
        var up = _up;
        if (up == null) {
            return;
        }
        var sid = (kind == :start) ? VoiceProto.parseSid(code, data) : null;
        var ok = (kind == :start) ? sid != null : VoiceProto.isOk(code, data);
        if (ok) {
            up.onOk(sid);
            if (kind == :start) {
                _sid = sid;
            } else if (kind == :end) {
                progress();
                startPolling();
                return;
            }
            pump();
            WatchUi.requestUpdate();
        } else if (up.onFail()) {
            System.println("FedWheel voice: " + kind + " failed (" + code + "), retrying");
            // re-sent from the next tick (<= 1 s)
        } else {
            failUpload(code == 200 ? rez(Rez.Strings.Voice_ErrServer) : netError(code));
        }
    }

    // Upload gave up. START on the error screen re-sends the whole recording in a fresh session
    // while it is still kept (nothing acknowledged yet); otherwise it records again.
    private function failUpload(msg as String) as Void {
        if (state == VS_REC || state == VS_FINISHING) {
            _rec.stop();
        }
        var up = _up;
        if (up != null) {
            up.finish();
        }
        if (up == null || !up.restartable()) {
            msg += "\n" + rez(Rez.Strings.Voice_Repeat);
        }
        fail(msg, :upload);
    }

    private function progress() as Void {
        var up = _up;
        if (up != null) {
            sent = up.acked();
            total = up.slices();
        }
    }

    // Seconds spent waiting for the answer (shown next to "Думаю…").
    function thinkSeconds() as Number {
        return (System.getTimer() - _pollStart) / 1000;
    }

    // True when uploads trail the capture by more than the slice being filled.
    function lagging() as Boolean {
        return total - sent >= 2;
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
                WatchUi.requestUpdate(); // elapsed seconds
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
                fail(msg.length() > 0 ? msg : rez(Rez.Strings.Voice_ErrServer), :upload);
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
            _up = null; // done; free memory
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
        if (kind == :start || kind == :chunk || kind == :end) {
            onUploadResponse(kind, code, data);
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
        if (k == :tick && (state == VS_REC || state == VS_FINISHING || state == VS_SENDING)) {
            var now = System.getTimer();
            sampleMemory();
            if (state == VS_REC) {
                recSeconds = (now - _recStart) / 1000;
                if (recSeconds >= MAX_REC_S) {
                    stopRecording();
                }
            } else if (state == VS_FINISHING && now - _stopAt >= FINISH_FALLBACK_MS) {
                finishRecording();
            }
            if (WheelData.voicePort == null) {
                if (_noPortSince == 0) {
                    _noPortSince = now;
                } else if (state == VS_SENDING && now - _noPortSince > PORT_WAIT_MS) {
                    failUpload(rez(Rez.Strings.Voice_ErrPhone));
                    return;
                }
            } else {
                _noPortSince = 0;
            }
            pump();
            WatchUi.requestUpdate();
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
        var up = _up;
        if (_retry == :upload && up != null && up.restart()) {
            _gen++;
            state = VS_SENDING;
            _noPortSince = 0;
            schedule(:tick, 1000, true);
            pump();
            WatchUi.requestUpdate();
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
        _up = null;
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

    private function sampleMemory() as Void {
        var st = System.getSystemStats();
        var used = st.usedMemory;
        if (used > peakUsed) {
            peakUsed = used;
        }
        var up = _up;
        System.println("FedWheel voice: t=" + recSeconds + "s mem used=" + used + " free=" + st.freeMemory
            + " unsent=" + (up != null ? up.unsent() : 0) + " sent=" + sent + "/" + total);
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
