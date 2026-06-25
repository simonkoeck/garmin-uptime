using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.UserProfile;
using Toybox.Application as App;
using Toybox.SensorHistory;
using Toybox.Weather;

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
    const BAR_OFF  = 0x383838;   // progress bar, empty segment
    const AOD_TIME = 0x4A4A4A;   // always-on dim (kept neutral for burn-in safety)

    // Palette — set per update from the "theme" setting (see applyTheme).
    var mAccent = 0xFFFFFF;  // prompt + time + cursor + filled bar
    var mValue  = 0xC8C8C8;  // row values
    var mLabel  = 0x5A5A5A;  // row labels
    var mCursor = 0x6A6A6A;  // blinking cursor (muted accent)

    // segmented progress bar geometry (rects with gaps for padding)
    const BAR_CELLS = 10;
    const BAR_SEG   = 7;         // segment width
    const BAR_GAP   = 3;         // gap between segments
    const BAR_H     = 14;        // segment height

    var mMonoLg;   // JetBrains Mono, large (prompt/time)
    var mMono;     // JetBrains Mono, small (rows)
    var mCx;
    var mCy;
    var mScale = 1.0; // screen width / 390, to scale bar/cursor pixels
    var mLowPower = false;
    var mBurnIn = false;
    var mCurX = 0; // cursor rect, for the blink in onPartialUpdate
    var mCurY = 0;
    var mCurW = 0;
    var mCurH = 0;

    // Appearance settings, refreshed each onUpdate.
    var mPrompt = "> ";        // prompt symbol + trailing space
    var mCursorStyle = 0;      // 0 block, 1 underscore, 2 pipe
    var mCursorBlink = true;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Gfx.Dc) as Void {
        mMonoLg = Ui.loadResource(Rez.Fonts.LumenMonoLg);
        mMono   = Ui.loadResource(Rez.Fonts.LumenMono);
        mCx = dc.getWidth() / 2;
        mCy = dc.getHeight() / 2;
        mScale = dc.getWidth() / 390.0;
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

        readSettings();

        var clock = Sys.getClockTime();
        var h = dc.getHeight();

        if (mLowPower && mBurnIn) {
            drawAlwaysOn(dc, clock, h);
        } else {
            drawTerminal(dc, clock, h);
        }
    }

    // Per-second cursor blink while awake (clipped, so it's cheap).
    // A non-blinking cursor is drawn once in drawTerminal and needs no redraw.
    function onPartialUpdate(dc as Gfx.Dc) as Void {
        if (mLowPower || mCurW <= 0 || !mCursorBlink) {
            return;
        }
        blinkCursor(dc, Sys.getClockTime().sec % 2 == 0);
    }

    // Refresh appearance settings + palette from app properties.
    function readSettings() as Void {
        mCursorBlink = slot("cursorBlink", true);
        mCursorStyle = slot("cursorStyle", 0);

        var pc = slot("promptChar", 0);
        var sym = ">";
        if    (pc == 1) { sym = "$"; }
        else if (pc == 2) { sym = "#"; }
        else if (pc == 3) { sym = "~"; }
        else if (pc == 4) { sym = ":"; }
        mPrompt = sym + " ";

        var t = slot("theme", 0);
        if (t == 1) {            // green phosphor
            mAccent = 0x33FF66; mValue = 0x29C24F; mLabel = 0x1C7A33; mCursor = 0x1FA33D;
        } else if (t == 2) {     // amber CRT
            mAccent = 0xFFB000; mValue = 0xC88400; mLabel = 0x7A5200; mCursor = 0xA66E00;
        } else {                 // monochrome (original)
            mAccent = 0xFFFFFF; mValue = 0xC8C8C8; mLabel = 0x5A5A5A; mCursor = 0x6A6A6A;
        }
    }

    function drawTerminal(dc as Gfx.Dc, clock, h as Lang.Number) as Void {
        var cw = dc.getTextWidthInPixels("0", mMono); // monospace cell width
        // Label column is 7 cells wide (6 chars + 1 gap) so even a full-width
        // label like "stress" doesn't touch its value. Bars then occupy barW,
        // then a 1-cell gap, then the value.
        var barW = BAR_CELLS * (BAR_SEG * mScale).toNumber()
                 + (BAR_CELLS - 1) * (BAR_GAP * mScale).toNumber();
        var labelW = cw * 7;
        var barValX = labelW + barW + cw; // value x for bar rows (relative to lx)

        // prompt + time
        var hour = clock.hour;
        var is24 = Sys.getDeviceSettings().is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var timeStr = mPrompt + (is24 ? hour.format("%02d") : hour.format("%d"))
                    + ":" + clock.min.format("%02d");

        // Resolve the five slots up front so we can centre on the ACTUAL widest
        // row (rather than a worst-case reservation, which looked left-heavy when
        // values are short). Each entry is [label, value, frac|null].
        var ai = ActivityMonitor.getInfo();
        var ids = [
            slot("slot1", FIELD_DATE),  slot("slot2", FIELD_HR),
            slot("slot3", FIELD_REST),  slot("slot4", FIELD_STEPS),
            slot("slot5", FIELD_BATTERY)
        ];
        var rows = new [5];
        var clw = dc.getTextWidthInPixels("0", mMonoLg);
        var blockW = dc.getTextWidthInPixels(timeStr, mMonoLg) + clw; // + cursor
        for (var i = 0; i < 5; i++) {
            var r = resolveField(ids[i], ai);
            rows[i] = r;
            if (r != null) {
                var valW = dc.getTextWidthInPixels(r[1], mMono);
                var rowW = (r[2] == null) ? labelW + valW : barValX + valW;
                if (rowW > blockW) { blockW = rowW; }
            }
        }
        var lx = (mCx * 2 - blockW) / 2;
        if (lx < 8) { lx = 8; }

        var ty = (h * 0.28).toNumber();
        dc.setColor(mAccent, BG);
        dc.drawText(lx, ty, mMonoLg, timeStr,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);

        // inline cursor, right after the time (reads as a live prompt). Geometry
        // depends on the cursor-style setting; blinkCursor just fills the rect.
        var fullH = (40 * mScale).toNumber();
        mCurX = lx + dc.getTextWidthInPixels(timeStr, mMonoLg) + (clw * 0.3).toNumber();
        if (mCursorStyle == 1) {            // underscore — thin, at the baseline
            var fh = dc.getFontHeight(mMonoLg);
            mCurW = (clw * 0.7).toNumber();
            mCurH = (5 * mScale).toNumber();
            if (mCurH < 3) { mCurH = 3; }
            mCurY = ty + fh / 2 - (4 * mScale).toNumber() - mCurH / 2;
        } else if (mCursorStyle == 2) {     // pipe — thin, full height
            mCurW = (clw * 0.16).toNumber();
            if (mCurW < 2) { mCurW = 2; }
            mCurH = fullH;
            mCurY = ty;
        } else {                            // block (original)
            mCurW = (clw * 0.6).toNumber();
            mCurH = fullH;
            mCurY = ty;
        }
        blinkCursor(dc, mCursorBlink ? (clock.sec % 2 == 0) : true);

        // draw the resolved rows, evenly spaced in the original 0.44..0.77 band
        for (var i = 0; i < 5; i++) {
            var r = rows[i];
            if (r == null) { continue; } // slot is off
            var y = (h * (0.44 + i * 0.0825)).toNumber();
            if (r[2] == null) {
                drawRow(dc, lx, cw, y, r[0], r[1]);
            } else {
                drawBar(dc, lx, cw, y, r[0], r[2], r[1]);
            }
        }
    }

    // Field ids — must match the listEntry values in resources/settings.
    const FIELD_OFF          = 0;
    const FIELD_DATE         = 1;
    const FIELD_HR           = 2;
    const FIELD_REST         = 3;
    const FIELD_STEPS        = 4;   // bar
    const FIELD_BATTERY      = 5;   // bar
    const FIELD_STRESS       = 6;
    const FIELD_BODY_BATTERY = 7;   // bar
    const FIELD_FLOORS       = 8;   // bar
    const FIELD_ACTIVE       = 9;   // bar
    const FIELD_CALORIES     = 10;
    const FIELD_DISTANCE     = 11;
    const FIELD_WEATHER      = 12;
    const FIELD_NOTIFS       = 13;
    const FIELD_STATUS       = 14;
    const FIELD_ALTITUDE     = 15;
    const FIELD_SPO2         = 16;  // bar

    // Read a property, falling back to its default if unset. Used for both the
    // numeric field/appearance settings and the boolean cursor-blink toggle.
    function slot(key, dflt) {
        var v = App.Properties.getValue(key);
        return (v == null) ? dflt : v;
    }

    // The "date" field, formatted per the dateFmt setting.
    function dateString() {
        var fmt = slot("dateFmt", 0);
        if (fmt == 1) {                     // ISO 2026-06-25
            var gs = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            return gs.year.format("%04d") + "-" + gs.month.format("%02d") + "-" + gs.day.format("%02d");
        } else if (fmt == 2) {              // numeric 15.06
            var gn = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            return gn.day.format("%02d") + "." + gn.month.format("%02d");
        }
        var g = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);  // weekday mon 15 jun
        return Lang.format("$1$ $2$ $3$", [
            g.day_of_week, g.day.format("%02d"), g.month
        ]).toLower();
    }

    // Resolve a field id to [label, value, frac]: frac == null means a plain
    // value row, a Float (0..1) means a progress bar. Returns null when the slot
    // is off. Drawing is done by the caller so it can centre on actual widths.
    function resolveField(id, ai) {
        switch (id) {
            case FIELD_DATE:
                return ["date", dateString(), null];

            case FIELD_HR: {
                var act = Activity.getActivityInfo();
                var cur = (act != null && act.currentHeartRate != null) ? act.currentHeartRate : null;
                return ["hr", (cur != null) ? cur.format("%d") + " bpm" : "--", null];
            }

            case FIELD_REST: {
                var prof = UserProfile.getProfile();
                // averageRestingHeartRate is the 7-day auto-computed value that
                // actually updates daily; restingHeartRate is the static
                // user-configured one. Fall back to the configured value if unset.
                var rest = null;
                if (prof != null) {
                    rest = (prof.averageRestingHeartRate != null) ? prof.averageRestingHeartRate : prof.restingHeartRate;
                }
                return ["rest", (rest != null) ? rest.format("%d") + " bpm" : "--", null];
            }

            case FIELD_STEPS: {
                var steps = (ai != null && ai.steps != null) ? ai.steps : 0;
                var goal = (ai != null && ai.stepGoal != null && ai.stepGoal > 0) ? ai.stepGoal : 10000;
                return ["step", steps.format("%d"), steps.toFloat() / goal];
            }

            case FIELD_BATTERY: {
                var batt = Sys.getSystemStats().battery;
                return ["bat", batt.toNumber().format("%d") + "%", batt / 100.0];
            }

            case FIELD_STRESS: {
                var s = getStress();
                return ["stress", (s != null) ? s.format("%d") : "--", null];
            }

            case FIELD_BODY_BATTERY: {
                var b = getBodyBattery();
                return ["body", (b != null) ? b.format("%d") : "--", (b != null) ? b / 100.0 : null];
            }

            case FIELD_FLOORS: {
                var f = (ai != null && ai.floorsClimbed != null) ? ai.floorsClimbed : 0;
                var fg = (ai != null && ai.floorsClimbedGoal != null && ai.floorsClimbedGoal > 0) ? ai.floorsClimbedGoal : 10;
                return ["stairs", f.format("%d"), f.toFloat() / fg];
            }

            case FIELD_ACTIVE: {
                var m = 0;
                if (ai != null && ai.activeMinutesWeek != null && ai.activeMinutesWeek.total != null) {
                    m = ai.activeMinutesWeek.total;
                }
                var mg = (ai != null && ai.activeMinutesWeekGoal != null && ai.activeMinutesWeekGoal > 0) ? ai.activeMinutesWeekGoal : 150;
                return ["active", m.format("%d"), m.toFloat() / mg];
            }

            case FIELD_CALORIES: {
                var cal = (ai != null && ai.calories != null) ? ai.calories : 0;
                return ["cal", cal.format("%d"), null];
            }

            case FIELD_DISTANCE: {
                var cm = (ai != null && ai.distance != null) ? ai.distance : 0;
                var valStr;
                if (Sys.getDeviceSettings().distanceUnits == Sys.UNIT_STATUTE) {
                    valStr = (cm / 160934.4).format("%.1f") + " mi";
                } else {
                    valStr = (cm / 100000.0).format("%.1f") + " km";
                }
                return ["dist", valStr, null];
            }

            case FIELD_WEATHER: {
                var t = null;
                if (Toybox has :Weather) {
                    var cond = Weather.getCurrentConditions();
                    if (cond != null && cond.temperature != null) {
                        t = cond.temperature; // degrees Celsius
                    }
                }
                var valStr;
                if (t == null) {
                    valStr = "--";
                } else if (Sys.getDeviceSettings().temperatureUnits == Sys.UNIT_STATUTE) {
                    valStr = (t * 9.0 / 5.0 + 32).format("%d") + "f";
                } else {
                    valStr = t.format("%d") + "c";
                }
                return ["temp", valStr, null];
            }

            case FIELD_NOTIFS: {
                var n = Sys.getDeviceSettings().notificationCount;
                return ["notif", (n != null) ? n.format("%d") : "0", null];
            }

            case FIELD_STATUS: {
                var ds = Sys.getDeviceSettings();
                var s = ds.phoneConnected ? "bt" : "--";
                if (ds.doNotDisturb) { s += " dnd"; }
                if (ds.alarmCount != null && ds.alarmCount > 0) { s += " al"; }
                return ["conn", s, null];
            }

            case FIELD_ALTITUDE: {
                var act = Activity.getActivityInfo();
                var alt = (act != null && act.altitude != null) ? act.altitude : null; // metres
                var valStr;
                if (alt == null) {
                    valStr = "--";
                } else if (Sys.getDeviceSettings().elevationUnits == Sys.UNIT_STATUTE) {
                    valStr = (alt * 3.28084).format("%d") + " ft";
                } else {
                    valStr = alt.format("%d") + " m";
                }
                return ["alt", valStr, null];
            }

            case FIELD_SPO2: {
                var o = getSpo2();
                return ["spo2", (o != null) ? o.format("%d") : "--", (o != null) ? o / 100.0 : null];
            }
        }
        return null; // FIELD_OFF or unknown
    }

    // Most-recent stress score, or null when unsupported/unavailable.
    function getStress() {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getStressHistory)) {
            return null;
        }
        var iter = SensorHistory.getStressHistory({
            :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST
        });
        var s = (iter != null) ? iter.next() : null;
        return (s != null && s.data != null) ? s.data : null;
    }

    // Most-recent Body Battery level (0–100), or null when unsupported.
    function getBodyBattery() {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }
        var iter = SensorHistory.getBodyBatteryHistory({
            :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST
        });
        var s = (iter != null) ? iter.next() : null;
        return (s != null && s.data != null) ? s.data : null;
    }

    // Most-recent blood-oxygen % (0–100), or null when unsupported.
    function getSpo2() {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getOxygenSaturationHistory)) {
            return null;
        }
        var iter = SensorHistory.getOxygenSaturationHistory({
            :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST
        });
        var s = (iter != null) ? iter.next() : null;
        return (s != null && s.data != null) ? s.data : null;
    }

    function drawRow(dc as Gfx.Dc, lx as Lang.Number, cw as Lang.Number, y as Lang.Number, label as Lang.String, value as Lang.String) as Void {
        var v = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(mLabel, BG);
        dc.drawText(lx, y, mMono, label, v);
        dc.setColor(mValue, BG);
        dc.drawText(lx + cw * 7, y, mMono, value, v); // align values at column 7
    }

    // A label + a segmented progress bar (rects with gaps) + a value.
    function drawBar(dc as Gfx.Dc, lx as Lang.Number, cw as Lang.Number, y as Lang.Number, label as Lang.String, frac, value as Lang.String) as Void {
        if (frac < 0) { frac = 0.0; }
        if (frac > 1) { frac = 1.0; }
        var v = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;

        var filled = (frac * BAR_CELLS + 0.5).toNumber();
        if (filled > BAR_CELLS) { filled = BAR_CELLS; }

        dc.setColor(mLabel, BG);
        dc.drawText(lx, y, mMono, label, v);

        var seg = (BAR_SEG * mScale).toNumber();
        var gap = (BAR_GAP * mScale).toNumber();
        var bh = (BAR_H * mScale).toNumber();
        var barX = lx + cw * 7;
        var step = seg + gap;
        var top = y - bh / 2;
        for (var i = 0; i < BAR_CELLS; i++) {
            dc.setColor(i < filled ? mAccent : BAR_OFF, BG);
            dc.fillRectangle(barX + i * step, top, seg, bh);
        }

        var barW = BAR_CELLS * seg + (BAR_CELLS - 1) * gap;
        dc.setColor(mValue, BG);
        dc.drawText(barX + barW + cw, y, mMono, value, v);
    }

    function blinkCursor(dc as Gfx.Dc, on as Lang.Boolean) as Void {
        dc.setClip(mCurX, mCurY - mCurH / 2, mCurW, mCurH);
        dc.setColor(BG, BG);
        dc.clear();
        if (on) {
            dc.setColor(mCursor, BG);
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
        var str = mPrompt + (is24 ? hour.format("%02d") : hour.format("%d"))
                + ":" + clock.min.format("%02d");

        dc.setColor(AOD_TIME, BG);
        dc.drawText(mCx + shift, (h * 0.5).toNumber() + shift, mMonoLg, str,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function onHide() as Void {
    }
}
