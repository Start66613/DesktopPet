# 桌面羽毛球 Meowa 音乐与音效生成说明

## 已接入内容

当前版本使用一首循环 BGM 和九个语义化音效：

- `badminton_bgm.mp3`：比赛窗口背景音乐
- `ui_confirm.mp3`：选择难度、开始、暂停和继续
- `serve.mp3`：首轮发球
- `hit.mp3`：普通击球
- `perfect.mp3`：完美回击
- `smash.mp3`：扣杀
- `score_player.mp3`：玩家得分
- `score_pet.mp3`：桌宠得分
- `win.mp3`：比赛胜利
- `lose.mp3`：比赛落败

运行目录为 `assets/minigames/badminton/runtime/audio/`。Godot 会原生导入 MP3；BGM 在代码中开启循环，窗口关闭后停止，暂停菜单打开时暂停。

## 生成一：比赛 BGM

### Meowa 操作

1. 在 Canvas 中添加 Music / 音乐生成节点。
2. 选择直接生成完整音频，不要先做 30 秒 Preview。预览不能无损延长成同一首完整曲目。
3. 使用下面的英文提示词，生成约 3 分钟的版本。
4. 下载最终 MP3，试听开头、结尾和连续循环处。
5. 接入项目时命名为 `badminton_bgm.mp3`。

### English prompt

```text
A three-minute loopable instrumental theme for a cute desktop badminton match in a pastel rose garden. Light and lively at about 118 BPM, with pizzicato strings, glockenspiel, soft marimba, airy flute, and gentle acoustic percussion. Keep the melody playful and warm rather than intense, with steady energy that will not distract during repeated rallies. Begin cleanly and end at a musically seamless loop point. No vocals or lyrics.
```

当前用户生成版约 `136.960` 秒，默认运行音量为 `-12 dB`，给击球音效留出了空间。上一版约 `173.453` 秒的音乐和配套音效保存在 `D:\game creat\DesktopPet_backup_20260808-230433`，可随时整体或仅按 `runtime/audio` 目录恢复。

## 生成二：九件套音效

### Meowa 操作

1. 在 Canvas 中添加 Sound Effects / 音效生成节点。
2. 选择 Sound Pack / 音效包模式。
3. 数量设为 `9`，单项时长设为 `1` 秒；得分或胜负短句允许模型自然延长到约 2 秒。
4. 使用下面的英文提示词一次生成整套，统一音色并节省重复生成额度。
5. 按输出顺序试听，确认每个文件都对应正确事件，再按“已接入内容”中的文件名重命名。

### English prompt

```text
Create a coherent ordered pack of nine short sound effects for a cute pastel desktop badminton game: 1 soft UI confirm chime, 2 airy shuttlecock serve whoosh, 3 crisp racket contact pop, 4 sparkling perfect-hit chime layered with contact, 5 stronger smash crack with a short airy trail, 6 cheerful player-score flourish, 7 playful pet-score flourish, 8 warm match-win fanfare, and 9 gentle encouraging match-loss jingle. Keep every sound clean, bright, compact, and consistent with a magical-girl rose-garden style. No speech, no voices, no background music, and no long reverb tails.
```

## 验收标准

- 普通击球、完美回击和扣杀必须能仅靠声音区分。
- 玩家得分与桌宠得分不能使用同一旋律或完全相同的音高走向。
- 音效不能带人声、环境底噪或过长混响，否则连续回合会堆叠得很乱。
- BGM 要比音效轻，连续播放时不能盖住击球反馈。
- BGM 需要至少试听两次首尾衔接；若接缝明显，优先重新生成明确 loop point 的版本。

第一版 Meowa 输出保存在 `outputs/meowa-badminton-audio-20260808/`。当前用户生成版的中文原文件保存在 `assets/minigames/badminton/packages/audio_user_20260808/`，运行时使用其语义化重命名副本。
