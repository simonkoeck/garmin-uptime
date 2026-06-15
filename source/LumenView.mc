using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.UserProfile;

// Lumen — a monochrome "terminal" watch face.
//
//   > 2:28
//
//   date  mon 15 jun
//   hr    72
//   step  8420
//   bat   50%
//   █                  <- block cursor, blinks 1 Hz while the wrist is raised
//
// JetBrains Mono on true black; bright values, dim labels, no accent colour.
// A dimmed, burn-in-safe rendering is used for always-on.
class LumenView extends Ui.WatchFace {

    const BG       = 0x000000;
    const HOUR     = 0xFFFFFF;   // prompt + time + cursor
    const T_LABEL  = 0x5A5A5A;   // row labels
    const T_VALUE  = 0xC8C8C8;   // row values
    const BAR_ON   = 0xE0E0E0;   // progress bar, filled
    const BAR_OFF  = 0x383838;   // progress bar, empty segment
    const CURSOR   = 0x6A6A6A;   // blinking cursor (muted, not full white)
    const AOD_TIME = 0x4A4A4A;   // always-on dim

    // segmented progress bar geometry (rects with gaps for padding)
    const BAR_CELLS = 10;
    const BAR_SEG   = 7;         // segment width
    const BAR_GAP   = 3;         // gap between segments
    const BAR_H     = 14;        // segment height

    var mMonoLg;   // JetBrains Mono, large (prompt/time)
    var mMono;     // JetBrains Mono, small (rows)
    var mCx;
    var mCy;
    var mLowPower = false;
    var mBurnIn = false;
    var mCurX = 0; // cursor rect, for the blink in onPartialUpdate
    var mCurY = 0;
    var mCurW = 0;
    var mCurH = 0;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Gfx.Dc) as Void {
        mMonoLg = Ui.loadResource(Rez.Fonts.LumenMonoLg);
        mMono   = Ui.loadResource(Rez.Fonts.LumenMono);
        mCx = dc.getWidth() / 2;
        mCy = dc.getHeight() / 2;
        mBurnIn = Sys.getDeviceSettings().requiresBurnInProtection;
    }

    function onShow() as Void {
    }

    function onEnterSleep() as Void {
        mLowPower = true;
        Ui.requestUpdate();
    }

    function onExitSleep() as Void {
        mLowPower = false;
        Ui.requestUpdate();
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.clearClip();
        dc.setColor(Gfx.COLOR_WHITE, BG);
        dc.clear();

        var clock = Sys.getClockTime();
        var h = dc.getHeight();

        if (mLowPower && mBurnIn) {
            drawAlwaysOn(dc, clock, h);
        } else {
            drawTerminal(dc, clock, h);
        }
    }

    // Per-second cursor blink while awake (clipped, so it's cheap).
    function onPartialUpdate(dc as Gfx.Dc) as Void {
        if (mLowPower || mCurW <= 0) {
            return;
        }
        blinkCursor(dc, Sys.getClockTime().sec % 2 == 0);
    }

    function drawTerminal(dc as Gfx.Dc, clock, h as Lang.Number) as Void {
        var cw = dc.getTextWidthInPixels("0", mMono); // monospace cell width
        // Centre the data block horizontally: 6 label cols + bar + 1 gap col +
        // 5 value cols. Also guarantees values can't overflow the right edge.
        var barW = BAR_CELLS * BAR_SEG + (BAR_CELLS - 1) * BAR_GAP;
        var blockW = cw * 6 + barW + cw + cw * 5;
        var lx = (mCx * 2 - blockW) / 2;
        if (lx < 8) { lx = 8; }

        // prompt + time
        var hour = clock.hour;
        var is24 = Sys.getDeviceSettings().is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var timeStr = "> " + (is24 ? hour.format("%02d") : hour.format("%d"))
                    + ":" + clock.min.format("%02d");
        var ty = (h * 0.28).toNumber();
        dc.setColor(HOUR, BG);
        dc.drawText(lx, ty, mMonoLg, timeStr,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);

        // inline blinking cursor, right after the time (reads as a live prompt)
        var clw = dc.getTextWidthInPixels("0", mMonoLg);
        mCurX = lx + dc.getTextWidthInPixels(timeStr, mMonoLg) + (clw * 0.3).toNumber();
        mCurY = ty;
        mCurW = (clw * 0.6).toNumber();
        mCurH = 40;
        blinkCursor(dc, clock.sec % 2 == 0);

        // data rows
        var g = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [
            g.day_of_week, g.day.format("%02d"), g.month
        ]).toLower();

        var ai = ActivityMonitor.getInfo();
        var steps = (ai != null && ai.steps != null) ? ai.steps : 0;
        var goal = (ai != null && ai.stepGoal != null && ai.stepGoal > 0) ? ai.stepGoal : 10000;
        var batt = Sys.getSystemStats().battery;

        var act = Activity.getActivityInfo();
        var cur = (act != null && act.currentHeartRate != null) ? act.currentHeartRate : null;
        var prof = UserProfile.getProfile();
        var rest = (prof != null && prof.restingHeartRate != null) ? prof.restingHeartRate : null;
        var hrStr   = (cur  != null) ? cur.format("%d") + " bpm"  : "--";
        var restStr = (rest != null) ? rest.format("%d") + " bpm" : "--";

        drawRow(dc, lx, cw, (h * 0.44).toNumber(), "date", dateStr);
        drawRow(dc, lx, cw, (h * 0.52).toNumber(), "hr",   hrStr);
        drawRow(dc, lx, cw, (h * 0.60).toNumber(), "rest", restStr);
        drawBar(dc, lx, cw, (h * 0.69).toNumber(), "step", steps.toFloat() / goal, steps.format("%d"));
        drawBar(dc, lx, cw, (h * 0.77).toNumber(), "bat",  batt / 100.0, batt.toNumber().format("%d") + "%");
    }

    function drawRow(dc as Gfx.Dc, lx as Lang.Number, cw as Lang.Number, y as Lang.Number, label as Lang.String, value as Lang.String) as Void {
        var v = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(T_LABEL, BG);
        dc.drawText(lx, y, mMono, label, v);
        dc.setColor(T_VALUE, BG);
        dc.drawText(lx + cw * 6, y, mMono, value, v); // align values at column 6
    }

    // A label + a segmented progress bar (rects with gaps) + a value.
    function drawBar(dc as Gfx.Dc, lx as Lang.Number, cw as Lang.Number, y as Lang.Number, label as Lang.String, frac, value as Lang.String) as Void {
        if (frac < 0) { frac = 0.0; }
        if (frac > 1) { frac = 1.0; }
        var v = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;

        var filled = (frac * BAR_CELLS + 0.5).toNumber();
        if (filled > BAR_CELLS) { filled = BAR_CELLS; }

        dc.setColor(T_LABEL, BG);
        dc.drawText(lx, y, mMono, label, v);

        var barX = lx + cw * 6;
        var step = BAR_SEG + BAR_GAP;
        var top = y - BAR_H / 2;
        for (var i = 0; i < BAR_CELLS; i++) {
            dc.setColor(i < filled ? BAR_ON : BAR_OFF, BG);
            dc.fillRectangle(barX + i * step, top, BAR_SEG, BAR_H);
        }

        var barW = BAR_CELLS * BAR_SEG + (BAR_CELLS - 1) * BAR_GAP;
        dc.setColor(T_VALUE, BG);
        dc.drawText(barX + barW + cw, y, mMono, value, v);
    }

    function blinkCursor(dc as Gfx.Dc, on as Lang.Boolean) as Void {
        dc.setClip(mCurX, mCurY - mCurH / 2, mCurW, mCurH);
        dc.setColor(BG, BG);
        dc.clear();
        if (on) {
            dc.setColor(CURSOR, BG);
            dc.fillRectangle(mCurX, mCurY - mCurH / 2, mCurW, mCurH);
        }
        dc.clearClip();
    }

    // Dimmed, burn-in-safe rendering for always-on: just the prompt + time,
    // shifted a few pixels on a slow cycle.
    function drawAlwaysOn(dc as Gfx.Dc, clock, h as Lang.Number) as Void {
        var shift = (clock.min % 4) - 2;

        var hour = clock.hour;
        var is24 = Sys.getDeviceSettings().is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var str = "> " + (is24 ? hour.format("%02d") : hour.format("%d"))
                + ":" + clock.min.format("%02d");

        dc.setColor(AOD_TIME, BG);
        dc.drawText(mCx + shift, (h * 0.5).toNumber() + shift, mMonoLg, str,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function onHide() as Void {
    }
}
