<p align="center"><img src="docs/icon.png" width="112" alt=""></p>

<h1 align="center">Flaco</h1>

<p align="center">A FLAC player for iPhones from the 5c on iOS 10 up. foobar2000 at heart, with a modern skin.</p>

<img src="docs/hero.png" width="100%" alt="Flaco's amber icon beside the player on an iPhone 6s">

- **Gapless** FLAC, ALAC, WAV, AIFF, MP3 and AAC, at the file's own sample rate where the output allows
- **Colours from the cover**, fading between songs
- **Live spectrum** and a waveform seekbar
- **ReplayGain**, by album where the tags have it
- **Syncs from Navidrome** or any Subsonic server: the original files, everything or the albums you tick, kept offline

## Build

```sh
./build.sh          # one app for 32-bit and 64-bit iPhones
Tools/install.sh    # signs it with your team and installs it on the iPhones plugged in
```

Put `DEVELOPMENT_TEAM` and `FLACO_BUNDLE_ID` in `Config/Local.xcconfig`. Signing needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The 5c takes a few extra steps: [docs/iphone-5c.md](docs/iphone-5c.md).

## License

MIT
