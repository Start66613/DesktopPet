# 桌宠项目交接文档

> 本文档供 Codex 接手继续开发使用。项目已完成初版：透明置顶窗口 + 待机动画 + 点击穿透 + 八向自动闲逛 + 点击/自动气泡互动 + 右键菜单。

## 项目概况

| 项 | 值 |
|---|---|
| 项目路径 | `d:\game creat\DesktopPet` |
| 引擎 | Godot 4.7 stable（运行日志确认为 `4.7.stable.official`） |
| 渲染器 | `gl_compatibility`（OpenGL 3.3） |
| 目标 | 个人使用的桌面宠物，透明无边框置顶窗口 |
| 当前状态 | 可运行：待机动画、八向移动、拖动、点击穿透、随机气泡互动、右键菜单 |

## 环境与运行

启动游戏：

```powershell
godot --path "d:\game creat\DesktopPet"
```

新增 PNG 帧后需要重新导入（否则 `load()` 会报 No loader found）：

```powershell
godot --headless --import --path "d:\game creat\DesktopPet"
```

调试说明：Godot 项目窗口标题在 debug 模式下为 `DesktopPet (DEBUG)`，正式运行为 `DesktopPet`。运行中的退出方式：右键菜单中的“退出桌宠”或按 ESC。

## 项目结构

```
DesktopPet/
├── project.godot              # 窗口与渲染配置
├── icon.svg
├── scenes/
│   └── pet.tscn               # 主场景：Node2D + AnimatedSprite2D
├── scripts/
│   └── pet.gd                 # 全部逻辑（动画/状态机/拖动/点击穿透）
└── assets/
    └── sprites/
        └── idle/              # 动作文件夹，idle_01.png ~ idle_08.png
            └── ...            # 每帧 256x256，透明背景像素画
    └── movement/               # 用户提供的八套 Godot SpriteFrames 资源包
        ├── walk_left/
        ├── walk_right/
        ├── walk_up/
        ├── walk_down/
        ├── walk_up_left/
        ├── walk_up_right/
        ├── walk_down_left/
        └── walk_down_right/
```

约定：`assets/sprites/<动作名>/*.png` 即一个动画，脚本启动时自动扫描目录构建 `SpriteFrames`，无需手动配置。新增动作只需新建文件夹放帧。

## 核心实现

### 透明置顶窗口（`project.godot`）

关键配置：

```ini
[display]
window/size/viewport_width=320
window/size/viewport_height=320
window/size/resizable=false
window/size/borderless=true
window/size/transparent=true
window/size/always_on_top=true
window/per_pixel_transparency/allowed=true

[rendering]
renderer/rendering_method="gl_compatibility"
textures/canvas_textures/default_texture_filter=0   ; Nearest 过滤，像素画
environment/defaults/default_clear_color=Color(0, 0, 0, 0)
```

注意：仅靠项目配置还不够，`pet.gd` 的 `_ready()` 里还调用了 `get_viewport().transparent_bg = true`，两者缺一不可。

### 动画系统（`pet.gd` 的 `_build_sprite_frames()`）

启动时扫描 `SPRITES_DIR` 下每个子文件夹，按文件名排序构建循环动画，默认 8 FPS；随后递归读取 `assets/movement` 下用户提供的 `*_frames.tres`，把资源包中的 AtlasTexture 帧复制到英文方向动作名。精灵 256x256 以 `SPRITE_SCALE = 1.0` 显示，`centered = true`，居中于 320x320 视口，显示尺寸更接近 Codex 宠物。

### 状态机与自动移动（`pet.gd`）

当前枚举为 `enum State { IDLE, WALK }`。待机和行走会按随机时长切换；行走从八个方向随机选择，以浮点累计的窗口位置移动桌宠，避免高刷新率下斜向位移被整数四舍五入吞掉；碰到当前屏幕的可用工作区边缘时反弹并切换对应方向动画。

加新状态（SLEEP/REACT/CLICK）的路径：扩枚举 → 加 `_enter_state()` 分支 → 在动画库中加入动作 → 按需在 `_process()` 或点击事件中触发。

### 点击互动气泡

启动时会先显示欢迎气泡；左键短按角色会进入短暂待机并显示随机中文短句/emoji，自动行走回到待机时和定时器到点时也会主动说话。气泡由 `speech_bubble.gd` 的 `Node2D` 直接绘制底板和文字，绕开透明窗口中不稳定的 Control 布局，因此不会影响鼠标穿透。Windows 下气泡文字加载 `simhei.ttf`，emoji 加载 `seguiemj.ttf`，避免 Godot 默认字体缺少中文/emoji 字形。左键拖动仍然移动窗口；右键打开菜单，可选择说话、开关自动散步、回到屏幕中央或退出。

### 点击穿透（核心功能，已实现）

API 是 **`DisplayServer.window_set_mouse_passthrough(region: PackedVector2Array)`**，不是 `window_set_mouse_passthrough_polygon`（该方法不存在，会直接 Parser Error 中断运行）。

实现思路：窗口只在多边形内部接收鼠标事件，多边形外全部穿透到后方窗口。流程：

1. `_precompute_passthrough_polygons()`：启动时遍历所有动画所有帧，调用 `_compute_opaque_polygon()` 逐像素扫 alpha，得到不透明像素的矩形包围盒，扩展 2 像素余量后转成窗口坐标四边形，存进 `_frame_polygons`（`anim_name -> Array[PackedVector2Array]`）。
2. 监听 `sprite.frame_changed`，换帧时 `_update_passthrough()` 把当前帧的四边形传给系统。
3. 拖动时（`_dragging == true`）传入空多边形取消穿透，保证拖到透明区也不丢事件；松开左键后恢复。

### 拖动与退出（`pet.gd` 的 `_input()` / `_unhandled_input()`）

左键按住拖动窗口（记录鼠标与窗口起点做差量）；右键打开 `PopupMenu`，菜单打开期间临时关闭穿透，关闭后恢复当前帧区域。

## 关键技术决策

- **为什么用 passthrough 多边形而不是 WS_EX_TRANSPARENT**：曾用 Python ctypes 给窗口加 `WS_EX_TRANSPARENT` 测试，失败。原因：Godot 透明窗口不使用 `WS_EX_LAYERED` 样式，而 `WS_EX_TRANSPARENT` 依赖它才能生效。Godot 原生 API `window_set_mouse_passthrough` 内部正确实现（Windows 上用 `WM_NCHITTEST` 方案），可直接用，不需要碰 Win32。
- **包围盒而非精确轮廓**：最初实现过逐行扫描生成轮廓多边形（每帧约 190-213 顶点），但该实现曾在自测时出现部分区域穿透失效的异常，且顶点多。为稳妥，当前版本用矩形包围盒（每帧 4 顶点），简单可靠，已验证可用。

## 已知限制

- 矩形包围盒会包含角色周围的透明区（如头顶上方、裙摆与地面之间），这些区域仍可点击、不会穿透。对"点角色旁边空白穿透到后面窗口"的核心需求无影响。若需更精确，可改为轮廓多边形：逐行扫描每行最左/最右不透明像素，左边界从上到下、右边界从下到上拼合成闭合多边形，再做共线点简化（早期版本实现过，每帧约 190-213 顶点，当前代码已替换为包围盒，可用类似思路重写）。
- 自测 25 个点击点中 23 个符合预期，2 个异常点集中在角色头顶正上方 60px 与脚下 60px 处，属包围盒边缘误差。
- 透明穿透在动画帧切换时实时更新，动画跳动时穿透区域会随之轻微变化，属正常现象。

## 待办事项

1. 更多动作：SLEEP / REACT / CLICK 互动。
2. 打包导出（Export Templates）为 exe，目前只在编辑器/命令行下跑。
3. 开机自启、任务栏图标隐藏、设置菜单等桌面应用增强（可选）。

## 2026-08-07 养成系统更新

- `scripts/care_system.gd`：管理饱腹、水分、心情、好感和精力；支持真实时间衰减、睡眠恢复、最多 8 小时离线结算，以及 `user://care_state.cfg` 本地存档。
- `scripts/care_panel.gd`：独立透明置顶养成窗口。右键桌宠选择“打开她的日常”，可进行吃饭、喝水、聊天、娱乐、送礼、摸摸和休息互动；四个物品类别各有 5 个可选项目。
- `scripts/care_feedback.gd`：在角色旁显示饱腹、水分、心情、好感和精力反馈，并与 Windows 点击穿透区域同步，避免透明窗口裁剪。
- `scripts/speech_bubble.gd`：换用 Meowa 紧凑气泡本体和独立尖角；气泡高度为 64 像素，尖角位于头发上方，长对白自动排成两行。
- `assets/care/packages/`：用户提供的四个原始 ZIP 完整归档。
- `assets/care/source/`：四套 Meowa Godot 导出包的完整解压内容。
- `assets/care/runtime/`：运行时使用的 38 个语义化 PNG，包括主面板、按钮、20 件物品、气泡和反馈效果。
- 调试养成面板可使用：`godot --path "d:\game creat\DesktopPet" -- --show-care-panel`。正常启动不会自动打开面板。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260807-232439`。

## 2026-08-08 养成面板布局更新

- `scripts/care_panel.gd`：物品选择器按资源图实际的四列两行卡槽布局，五个物品排为第一行四个、第二行一个；图标与名称均缩小并居中在各自卡槽内。
- 养成面板底部新增与主面板衔接的粉白操作底板，使七个行动按钮不再悬空。
- 养成面板顶部和物品选择器标题区域均可拖动窗口，关闭按钮和物品按钮不受影响。
- `scripts/mirror_preview.gd`：镜面镂空处改为有柔和底色与细线反光的镜子，并循环播放 `assets/sprites/idle/idle_01.png` 至 `idle_08.png` 的待机动画。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-001342`。

## 2026-08-08 养成面板视觉校准

- 镜面预览改为比透明孔更大的矩形底层，使用与主面板一致的暖白底色；`care_panel.png` 后绘制并自然遮住矩形边缘，不再手工拟合椭圆。
- `scripts/care_stat_bar.gd`：替代受 Godot 主题最小尺寸影响的 `ProgressBar`，动态条固定为 `137x10`，并在底图虚线框内保留一致边距。
- `assets/care/runtime/ui/action_strip.png`：由旧 UI 包的 `36_spritesheet.png` 本地整理而成，保留双层边框与四角花饰，移除不匹配的十二格占位；未调用 Meowa，不消耗额度。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-003957`。

## 2026-08-08 养成界面尺寸与动效

- 养成窗口从 `440x470` 放大到 `520x555`，内部使用统一 `1.18` 倍设计缩放，布局比例、字体和点击区域同步增大。
- 移除物品选择器覆盖全窗口的半透明粉色遮罩，解决透明区域出现粉色矩形边的问题。
- 物品选择器标题下移到蝴蝶结下方，并缩为紧凑单行，避免文字压住装饰。
- 面板打开时淡入并轻微弹出；主操作按钮、关闭按钮和物品按钮支持悬停放大与轻摆；物品按顺序淡入；状态条通过 Tween 平滑滑动到新数值。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-005210`。

## 2026-08-08 右键菜单定位修复

- `scripts/pet.gd`：右键菜单改用屏幕坐标定位，不再把桌宠窗口内部坐标误当成系统弹窗坐标。
- 菜单默认显示在桌宠右侧，靠近屏幕边缘时自动切换到左侧，并按当前屏幕工作区限制上下位置。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-010638`。

## 2026-08-08 右键菜单视觉与窗口尺寸

- `scripts/pet.gd`：右键菜单改为贴当前动画帧的不透明模型边界，视觉间距约 `6px`；不再按透明窗口边缘计算距离。
- `assets/care/runtime/ui/context_menu_panel.png`：由 UI 包 `main_ui/14_spritesheet.png` 整理出干净的竖向花边菜单底板，保留顶部玫瑰、外框和虚线边，移除原设置菜单内容。
- 养成窗口从 `520x555` 再放大到约 `581x620`。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-011507`。

## 2026-08-08 右键菜单内层色块修复

- `assets/care/runtime/ui/context_menu_panel.png`：将清理原菜单内容时留下的偏亮矩形填充改为与原花边面板一致的自然底色，消除菜单内部可见的矩形边缘。
- 保留菜单花边、顶部玫瑰、文字可读底色和原有点击区域；菜单交互逻辑未改动。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-012546`。

## 2026-08-08 AI 聊天与羽毛球互动

- `scripts/ai_chat_panel.gd`：新增可拖动的云端 AI 聊天窗口，使用通用 OpenAI 兼容 `chat/completions` 接口；支持 OpenAI、DeepSeek、硅基流动和自定义接口地址，模型、API Key、请求中状态、消息气泡、滚动历史和本机配置。
- API 配置保存在 `user://ai_chat.cfg`，聊天记录保存在 `user://ai_chat_history.json`，均不写入项目资源；聊天系统提示词会带入当前养成状态，但不会虚构看到用户屏幕内容。
- 右键菜单“和她说说话”和养成窗口“聊天”按钮现在打开同一个 AI 聊天窗口；AI 回复会以桌宠气泡短暂显示，并增加少量心情和好感。
- `assets/chat/packages/ai_chat_ui.zip`：完整原始 UI 包；`assets/chat/source/`：原始 Godot 导出；`assets/chat/runtime/ui/`：运行时语义化 UI 组件。
- `assets/activities/badminton/`：完整羽毛球动画包；`scripts/pet.gd` 将其注册为一次性 `badminton` 活动，动画结束自动回到待机并暂停自动散步期间的移动。
- `scripts/care_system.gd`：娱乐物品新增“羽毛球”，消耗精力并提升心情/好感；图标为羽毛球动画首帧裁切图。
- 调试启动聊天窗口：`godot --path "d:\game creat\DesktopPet" -- --show-chat-panel`。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-013246`。

## 2026-08-08 聊天窗口切换与最小化修复

- `scripts/pet.gd`：从右键菜单或养成窗口切换到聊天时，先隐藏当前菜单/养成窗口，再将聊天窗口置前，避免多个原生置顶窗口互相遮挡。
- `scripts/ai_chat_panel.gd`：重新打开聊天前恢复 `Window.MODE_WINDOWED`；最小化使用聊天窗口自身的 `mode` 属性，修复最小化后再次打开仍停留在隐藏状态的问题。
- 聊天 UI 底图已自带发送、最小化和关闭按钮，运行时改为只叠加透明点击热区，避免重复绘制造成按钮错位；设置按钮仍使用独立素材。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-021423`。

## 2026-08-08 聊天窗口启动日志清理

- `scripts/ai_chat_panel.gd`：移除 Godot 4.7 已弃用的 `move_to_foreground()` 调用，使用 `grab_focus()` 完成置前。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-021939`。

## 2026-08-08 主动陪伴系统 1.0

- `scripts/proactive_companion.gd`：新增独立主动陪伴模块，复用聊天窗口保存的 OpenAI 兼容 API 配置；结合当前时间、养成数值、桌宠动作、最近互动与近期主动台词，允许 AI 自主判断开口或保持安静。
- 首次主动思考延迟约 25～45 秒，之后按用户设置的表达频率调度；接口失败时静默退避，不向用户显示技术报错，也不会在睡觉、起床、娱乐、拖拽、已有气泡或功能窗口打开时插话。
- 最近养成互动、成功 AI 对话与主动台词保存在 `user://companion_memory.json`；主动陪伴开关保存在 `user://companion_settings.cfg`。
- `scripts/pet.gd`：喂食、喝水、娱乐、送礼、摸摸、休息和 AI 对话会进入短期互动记忆；旧固定台词间隔由 14～28 秒调整为 70～130 秒。
- 右键菜单新增可勾选的“主动陪伴”，默认开启并持久化；关闭进行中的请求后不会补发过期气泡。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-142620`。

## 2026-08-08 主动陪伴设置与活动扩展

- `scripts/companion_settings_panel.gd`：新增独立可拖动陪伴设置窗口，包含主动陪伴、夜间安静、前台应用感知开关，5 秒测试/活泼/日常/安静四档预设，以及 5 秒至 10 分钟、1 秒步进的频率滑杆。
- “现在来陪我”会立即发起一次强制开口的主动陪伴测试；低于 30 秒的测试频率下，AI 选择安静后也按当前短间隔继续测试，而接口失败仍保留静默退避，避免故障时频繁请求。
- 设置面板使用缩放后的 Meowa 背景素材，但标题、状态、开关、预设和操作按钮文字改为原生像素尺寸绘制，减少整体缩放造成的文字发糊；窗口打开时有轻微弹出动画，不改变透明度。
- `scripts/ai_chat_panel.gd`、`scripts/care_panel.gd` 和设置窗口均使用普通窗口层级（`always_on_top = false`）；只有桌宠主窗口保持置顶。当前窗口尺寸为聊天 `480x689`、养成 `520x555`、设置 `591x415`。
- `scripts/foreground_app_monitor.gd` + `tools/foreground_app_probe.exe`：Windows 下通过 `GetForegroundWindow`/`EnumWindows` 读取前台进程名及最多 8 个有可见标题窗口的应用进程名，不读取或传递窗口标题、文档内容和屏幕画面；过滤桌宠自身、系统进程及 NVIDIA 浮层。
- 进程探针由 `tools/foreground_app_probe.cs` 编译，大小约 7 KB；探针缺失时使用 `tasklist.exe` 粗略降级，运行期不再隐藏启动 PowerShell，避免触发系统安全拦截。
- `assets/activities/music/` 与 `assets/activities/handheld/` 已导入；听歌约循环 22 秒、掌机对战约循环 24 秒、羽毛球约循环 13 秒，活动结束后回到待机。羽毛球使用用户新生成的独立图标。
- 运行验证：Godot 4.7.1 编辑器解析通过，headless 运行约 1.9 秒退出；实际设置窗口识别到 `ChatGPT` 及 7 个可见应用，没有再出现 PowerShell 安全提示。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-160903`。

## 2026-08-08 主动陪伴可靠性修复

- `scripts/proactive_companion.gd`：OpenAI 兼容接口启用 JSON Object 输出，并明确使用 UTF-8 请求头；5～30 秒高频测试档要求模型本次必须开口，首次触发也按所设频率执行。
- 接口返回 `429`、网络异常、配置缺失或响应格式异常时，主动陪伴改用本地少女口吻台词兜底；台词会参考时间、养成状态与粗粒度前台应用类别，并避开最近重复内容。限流时 API 冷却 90 秒，但本地表达仍按用户设置频率继续。
- AI 请求期间若桌宠开始睡觉、出现普通气泡或打开功能窗口，完成的回复会进入待显示队列；恢复可表达状态后立即展示，不再直接丢弃。睡觉期间仍不会冒文字气泡。
- 主动气泡显示时长由 5 秒延长到 8 秒；设置窗口显示最近一次主动表达时间；`user://proactive_debug.log` 仅记录触发状态、HTTP 状态和显示结果，不包含 API Key、提示词或回复正文。
- 运行验证：`glm-4.7-flash` 曾正常返回结构化中文主动台词；免费接口出现 `429` 后，本地兜底于同一秒显示，随后在 5 秒测试档连续表达。Godot 4.7.1 编辑器解析通过。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-182342`。

## 2026-08-08 前台软件感知优化

- `tools/foreground_app_probe.cs/.exe`：在原生枚举阶段直接过滤 `Godot_v*`、`Godot` 和 `DesktopPet`，桌宠自身不再出现在探针原始输出或八个可见应用名额中。
- `scripts/foreground_app_monitor.gd`：启用感知后立即执行首次扫描；新增 ChatGPT、主流浏览器、WPS/Office、开发工具、聊天与影音软件的友好名称分类，未知进程统一为“其他应用”；桌宠自身位于前台导致 `FOREGROUND:` 为空时也能安全回退到其他可见软件。
- `scripts/proactive_companion.gd`：不再向模型传递任何原始进程名，只提供识别后的软件友好名称和粗粒度活动类别；软件切换后的首次表达以及之后约每三次表达，会要求自然结合当前软件，本地限流兜底也遵循同样规则。
- 运行验证：原生探针输出不含 Godot；首轮主动请求记录 `app_context=true`，`glm-4.7-flash` 实际生成“正在用 ChatGPT 忙吗？要是累了，就看看我吧。”以及“嘿，还在用 Edge 看网页呀？记得让眼睛休息一下哦。”。Godot 4.7.1 编辑器解析通过，常驻运行日志无脚本错误。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-191951`。

## 验证方法

运行时验证点击穿透的行为判定：点击透明区域时，焦点应落到后方窗口而非桌宠；点击角色本体时，焦点应为桌宠窗口。可用 `GetForegroundWindow`（Python ctypes 或任何窗口枚举工具）确认焦点归属。
