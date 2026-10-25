<p align="center"><img src="docs/icon.png" width="112" alt=""></p>

<h1 align="center">Flaco</h1>

<p align="center">A FLAC player for the iPhone 6s. foobar2000 at heart, with a modern skin.</p>

<img src="docs/hero.png" width="100%" alt="Flaco's amber icon beside the player on an iPhone 6s">

- **Gapless** FLAC, ALAC, WAV, AIFF, MP3 and AAC, at the file's own sample rate where the output allows
- **Colours from the cover**, fading between songs
- **Live spectrum** and a waveform seekbar
- **ReplayGain**, by track or album
- **Syncs from Navidrome** or any Subsonic server: the original files, everything or just what you pick, kept offline

## Build

```sh
brew install xcodegen && xcodegen && open Flaco.xcodeproj
```

Put your team and bundle id in `Config/Local.xcconfig`, then build Release to an iPhone on iOS 15.

## License

MIT
