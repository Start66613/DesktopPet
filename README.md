# DesktopPet - Xiao Xueqiu

> A Windows desktop companion who walks, sleeps, chats, listens to music, plays badminton, and keeps you company.

[![Godot](https://img.shields.io/badge/Godot-4.7.1-478cbf?logo=godotengine)](https://godotengine.org/)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078d4?logo=windows)](#local-run)
[![License](https://img.shields.io/badge/license-MIT-75b798.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-active%20development-f5a3b7.svg)](#roadmap)

DesktopPet is a personal Godot project focused on **companionship, playful interaction, and a soft girl-style UI**. It is more than a static mascot: the pet wanders and rests on the desktop, speaks in bubbles, reacts to music, supports AI chat and optional screen awareness, and includes care activities, a mini-game, and a dog companion.

> Current build: `0.1.0` development version. The immersive music experience is still being actively redesigned.

## Preview

| Desktop interaction | Music center |
| --- | --- |
| ![The pet showing a speech bubble on the desktop](docs/images/desktop-pet-interaction.png) | ![The pink lace-styled music player](docs/images/music-player.png) |

| Companion settings | Desktop badminton mini-game |
| --- | --- |
| ![Companion settings window](docs/images/companion-settings.png) | ![Badminton mini-game result screen](docs/images/badminton-gameplay.png) |

## Features

### Desktop companion

- Borderless transparent desktop window with click-through in transparent pixels.
- Eight-direction walking, idle, sleep, turn-over, music, handheld, and badminton animation states.
- Mouse dragging, context menus, speech bubbles, emoticons, and interaction feedback.
- Configurable proactive-expression frequency; the pet stays quiet while sleeping.

### Care and interaction

- Food, drinks, entertainment, gifts, and affection feedback.
- Draggable girl-style care panels with button motion feedback.
- A desktop badminton duel with rounds, scoring, combos, results, and sound effects.
- A hidden Easter egg: ride a dragon through a secret setting interaction.

### AI and local awareness

- AI chat through an OpenAI-compatible Chat Completions endpoint configured in-app.
- Error messages and random dialogue stay in the pet's voice.
- Optional foreground-app/process awareness for more contextual work, game, and music companionship.
- Screen awareness is off by default and requires explicit authorization in settings.

### Music companion

- Reads Windows media sessions and can follow players such as QQ Music and NetEase Cloud Music.
- Album cover, track metadata, lyrics, progress, play/pause, previous/next, playback order, and seek control.
- Pet-style reactions to song changes, playback state, and lyric changes.

### Dog companion

- Adopt, name, send home, and manage a dog companion.
- Eight-direction walking plus sit, sleep, and happy idle animations.
- The pet reacts to the dog's state through dialogue and interactions.

## Technical overview

| Area | Implementation |
| --- | --- |
| Desktop/game layer | Godot 4.7.1, GDScript, native transparent windows |
| Click-through | Sprite alpha hit testing plus Windows window input-region control |
| Animation | `AnimatedSprite2D`, SpriteFrames, multi-frame pixel animation |
| Music integration | Windows Global System Media Transport Controls bridge |
| AI chat | Configurable OpenAI-compatible Chat Completions endpoint |
| Local awareness | Foreground-app detection and opt-in screen-state analysis |
| Windows release | Godot export, PowerShell build scripts, Inno Setup installer |

The project is organized by feature under [`scripts/`](scripts), [`scenes/`](scenes), [`assets/`](assets), and [`tools/`](tools). See the [asset catalog](docs/ASSET_CATALOG.md) for source, runtime, and backup asset locations.

## Local run

### Requirements

- Windows 10 or Windows 11
- Godot `4.7.1`
- Optional: QQ Music or NetEase Cloud Music for local media-session integration

### Steps

1. Clone the repository and import the project with Godot `4.7.1`.
2. Run the project main scene, or run `scenes/pet.tscn`.
3. Open care, chat, companion settings, music, and mini-games from the pet's right-click menu.
4. For AI chat, enter the endpoint, model, and API key in the in-app settings. Never commit real keys.

## Windows build

The release script is [`tools/build_windows_release.ps1`](tools/build_windows_release.ps1). It produces:

- `dist/DesktopPet-0.1.0-Setup.exe`: Inno Setup installer
- `dist/DesktopPet-0.1.0-Portable.zip`: portable build

`build/`, `dist/`, `.env`, runtime logs, Godot import caches, and local backups are excluded by `.gitignore`.

## Privacy and safety

- AI endpoints and screen awareness are optional and disabled by default.
- API keys, tokens, and local environment files are excluded from GitHub.
- Screen frames are analyzed only after authorization; the project does not upload or persist screenshots by default.
- Review the terms and licenses of third-party models, music clients, and generated assets before redistribution.

## Roadmap

- [x] Transparent desktop pet, click-through, drag interaction, and eight-direction motion
- [x] Care system, speech bubbles, context menus, and themed panels
- [x] AI chat, proactive-companion settings, and foreground-app detection
- [x] Windows media sessions, lyrics, music player, and music companionship
- [x] Badminton mini-game, dog companion, and dragon Easter egg
- [ ] Rebuild immersive music mode so the desktop pet remains freely active with a natural fullscreen transition
- [ ] More autonomous dog interactions, furniture, and desktop events
- [ ] Stronger multimodal screen awareness and AI work/game assistance

## Feedback

This is a continuously evolving learning project. Issues and UX feedback are welcome. Please include Windows version, reproduction steps, expected behavior, and sanitized screenshots/logs when reporting a bug.

## License and asset notice

Source code is released under the [MIT License](LICENSE). Fonts, music, sound effects, generated art, and third-party assets may have their own restrictions. Check the notices under `release/` and the terms of each source before publishing or redistributing.
