// Stub for watches without Audio.Capture (built instead of src-voice/, see monkey.jungle).
// START keeps the legacy horn/light behaviour there (StartAction.resolve falls back to horn).
module Voice {
    function available() { return false; }
    function isActive() { return false; }
    function onStartKey() { }
    function onBackKey() { return false; }
    function shutdown() { }
    function draw(dc) { }
}
