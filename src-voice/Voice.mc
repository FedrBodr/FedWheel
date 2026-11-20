import Toybox.Audio;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Push-to-talk facade used by the dashboard (HomeView / HomeViewDelegate).
// Devices without a microphone API compile src-novoice/Voice.mc instead (same functions).
module Voice {
    var _ctl = null;

    function available() {
        return (Toybox has :Audio) && (Audio has :Capture);
    }

    function isActive() {
        return _ctl != null && _ctl.state != VS_IDLE;
    }

    function onStartKey() {
        if (_ctl == null) {
            _ctl = new VoiceController();
        }
        _ctl.onStartKey();
    }

    // true when consumed (voice flow cancelled / answered "no").
    function onBackKey() {
        return _ctl != null && _ctl.onBackKey();
    }

    function shutdown() {
        if (_ctl != null) {
            _ctl.shutdown();
        }
    }

    // Drawn over the dashboard after the layout.
    function draw(dc) {
        if (isActive()) {
            VoiceOverlay.draw(dc, _ctl);
        }
    }
}

// Riding-speed readable overlay for the 454 px round AMOLED (scales with the screen).
// Short states use a bottom band so the speed number stays visible; the reply uses the
// whole screen with a compact speed on top.
module VoiceOverlay {
    function draw(dc, ctl) {
        var st = ctl.state;
        if (st == VS_RESULT || st == VS_CONFIRM || st == VS_ERROR) {
            drawFull(dc, ctl, st);
        } else {
            drawBand(dc, ctl, st);
        }
    }

    function drawBand(dc, ctl, st) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var top = (h * 0.64).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, top, w, h - top);
        var s;
        var color;
        var font = Graphics.FONT_LARGE;
        if (st == VS_REC) {
            s = ctl.rez(Rez.Strings.Voice_Listening) + " " + ctl.recSeconds + " с";
            color = Graphics.COLOR_RED;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(6);
            dc.drawLine(w / 6, top, w * 5 / 6, top);
            dc.setPenWidth(1);
        } else if (st == VS_THINKING) {
            s = ctl.rez(Rez.Strings.Voice_Thinking) + " " + ctl.thinkSeconds() + " с";
            color = Graphics.COLOR_BLUE;
        } else if (st == VS_NOPORT) {
            s = ctl.rez(Rez.Strings.Voice_NoPhone);
            color = Graphics.COLOR_YELLOW;
            font = Graphics.FONT_MEDIUM;
        } else { // VS_FINISHING, VS_SENDING
            s = ctl.rez(Rez.Strings.Voice_Sending);
            color = Graphics.COLOR_BLUE;
        }
        var lines = fit(dc, s, [font, Graphics.FONT_SMALL], w * 3 / 4, h - top - h / 12);
        drawLines(dc, lines[0], lines[1], color, top + (h - top) * 2 / 5);
        // upload progress: while recording only when uploads lag behind the capture
        if ((st == VS_REC && ctl.lagging()) || ((st == VS_SENDING || st == VS_FINISHING) && ctl.total > 0)) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, top + (h - top) * 7 / 10, Graphics.FONT_TINY,
                ctl.rez(Rez.Strings.Voice_Sent) + " " + ctl.sent + "/" + ctl.total, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawFull(dc, ctl, st) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // compact speed so the rider still sees it
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h * 0.04).toNumber(), Graphics.FONT_NUMBER_MILD, speedText(), Graphics.TEXT_JUSTIFY_CENTER);

        var body = (st == VS_ERROR) ? ctl.errMsg : ctl.reply;
        if (body.length() == 0) {
            body = ctl.text;
        }
        var color = (st == VS_ERROR) ? Graphics.COLOR_RED : Graphics.COLOR_WHITE;
        var top = (h * 0.26).toNumber();
        var bottom = (st == VS_CONFIRM) ? (h * 0.72).toNumber() : (h * 0.84).toNumber();
        var fonts = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY];
        var res = fit(dc, body, fonts, w * 3 / 4, bottom - top);
        drawLines(dc, res[0], res[1], color, top + (bottom - top) / 2);

        if (st == VS_CONFIRM) {
            var hint = fit(dc, ctl.rez(Rez.Strings.Voice_ConfirmHint), [Graphics.FONT_SMALL, Graphics.FONT_TINY], w * 2 / 3, h * 2 / 9);
            drawLines(dc, hint[0], hint[1], Graphics.COLOR_YELLOW, (h * 0.83).toNumber());
        }
    }

    function speedText() {
        var s = WheelData.currentSpeed;
        if (s == null) {
            return "--";
        }
        return (s.toNumber() != null && s.toNumber() >= 10) ? s.toNumber().toString() : s.toString();
    }

    // Lines centred on cy (cy is the middle of the block).
    function drawLines(dc, lines, font, color, cy) {
        var lh = dc.getFontHeight(font);
        var y = cy - lines.size() * lh / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(dc.getWidth() / 2, y + i * lh, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Largest font whose wrapped text fits maxH; otherwise the smallest, cut with "…".
    // Returns [lines, font].
    function fit(dc, s, fonts, maxW, maxH) {
        var lines = null;
        var font = null;
        for (var i = 0; i < fonts.size(); i++) {
            font = fonts[i];
            lines = wrap(dc, s, font, maxW);
            if (lines.size() * dc.getFontHeight(font) <= maxH) {
                return [lines, font];
            }
        }
        var maxLines = maxH / dc.getFontHeight(font);
        if (maxLines < 1) {
            maxLines = 1;
        }
        if (lines.size() > maxLines) {
            lines = lines.slice(0, maxLines);
            lines[maxLines - 1] = lines[maxLines - 1] + "…";
        }
        return [lines, font];
    }

    // Greedy word wrap; honours "\n"; breaks over-long words (from FedVoice MainView).
    function wrap(dc, s, font, maxW) {
        var out = [];
        var chars = s.toCharArray();
        var line = "";
        var word = "";
        for (var i = 0; i <= chars.size(); i++) {
            var c = (i < chars.size()) ? chars[i] : '\n';
            if (c == ' ' || c == '\n') {
                var cand = line.length() == 0 ? word : line + " " + word;
                if (dc.getTextWidthInPixels(cand, font) <= maxW) {
                    line = cand;
                } else {
                    if (line.length() > 0) { out.add(line); }
                    line = word;
                    while (line.length() > 1 && dc.getTextWidthInPixels(line, font) > maxW) {
                        var n = line.length() - 1;
                        while (n > 1 && dc.getTextWidthInPixels(line.substring(0, n), font) > maxW) { n--; }
                        out.add(line.substring(0, n));
                        line = line.substring(n, line.length());
                    }
                }
                word = "";
                if (c == '\n') {
                    out.add(line);
                    line = "";
                }
            } else {
                word += c.toString();
            }
        }
        if (out.size() > 0 && out[out.size() - 1].length() == 0 && s.length() > 0) {
            out = out.slice(0, out.size() - 1);
        }
        return out;
    }
}
