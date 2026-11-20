import Toybox.Lang;
import Toybox.StringUtil;

// Pure voice-bridge protocol logic (no I/O), copied from FedVoice src/Proto.mc —
// covered by test-voice/VoiceProtoTest.mc. Port parsing lives in src/comm/VoicePort.mc.
// Contract: FedVoice README.md ("Phone contract").
module VoiceProto {
    const CHUNK_MAX = 3000;       // raw bytes per /voice/chunk (contract: <= 3 KB)
    const POLL_MS = 700;
    const POLL_TIMEOUT_MS = 30000;

    function chunkCount(size as Number, max as Number) as Number {
        return (size + max - 1) / max;
    }

    // Slice #seq (0-based) of at most max bytes.
    function chunkAt(bytes as ByteArray, seq as Number, max as Number) as ByteArray {
        var start = seq * max;
        var end = start + max;
        if (end > bytes.size()) {
            end = bytes.size();
        }
        return bytes.slice(start, end);
    }

    function chunkBody(sid as String, seq as Number, bytes as ByteArray) as Dictionary {
        var b64 = StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
        });
        return {"id" => sid, "seq" => seq, "data" => b64};
    }

    // /voice/start -> {"id": sid}
    function parseSid(code as Number, data as Object?) as String? {
        if (code != 200 || !(data instanceof Dictionary)) {
            return null;
        }
        var id = (data as Dictionary)["id"];
        return (id instanceof String) ? id as String : null;
    }

    // /voice/chunk and /voice/end -> {"ok": true}
    function isOk(code as Number, data as Object?) as Boolean {
        if (code != 200 || !(data instanceof Dictionary)) {
            return false;
        }
        return (data as Dictionary)["ok"] == true;
    }

    function str(v as Object?) as String {
        return (v instanceof String) ? v as String : "";
    }

    // /voice/result and /voice/confirm. Returns
    // {:kind => :pending|:done|:confirm|:error, :text, :reply, :code}.
    function parseResult(code as Number, data as Object?) as Dictionary {
        var r = {:kind => :error, :text => "", :reply => "", :code => code};
        if (code != 200 || !(data instanceof Dictionary)) {
            return r;
        }
        var d = data as Dictionary;
        r[:text] = str(d["text"]);
        r[:reply] = str(d["reply"]);
        var state = d["state"];
        if ("pending".equals(state)) {
            r[:kind] = :pending;
        } else if ("done".equals(state)) {
            r[:kind] = (d["needsConfirm"] == true) ? :confirm : :done;
        } else if ("error".equals(state)) {
            r[:kind] = :error;
        }
        return r;
    }

    function timedOut(startMs as Number, nowMs as Number, limitMs as Number) as Boolean {
        return nowMs - startMs >= limitMs;
    }
}
