# 桌面羽毛球 Meowa 资源生成说明

音乐与音效的提示词及生成步骤见 `docs/BADMINTON_AUDIO_MEOWA_PROMPTS.md`。

## 资源合同

第一版只需要两次核心生成：

1. `badminton_court_background`：4:3 不透明像素球场背景，运行时按约 960x720 使用。
2. `badminton_ui_sheet`：4:3 透明 UI/道具合集，包含计分、按钮、球拍、羽毛球和常用特效。

地图与 UI 不要放在同一次生成。地图需要完整背景，UI 和道具需要透明分件，混在一起会降低切图质量。

## 生成一：球场地图

### Meowa 设置

- 功能：Pixel Universal Generation（像素通用生成）
- Composition：Normal，不选严格 Top-down
- Canvas：4:3 / xlarge
- Background removal：关闭
- 参考图：`D:\game creat\DesktopPet\assets\sprites\idle\idle_01.png`
- 只上传这一张参考图

### English prompt

```text
A 4:3 pixel-art badminton court viewed from a slightly elevated near-side perspective, designed as a playable game background. A clear badminton net runs horizontally across the center. Keep both halves open and readable, with enough space for a small chibi girl opponent on the far half and a mouse-controlled racket on the near half. Use mint green and white court markings, blush pink borders, charcoal details, small rose and ribbon accents, and a bright garden sports pavilion atmosphere that matches the reference character. No characters, no rackets, no shuttlecocks, no UI, and no text.
```

### 检查标准

- 球网必须横贯中央，不能斜到难以判断前后场。
- 远侧要能放下桌宠，近侧要留出鼠标挥拍空间。
- 不能出现人物、文字、按钮、比分牌或画面边框。
- 球场线要清楚，装饰不能占据可玩区域。

## 生成二：UI、道具与特效合集

### Meowa 设置

- 功能：UI Generation
- Mode：Generate
- Resolution：2K
- Aspect ratio：4:3
- Quality：Detailed
- Background removal：Standard；若细小羽毛边缘不干净，再单独尝试 Advanced
- 参考图：`D:\game creat\DesktopPet\assets\care\runtime\ui\care_panel.png`
- 只上传这一张参考图

### English prompt

```text
A cohesive pixel-art UI and gameplay asset sheet for a cute desktop badminton duel, matching the reference UI. Use warm white, blush pink, cherry red, mint green, charcoal, and small gold accents, with restrained lace, roses, ribbons, and heart details. Arrange clearly separated reusable components: a wide match score panel, two player score badges, a compact round indicator, a combo counter plate, a smash power meter frame and fill, a serve indicator, a pause button, restart button, exit button, three small difficulty tabs, a large result panel, three shuttlecocks at different flight angles, a mouse-controlled badminton racket cursor, a circular landing marker, a normal hit spark, a perfect-hit star burst, a curved smash trail, a miss puff, and a small victory confetti effect. Transparent background, generous spacing between every component, no characters, no scene background, no letters, no numbers, and no readable text.
```

### 检查标准

- 每个组件之间必须有透明间距，不能互相粘连。
- 按钮只保留图标和装饰，不要让模型生成中文或英文。
- 羽毛球至少有三个不同朝向，不能与球拍重叠。
- 计分板、结果框和能量条中央要留出干净区域，文字由 Godot 绘制。
- 下载完整 Godot/源资源 ZIP，不要只保存网页预览截图。

## 可选第三次：特效补充

只有第二张图里的特效粘连或不够清晰时才生成，不必提前消耗额度。

```text
A transparent pixel-art effects sheet for a cute badminton game. Include twelve clearly separated effects: three racket swing arcs with increasing power, two shuttlecock impact sparks, a perfect-hit flower burst, a fast smash trail, a net-graze spark, a court landing ring, a soft miss puff, a score celebration, and a match-win confetti burst. Match a blush pink, mint green, warm white, cherry red, and gold desktop companion UI palette. No characters, no UI panels, no text, and generous transparent spacing.
```

## 导出交接

生成后分别下载原始 ZIP，文件名可改为：

- `桌面羽毛球地图.zip`
- `桌面羽毛球UI和特效.zip`

将 ZIP 发给 Codex 后再开始切图和实装。不要在 Meowa 中继续缩放或拼接，Godot 中会统一处理分辨率、锚点和碰撞区域。
