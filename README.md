<p align="center">
  <img src="site/favicon.svg" width="84" alt="Healthy Pops icon">
</p>

<h1 align="center">Healthy Pops</h1>

<p align="center">
  <b>Tiny popups that keep you healthy at your Mac.</b><br>
  Eye breaks, water, posture and your own reminders. Free forever, open source.
</p>

<p align="center">
  <a href="https://github.com/ThusharaSampath/healthy-pops/releases/latest"><img src="https://img.shields.io/github/v/release/ThusharaSampath/healthy-pops?color=ff4fa3&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-1fa2c4" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-6a4cf0" alt="Universal">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2fb67c" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://github.com/ThusharaSampath/healthy-pops/releases/latest/download/HealthyPops.dmg"><b>⬇&nbsp; Download for Mac</b></a>
  &nbsp;·&nbsp;
  <a href="https://healthy-pops.pages.dev">Website</a>
</p>

<p align="center">
  <img src="docs/popups.jpg" alt="Healthy Pops popups: eye break reminder, water, posture and a custom stretch reminder">
</p>

## What it does

|  |  |
|---|---|
| 👀 **Eye breaks** | The 20-20-20 rule on autopilot. A heads-up, then a calm 20-second break with nothing to read. |
| 💧 **Water** | A silly nudge every hour. Log a glass with <kbd>⌃⌥W</kbd>. |
| 🧍 **Posture** | Five seconds, one cheeky line, gone. |
| ✨ **Your own popups** | Pick a title, icon, colour and interval in a keyboard-first editor. |
| 🐱 **Break cat** | A little cat turns up during eye breaks and does one cute thing: waves, grooms, stretches, naps, chases yarn. Seven coats, four ways in, never the same twice in a row. Switch it off under **Reminders → Break Cat**. |

<p align="center">
  <img src="docs/break-cat.jpg" alt="The break cat waving, chasing yarn, watching a butterfly, napping and sending hearts">
</p>

Every popup counts **real screen time** (lock, sleep or walk away and it starts over), **waits while you're in a call**, and can be tuned or switched off from the menu bar. No account, no network, no permissions. Native Swift, under 1 MB.

## Install

1. [Download `HealthyPops.dmg`](https://github.com/ThusharaSampath/healthy-pops/releases/latest/download/HealthyPops.dmg) and drag the app to Applications.
2. First launch only: right-click the app → **Open** (it isn't notarized yet).
3. It lives in your menu bar. Turn on **Launch at Login** there.

## Build from source

```bash
git clone https://github.com/ThusharaSampath/healthy-pops
cd healthy-pops
./build.sh --install
```

Needs Swift 5.9+ (Xcode or Command Line Tools). Run with `HEALTHYPOPS_DEBUG=1` for a 30-second cycle while testing.

## Contributing

PRs are very welcome: funnier messages (`Sources/HealthyPops/NudgeToast.swift`), new built-in popups, new cat coats or activities (`Sources/HealthyPops/BreakCat.swift`), fixes and ideas. Pushing a `v*` tag builds a universal DMG, publishes the release and deploys the website.

## License

[MIT](LICENSE) © Thushara Sampath
