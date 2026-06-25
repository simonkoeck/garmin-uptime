# Connect IQ Store description

uptime is a minimalist watch face styled after a developer's terminal — monochrome by default, with nothing on screen you didn't ask for.

The time sits at the top like a shell prompt with a blinking cursor, followed by a clean console readout:

```
> 2:46

date   mon 15 jun
hr     72 bpm
rest   58 bpm
step   ▮▮▮▮▯▯▯▯▯▯  4280
bat    ▮▮▮▮▮▮▯▯▯▯  62%
```

**Make it yours.** Every row is configurable — pick what each of the five lines shows, or turn it off:

- date, heart rate, resting HR
- steps, floors, active minutes, calories, distance
- Body Battery, stress, Pulse Ox
- weather, altitude, notifications, connection status, battery

Metrics with a goal (steps, battery, Body Battery, floors, active minutes) draw as segmented progress bars; the rest as clean value rows. Distance, temperature and altitude follow your watch's own unit settings.

**Style it.**

- **Theme** — monochrome, green phosphor, or amber CRT
- **Prompt** — `>` `$` `#` `~` `:`
- **Cursor** — block, underscore, or pipe (blink optional)
- **Date** — weekday, ISO (`2026-06-25`), or numeric

Set in JetBrains Mono on a true-black background — easy on AMOLED battery, with a dimmed always-on (AOD) mode for burn-in safety.

Configure everything in **Garmin Connect → uptime → Settings**.
