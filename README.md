# Swarm for macOS

A macOS screensaver that recreates `swarm`, the X11 screensaver written by Jeff
Butterworth and long shipped with xlock and XScreenSaver.

One wasp wanders the screen. A hundred bees chase it, always accelerating
towards it and never slowing down, so they overshoot, swing back, and orbit in
a knot of light trails that keeps reshaping itself.

Written in Swift against Apple's ScreenSaver framework. 

## Requirements

- macOS 11 or later
- The Swift compiler, from either Xcode or the Command Line Tools
  (`xcode-select --install`)

The build produces a universal binary, so the same bundle runs on Apple silicon
and on Intel.

## Install

```sh
make install
```

That builds `build/Swarm.saver` and copies it to `~/Library/Screen Savers`,
which installs it for your account only. 

Then open **System Settings > Wallpaper** and click on the **Screen Saver** button, move your mouse to the bottom half of the dialog box, scroll down past Apple's own screensavers, and choose **Swarm**. Third party savers are grouped near the bottom of the list, under a heading such as "Other". (If you're not using macOS Tahoe, these instructions may not be quite correct annoyingly.)

To upgrade if there are any future updates, git pull and use:

```sh
make reinstall
```

This runs the same install process, but it also clears the two caches that otherwise keep the previous install running.

To install for everyone on the Mac instead, copy the bundle yourself:

```sh
make
sudo cp -R build/Swarm.saver "/Library/Screen Savers/"
```

## Uninstall

```sh
make uninstall
```

Or drag `Swarm.saver` out of `~/Library/Screen Savers` and into the Bin.

## Options

Open **System Settings > Wallpaper** and click on the **Screen Saver** button, click **Options**.

| Setting | What it does |
| --- | --- |
| Bees | How many insects chase the wasp. 5 to 400, default 100. |
| Trail length | How many past positions each trail keeps. 2 to 48, default 14, my preference 10. |
| Speed | How fast the swarm moves. 0.30x to 3.00x, default 1.00x. Slower is also a little straighter between turns, which tightens the swarm; use Gravity to put that back if you want it. |
| Depth | 1.0 is the 2d swarm which replicates the original screensaver. Above a value of 1.0, the insects fly in three dimensions and the world turns slowly. 1.0 to 3.5, default 2.5. |
| Gravity | How hard the bees are pulled towards the wasp, and so how tightly the swarm holds. 0.4 to 2.5, default 1.0, my preference 1.20. |
| Colours | Classic, Rainbow, Honey or Monochrome. |
| Fade the trails out | Fades the old end of each trail instead of drawing it solid. |

Speed and Gravity are multipliers, so their sliders run on a log scale over a
range symmetric about 1.0.

Colour schemes:

- **Classic** gives the whole swarm one hue that drifts slowly round the colour wheel, with a white wasp. This is closest to the original screensaver on a colour display.
- **Rainbow** gives every bee its own hue.
- **Honey** is amber bees behind a white wasp.
- **Monochrome** is white on black, the way it looked on a mono X terminal.

Settings are stored per user with `ScreenSaverDefaults`, under the module name
`ukcolumn.Swarm`.

## How it works

Every frame, at 60 frames a second:

1. The wasp adds a random acceleration to its velocity, capped per axis. The
   kick is a third of that cap, so it darts rather than drifting: its heading
   is unrecognisable a third of a second later, and it covers roughly a fifth
   of the screen width every second. It bounces off an invisible fence set in
   from the edges, not off the edges themselves.
2. Each bee accelerates towards the wasp by a fixed amount, whatever the
   distance between them, plus a little noise. Gravity scales that amount, and
   since orbit radius goes as speed squared over acceleration, turning it up
   pulls the swarm in. Nothing pulls a bee back, so it overshoots and orbits. Its speed is capped the same way, about half again as high as the wasp's. That gap is deliberate: the bees can catch the wasp, but not always, so now and then it gets away, the swarm trails out into a tail behind it, and then gathers back into a knot.
3. Bees bounce off the boundary of the world. The fence keeps the wasp away
   from the sides, and this catches the bees that swing out past it, so none of
   the swarm is ever drawn off the display.
4. Every insect pushes its new position into a small ring buffer. The renderer
   draws the ring as a line, which is the trail.

With Depth above 1.0 the same rules run in three dimensions. Each bee then
orbits on its own randomly oriented plane rather than in the screen plane, so
the swarm is a churning shell instead of a flat disc, and the tail it trails
when it loses the wasp can point at you as easily as across. The world turns 6
degrees a second, which is what makes near and far insects move differently
across the screen. The others are perspective, nearer insects drawn brighter
and thicker than their neighbours, and nearer ones drawn over further ones.

The world is a spheroid rather than a box, because a box seen from a turning
angle shows a flat face whenever a wall of bees bounces off it.

All the constants are written for a 1280 point wide screen and scaled to the
screen the screensaver is running on, so the swarm keeps the same proportions on a
laptop panel and on a 5K display.

Drawing batches every segment by colour and by opacity band, so even the
heaviest settings (400 bees with 48 point trails) come down to a few dozen
stroke calls a frame.

## Credits

A swarm of bees screensaver for MacOS 

Copyright (c) 2026 by Mike Robinson.

Permission to use, copy, modify, and distribute this software and its documentation for any purpose and without fee is hereby granted, provided that the above copyright notice appear in all copies and that both that copyright notice and this permission notice appear in supporting documentation.

This file is provided AS IS with no warranties of any kind. The author shall have no liability with respect to the infringement of copyrights, trade secrets or any patents by this file or any part thereof. In no event will the author be liable for any lost revenue or profits or other special, indirect and consequential damages.

Adapted from swarm.c Copyright (c) 1991 by Patrick J. Naughton
Adapted from xswarm by Jeff Butterworth 
