import Toybox.Lang;

// Streaming upload of one recording, without I/O (covered by test-voice/VoiceUploadTest.mc).
// Audio is appended while it is captured; next() says what to send: /voice/start once, then
// /voice/chunk slices of at most `max` bytes with strictly sequential seq (one request in flight),
// then /voice/end after stop and after every slice was acknowledged. An acknowledged slice is
// dropped, so memory holds only the bytes the phone has not confirmed yet.
class VoiceUpload {
    const MAX_RETRIES = 2;

    var sid as String? = null;

    private var _max as Number;
    private var _buf as ByteArray = []b;   // unacknowledged bytes; the head slice may be in flight
    private var _slice as Number = 0;      // size of the head slice once it was sent (0 = not chosen yet)
    private var _seq as Number = 0;        // acknowledged slices = seq of the head slice
    private var _kind as Symbol? = null;   // request in flight (:start, :chunk, :end) or null
    private var _finished as Boolean = false;
    private var _ended as Boolean = false;
    private var _tries as Number = 0;
    private var _total as Number = 0;      // bytes ever appended

    function initialize(max as Number) {
        _max = max;
    }

    function append(bytes as ByteArray) as Void {
        _buf.addAll(bytes);
        _total += bytes.size();
    }

    // Recording stopped: the remainder may now go out as a short slice, then /voice/end.
    function finish() as Void {
        _finished = true;
    }

    // Next request to send, marked in flight: {:kind => :start} | {:kind => :chunk, :seq, :data} |
    // {:kind => :end}. Null while a request is in flight, while less than one full slice is buffered
    // during recording, or once the session has ended.
    function next() as Dictionary? {
        if (_kind != null || _ended) {
            return null;
        }
        if (sid == null) {
            _kind = :start;
            return {:kind => :start};
        }
        if (_slice == 0) {
            var n = _buf.size();
            if (n >= _max || (_finished && n > 0)) {
                _slice = n < _max ? n : _max;
            }
        }
        if (_slice > 0) {
            _kind = :chunk;
            return {:kind => :chunk, :seq => _seq, :data => _buf.slice(0, _slice)};
        }
        if (_finished) {
            _kind = :end;
            return {:kind => :end};
        }
        return null;
    }

    // The in-flight request succeeded (newSid only for :start). Returns its kind.
    function onOk(newSid as String?) as Symbol? {
        var k = _kind;
        if (k == :start) {
            sid = newSid;
        } else if (k == :chunk) {
            _buf = _buf.slice(_slice, null);
            _slice = 0;
            _seq++;
        } else if (k == :end) {
            _ended = true;
        }
        _kind = null;
        _tries = 0;
        return k;
    }

    // The in-flight request failed. True when it may be re-sent (next() returns the same request).
    function onFail() as Boolean {
        _kind = null;
        _tries++;
        return _tries <= MAX_RETRIES;
    }

    // Start over in a fresh session with the whole recording. Only possible while nothing was
    // acknowledged (dropped) yet; returns false otherwise.
    function restart() as Boolean {
        if (_seq > 0) {
            return false;
        }
        sid = null;
        _slice = 0;
        _kind = null;
        _tries = 0;
        _ended = false;
        return true;
    }

    function restartable() as Boolean {
        return _seq == 0;
    }

    function busy() as Boolean {
        return _kind != null;
    }

    function ended() as Boolean {
        return _ended;
    }

    function acked() as Number {
        return _seq;
    }

    // Slices so far: acknowledged + still to send (the partial tail counts as one).
    function slices() as Number {
        return _seq + (_buf.size() + _max - 1) / _max;
    }

    function bytes() as Number {
        return _total;
    }

    function unsent() as Number {
        return _buf.size();
    }
}
