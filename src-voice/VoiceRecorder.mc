import Toybox.Audio;
import Toybox.Audio.Capture;
import Toybox.Lang;
import Toybox.System;

// Wraps Audio.Capture: records one Ogg/Opus stream into memory (from FedVoice src/Recorder.mc).
// Reports back to the controller via onRecError / onRecComplete.
class VoiceRecorder {
    private var _ctl as VoiceController;
    private var _bufs as Array<ByteArray> = [] as Array<ByteArray>;
    private var _bytes as Number = 0;
    private var _inited as Boolean = false;
    var formatDesc as String = "";

    function initialize(ctl as VoiceController) {
        _ctl = ctl;
    }

    function bytes() as Number {
        return _bytes;
    }

    // Ogg/Opus mono, 16 kHz preferred; Opus only supports 8/12/16/24/48 kHz.
    private function pickFormat() as Dictionary? {
        var freqs = [Audio.FREQ_16_KHZ, Audio.FREQ_24_KHZ, Audio.FREQ_12_KHZ, Audio.FREQ_8_KHZ];
        var names = ["16k", "24k", "12k", "8k"];
        var chans = [Audio.CHANNEL_MONO, Audio.CHANNEL_STEREO];
        for (var c = 0; c < chans.size(); c++) {
            for (var i = 0; i < freqs.size(); i++) {
                var f = {
                    :containerFormat => Audio.CONTAINER_OGG,
                    :codec => Audio.CODEC_OPUS,
                    :frequency => freqs[i],
                    :channels => chans[c]
                };
                if (Capture.isFormatSupported(f)) {
                    formatDesc = "ogg/opus " + names[i] + (c == 0 ? " mono" : " stereo");
                    return f;
                }
            }
        }
        return null;
    }

    // Returns null on success or an error symbol (:format, :mic).
    function start() as Symbol? {
        _bufs = [] as Array<ByteArray>;
        _bytes = 0;
        if (!(Toybox has :Audio) || !(Audio has :Capture)) {
            return :mic;
        }
        var reused = _inited;
        var err = startOnce();
        if (err == :mic && reused) {
            // After a completed capture the system may drop the capture session
            // ("Audio capture is not initialized"): initialise again once.
            err = startOnce();
        }
        return err;
    }

    private function startOnce() as Symbol? {
        try {
            if (!_inited) {
                var fmt = pickFormat();
                if (fmt == null) {
                    System.println("FedWheel voice: no Ogg/Opus capture format supported");
                    return :format;
                }
                var filters = [] as Array<Capture.Filter>;
                var supported = Capture.getSupportedFilters();
                for (var i = 0; i < supported.size(); i++) {
                    if (supported[i] == Capture.FILTER_NREC) {
                        filters.add(Capture.FILTER_NREC);
                    }
                }
                var sizes = [4096, 2048, 1024];
                for (var i = 0; i < sizes.size() && !_inited; i++) {
                    try {
                        var used = Capture.initializeAudioCapture(self, {
                            :format => fmt,
                            :windowSize => sizes[i],
                            :windowFilledBehavior => Capture.WINDOW_FILLED_CONTINUE,
                            :filters => filters
                        } as Capture.Settings);
                        _inited = true;
                        System.println("FedWheel voice: capture " + formatDesc + " window=" + used[:windowSize] + " filters=" + filters.size());
                    } catch (e instanceof Lang.ValueOutOfBoundsException) {
                        System.println("FedWheel voice: window " + sizes[i] + " too large");
                    }
                }
                if (!_inited) {
                    return :mic;
                }
            }
            Capture.start();
        } catch (e instanceof Lang.Exception) {
            System.println("FedWheel voice: capture start failed: " + e.getErrorMessage());
            _inited = false;
            return :mic;
        }
        return null;
    }

    function stop() as Void {
        if (!(Toybox has :Audio) || !(Audio has :Capture)) {
            return;
        }
        try {
            if (Capture.getState() == Capture.CAPTURE_CAPTURING) {
                Capture.stop();
            }
        } catch (e instanceof Lang.Exception) {
            System.println("FedWheel voice: capture stop failed: " + e.getErrorMessage());
        }
    }

    // Concatenate the captured windows into one Ogg stream and free the buffers.
    function takeAudio() as ByteArray {
        var out = []b;
        for (var i = 0; i < _bufs.size(); i++) {
            out.addAll(_bufs[i]);
        }
        _bufs = [] as Array<ByteArray>;
        _bytes = 0;
        return out;
    }

    // ---- Capture.Callbacks ----
    function onData(audioData as ByteArray) as Void {
        _bufs.add(audioData);
        _bytes += audioData.size();
    }

    function onError(error as Capture.Error) as Void {
        System.println("FedWheel voice: capture error " + error);
        _ctl.onRecError(error as Number);
    }

    function onComplete() as Void {
        _ctl.onRecComplete();
    }
}
