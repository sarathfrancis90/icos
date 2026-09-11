# YouTube upload for the Play Store promo video

Play only accepts a **YouTube URL** for the store listing video, not a file. So this
has to go up on YouTube first, then the link goes into the listing.

## The file

`icos-gameplay-1080p.mp4` — 1920x1080, H.264, 30 fps, stereo AAC, 34 seconds, 4.1 MB.

A full 7x7 practice solve on an iPhone, sped up so the line drawing reads at a glance,
over a blurred pull of the same footage. The audio track is silent by design: Play and
YouTube both want one present, and the store plays the video muted anyway.

## The thumbnail

`icos-thumbnail-1280x720.png` — 1280x720, 221 KB, well inside YouTube's 2 MB cap.

Set it under Video details, Thumbnail, Upload file. It needs a verified YouTube
account; if yours is not verified yet, verify by phone first or YouTube will only
offer the three auto-generated frames.

Regenerate it with `python3 scripts/make_thumbnail.py`. The board in it is lifted from
a real screenshot, not drawn, and the type is the same Inter the app ships. The layout
deliberately keeps the bottom-right corner clear, because YouTube stamps the video
duration there.

## Upload settings Play requires

Get these wrong and Play rejects the URL.

- **Visibility:** Public or Unlisted. Private will not work.
- **Monetisation / ads:** off.
- **Made for kids:** No, not made for kids.
- **Age restriction:** none.

## Copy to paste

**Title**

```
Icos - One line. Every cell. A daily path puzzle.
```

**Description**

```
Icos is a daily path puzzle. Draw one continuous line through every cell of the
grid, visiting the numbered waypoints in order. Every puzzle has exactly one
solution.

Everyone in the world gets the same puzzle each day. Monday starts gentle with a
5x5 grid. By Sunday you are facing an 8x8. Build a streak, create a group, and
race your friends on daily and weekly leaderboards.

Free. No ads. No account needed to play.

In 1857 the mathematician William Rowan Hamilton invented the Icosian game: find
a route that visits every point exactly once. Icos brings that idea to your phone
with a fresh grid every day.

https://icos.sarathfrancis.work
```

**Tags**

```
puzzle game, daily puzzle, logic puzzle, path puzzle, brain game, hamiltonian path,
grid puzzle, zip puzzle, one line puzzle, icos
```

## Then

Paste the watch URL into Play Console under Store listing, Common visual assets,
Video. Or hand the URL to Claude and it can set it through the API.
