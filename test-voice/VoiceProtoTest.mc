import Toybox.Test;
import Toybox.Lang;

module VoiceProtoTest {
    function bytes(n as Number) as ByteArray {
        var b = new [n]b;
        for (var i = 0; i < n; i++) {
            b[i] = i % 256;
        }
        return b;
    }

    // ---- chunking ----
    (:test)
    function chunkCountRoundsUp(logger as Logger) as Boolean {
        Test.assertEqual(VoiceProto.chunkCount(0, 3000), 0);
        Test.assertEqual(VoiceProto.chunkCount(1, 3000), 1);
        Test.assertEqual(VoiceProto.chunkCount(3000, 3000), 1);
        Test.assertEqual(VoiceProto.chunkCount(3001, 3000), 2);
        Test.assertEqual(VoiceProto.chunkCount(9000, 3000), 3);
        return true;
    }

    (:test)
    function chunksAreConsecutiveSlicesWithinLimit(logger as Logger) as Boolean {
        var src = bytes(7001);
        var n = VoiceProto.chunkCount(src.size(), 3000);
        Test.assertEqual(n, 3);
        var total = 0;
        for (var seq = 0; seq < n; seq++) {
            var c = VoiceProto.chunkAt(src, seq, 3000);
            Test.assert(c.size() <= 3000);
            for (var i = 0; i < c.size(); i++) {
                Test.assertEqual(c[i], src[total + i]);
            }
            total += c.size();
        }
        Test.assertEqual(total, 7001);
        Test.assertEqual(VoiceProto.chunkAt(src, 2, 3000).size(), 1001);
        return true;
    }

    (:test)
    function chunkBodyHasIdSeqBase64(logger as Logger) as Boolean {
        var body = VoiceProto.chunkBody("s1", 4, [1, 2, 3]b);
        Test.assert(body["id"].equals("s1"));
        Test.assertEqual(body["seq"], 4);
        Test.assert(body["data"].equals("AQID"));
        return true;
    }

    // ---- start / ok responses ----
    (:test)
    function parsesSessionId(logger as Logger) as Boolean {
        Test.assert(VoiceProto.parseSid(200, {"id" => "abc"}).equals("abc"));
        Test.assert(VoiceProto.parseSid(200, {"x" => 1}) == null);
        Test.assert(VoiceProto.parseSid(500, {"id" => "abc"}) == null);
        Test.assert(VoiceProto.parseSid(-104, null) == null);
        return true;
    }

    (:test)
    function okResponse(logger as Logger) as Boolean {
        Test.assert(VoiceProto.isOk(200, {"ok" => true}));
        Test.assert(!VoiceProto.isOk(200, {"ok" => false}));
        Test.assert(!VoiceProto.isOk(200, null));
        Test.assert(!VoiceProto.isOk(404, {"ok" => true}));
        return true;
    }

    // ---- result states ----
    (:test)
    function resultPending(logger as Logger) as Boolean {
        var r = VoiceProto.parseResult(200, {"state" => "pending", "text" => "", "reply" => "", "needsConfirm" => false});
        Test.assert(r[:kind] == :pending);
        return true;
    }

    (:test)
    function resultDone(logger as Logger) as Boolean {
        var r = VoiceProto.parseResult(200, {"state" => "done", "text" => "привет", "reply" => "здравствуй", "needsConfirm" => false});
        Test.assert(r[:kind] == :done);
        Test.assert((r[:text] as String).equals("привет"));
        Test.assert((r[:reply] as String).equals("здравствуй"));
        return true;
    }

    (:test)
    function resultNeedsConfirm(logger as Logger) as Boolean {
        var r = VoiceProto.parseResult(200, {"state" => "done", "text" => "купи", "reply" => "Купить?", "needsConfirm" => true});
        Test.assert(r[:kind] == :confirm);
        Test.assert((r[:reply] as String).equals("Купить?"));
        return true;
    }

    (:test)
    function resultError(logger as Logger) as Boolean {
        var r = VoiceProto.parseResult(200, {"state" => "error", "text" => "", "reply" => "не расслышал", "needsConfirm" => false});
        Test.assert(r[:kind] == :error);
        Test.assert((r[:reply] as String).equals("не расслышал"));
        return true;
    }

    (:test)
    function resultTransportFailureIsError(logger as Logger) as Boolean {
        var r = VoiceProto.parseResult(-104, null);
        Test.assert(r[:kind] == :error);
        Test.assertEqual(r[:code], -104);
        r = VoiceProto.parseResult(500, {"state" => "done"});
        Test.assert(r[:kind] == :error);
        Test.assertEqual(r[:code], 500);
        return true;
    }

    (:test)
    function resultMalformedIsError(logger as Logger) as Boolean {
        Test.assert(VoiceProto.parseResult(200, null)[:kind] == :error);
        Test.assert(VoiceProto.parseResult(200, {"state" => "weird"})[:kind] == :error);
        // missing optional fields tolerated
        var r = VoiceProto.parseResult(200, {"state" => "done"});
        Test.assert(r[:kind] == :done);
        Test.assert((r[:text] as String).equals(""));
        Test.assert((r[:reply] as String).equals(""));
        return true;
    }

    // ---- poll timeout ----
    (:test)
    function pollTimeout(logger as Logger) as Boolean {
        Test.assert(!VoiceProto.timedOut(1000, 30999, 30000));
        Test.assert(VoiceProto.timedOut(1000, 31000, 30000));
        return true;
    }

    (:test)
    function pollWaitsUpTo90sForSlowAnswers(logger as Logger) as Boolean {
        Test.assertEqual(VoiceProto.POLL_TIMEOUT_MS, 90000);
        Test.assert(!VoiceProto.timedOut(0, 60000, VoiceProto.POLL_TIMEOUT_MS)); // server can need ~30-60 s
        Test.assert(VoiceProto.timedOut(0, 90000, VoiceProto.POLL_TIMEOUT_MS));
        return true;
    }
}
