import Toybox.Test;
import Toybox.Lang;

module VoiceUploadTest {
    function bytes(from as Number, n as Number) as ByteArray {
        var b = new [n]b;
        for (var i = 0; i < n; i++) {
            b[i] = (from + i) % 256;
        }
        return b;
    }

    function started(max as Number) as VoiceUpload {
        var u = new VoiceUpload(max);
        var a = u.next() as Dictionary;
        Test.assert(a[:kind] == :start);
        u.onOk("s1");
        return u;
    }

    (:test)
    function startsSessionFirstEvenWithoutAudio(logger as Logger) as Boolean {
        var u = new VoiceUpload(10);
        var a = u.next() as Dictionary;
        Test.assert(a[:kind] == :start);
        Test.assert(u.busy());
        Test.assert(u.next() == null); // one request in flight at a time
        Test.assert(u.onOk("abc") == :start);
        Test.assert((u.sid as String).equals("abc"));
        Test.assert(u.next() == null); // nothing buffered yet
        return true;
    }

    (:test)
    function buffersWhileSessionIdIsPending(logger as Logger) as Boolean {
        var u = new VoiceUpload(10);
        u.next(); // start in flight
        u.append(bytes(0, 25));
        Test.assert(u.next() == null);
        u.onOk("s");
        var a = u.next() as Dictionary;
        Test.assert(a[:kind] == :chunk);
        Test.assertEqual(a[:seq], 0);
        Test.assertEqual((a[:data] as ByteArray).size(), 10);
        return true;
    }

    (:test)
    function sendsOnlyFullSlicesWhileRecording(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 9));
        Test.assert(u.next() == null);
        u.append(bytes(9, 1));
        var a = u.next() as Dictionary;
        Test.assert(a[:kind] == :chunk);
        Test.assertEqual((a[:data] as ByteArray).size(), 10);
        return true;
    }

    (:test)
    function ackDropsSliceAndAdvancesSeq(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 25));
        var a = u.next() as Dictionary;
        Test.assertEqual(a[:seq], 0);
        Test.assertEqual(u.unsent(), 25); // kept until acknowledged
        Test.assert(u.onOk(null) == :chunk);
        Test.assertEqual(u.unsent(), 15);
        Test.assertEqual(u.acked(), 1);
        a = u.next() as Dictionary;
        Test.assertEqual(a[:seq], 1);
        var d = a[:data] as ByteArray;
        Test.assertEqual(d[0], 10); // consecutive
        Test.assertEqual(d[9], 19);
        u.onOk(null);
        Test.assertEqual(u.unsent(), 5);
        Test.assert(u.next() == null); // 5 < 10 and still recording
        Test.assertEqual(u.bytes(), 25);
        return true;
    }

    (:test)
    function flushesRemainderOnFinishThenEnds(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 23));
        u.next();
        u.onOk(null);
        u.next();
        u.onOk(null);
        u.finish();
        var a = u.next() as Dictionary;
        Test.assert(a[:kind] == :chunk);
        Test.assertEqual(a[:seq], 2);
        var d = a[:data] as ByteArray;
        Test.assertEqual(d.size(), 3);
        Test.assertEqual(d[0], 20);
        u.onOk(null);
        a = u.next() as Dictionary;
        Test.assert(a[:kind] == :end);
        Test.assert(!u.ended());
        Test.assert(u.onOk(null) == :end);
        Test.assert(u.ended());
        Test.assert(u.next() == null);
        return true;
    }

    (:test)
    function endWaitsForInFlightSlice(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 10));
        u.next(); // chunk 0 in flight
        u.finish();
        Test.assert(u.next() == null);
        u.onOk(null);
        Test.assert((u.next() as Dictionary)[:kind] == :end);
        return true;
    }

    (:test)
    function finishWithoutAudioStillEnds(logger as Logger) as Boolean {
        var u = started(10);
        u.finish();
        Test.assert((u.next() as Dictionary)[:kind] == :end);
        return true;
    }

    (:test)
    function sliceFixedWhileInFlightEvenIfMoreArrives(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 4));
        u.finish();
        var a = u.next() as Dictionary;
        Test.assertEqual((a[:data] as ByteArray).size(), 4);
        u.append(bytes(4, 3)); // late capture data after stop
        u.onOk(null);
        a = u.next() as Dictionary;
        Test.assertEqual(a[:seq], 1);
        Test.assertEqual((a[:data] as ByteArray)[0], 4);
        return true;
    }

    (:test)
    function retriesSameSeqTwiceThenGivesUp(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 20));
        var a = u.next() as Dictionary;
        Test.assert(u.onFail());
        a = u.next() as Dictionary;
        Test.assertEqual(a[:seq], 0);
        Test.assertEqual((a[:data] as ByteArray)[0], 0);
        Test.assert(u.onFail());
        Test.assertEqual((u.next() as Dictionary)[:seq], 0);
        Test.assert(!u.onFail());
        return true;
    }

    (:test)
    function successResetsRetryCount(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 30));
        u.next();
        u.onFail();
        u.next();
        u.onFail();
        u.next();
        u.onOk(null);
        u.next();
        Test.assert(u.onFail());
        return true;
    }

    (:test)
    function restartsFreshSessionOnlyBeforeAnythingAcked(logger as Logger) as Boolean {
        var u = started(10);
        u.append(bytes(0, 15));
        u.next();
        u.onFail();
        Test.assert(u.restartable());
        Test.assert(u.restart());
        Test.assert(u.sid == null);
        Test.assert((u.next() as Dictionary)[:kind] == :start);
        u.onOk("s2");
        var a = u.next() as Dictionary;
        Test.assertEqual(a[:seq], 0);
        Test.assertEqual((a[:data] as ByteArray)[0], 0);
        u.onOk(null);
        Test.assert(!u.restartable());
        Test.assert(!u.restart());
        return true;
    }

    (:test)
    function countsSlicesForProgress(logger as Logger) as Boolean {
        var u = started(10);
        Test.assertEqual(u.slices(), 0);
        u.append(bytes(0, 25));
        Test.assertEqual(u.slices(), 3);
        u.next();
        u.onOk(null);
        Test.assertEqual(u.acked(), 1);
        Test.assertEqual(u.slices(), 3);
        return true;
    }
}
