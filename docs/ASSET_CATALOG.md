# DesktopPet Asset Catalog

This catalog groups the project's reusable assets without moving their files. Keeping the existing paths stable avoids breaking Godot imports and scene references.

## Runtime UI

| Category | Directory | Main reusable assets |
| --- | --- | --- |
| Care and context menu | `assets/care/runtime/ui/` | `care_panel.png`, `context_menu_panel.png`, `item_picker.png`, action icons, `close.png` |
| Speech bubble | `assets/care/runtime/bubbles/` | `speech_body.png`, `speech_tail.png` |
| AI chat | `assets/chat/runtime/ui/` | chat panel, input/settings fields, user/assistant bubbles, send/settings/status buttons, `minimize.png`, `close.png` |
| Companion settings | `assets/companion/runtime/ui/` | generated icon spritesheets for memory, screen permission, work/game assistant, reminders and future controls |
| Music player | `assets/music/runtime/ui/` | player and fullscreen backgrounds, lyrics/playlist panels, decorations, playback/status icons, `minimize.png`, `close.png` |
| Badminton game | `assets/minigames/badminton/runtime/ui/` | scoreboard, modal panels, difficulty controls, racket/shuttle assets, effects, pause/restart/exit controls |

## Character And Activity Animation

| Category | Directory | Contents |
| --- | --- | --- |
| Main pet | `assets/movement/`, `assets/sprites/` | idle and directional movement source frames |
| Pet activities | `assets/activities/` | badminton, music listening, handheld game and dragon ride animations |
| Dog movement | `assets/dog/source/directions/` | eight explicitly labelled movement directions |
| Dog actions | `assets/dog/source/actions/` | happy, sit transition/idle and sleep transition/idle |
| Dog interaction | `assets/dog/source/interaction/` | pet-and-dog interaction source animation |
| Dog furniture and UI | `assets/dog/source/furniture/`, `assets/dog/source/blue_ui/` | furniture sprites and pale-blue dog system UI source sheets |

## Source And Archive Rules

- `runtime/` contains cleaned assets intended for direct loading by game code.
- `source/` preserves original Meowa exports and sprite sheets for future recutting.
- `assets/archive/` stores older or superseded material for reference.
- `assets/ui_source/` stores general UI source packs that have not yet been promoted to a feature-specific runtime directory.
- New code should prefer a feature's `runtime/` directory and should not load an arbitrary numbered source sheet directly.

## Current Reuse Decisions

- Fullscreen music window controls use `assets/music/runtime/ui/minimize.png` and `close.png`.
- The controls keep transparent artwork and a larger invisible hit target; no generated rectangular button background is added.
- Chat and care close controls remain available as alternate pink treatments, while badminton's exit button is reserved for the game screen.
