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

## 2026-08-08 羽毛球台词与主动颜文字

- `scripts/care_system.gd`：羽毛球台词中的复杂泰文/组合重音颜文字替换为字体安全的 ASCII 颜文字；同时清理三条养成台词里的高风险颜文字，避免再次出现方框缺字。
- `scripts/proactive_companion.gd`：主动陪伴约 72% 概率在正文末尾追加一个字体安全的 ASCII 颜文字；颜文字由客户端统一选择，模型不再自行生成复杂字符，重复台词判断会忽略颜文字差异。
- `docs/BADMINTON_MEOWA_PROMPTS.md`：记录桌面羽毛球球场背景与透明 UI/道具/特效合集的 Meowa 英文提示词、生成设置、验收标准和导出方式。
- 运行验证：Godot 4.7.1 编辑器解析通过；主动陪伴实际输出“在用 ChatGPT 呀？那我就在旁边乖乖陪着你。 (^o^)”，日志记录 `kaomoji=true`，常驻运行无脚本错误。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-204647`。

## 2026-08-08 可玩桌面羽毛球小游戏

- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-210824`。
- `assets/minigames/badminton/packages/`：归档用户提供的球场与 UI/特效原始 ZIP；同目录保留完整 Meowa 导出源文件，`runtime/` 下整理为一张语义化球场图和 27 个运行时 UI/道具/特效 PNG。
- `scripts/badminton_game_panel.gd`：新增独立 `960x720` 普通层级无边框游戏窗口，提供轻松/认真/挑战三档难度、鼠标跟随球拍、点击或快速挥动回击、透视飞行轨迹、落点提示、对手移动与回球、完美回击、扣杀蓄力、连击、先到 5 分、暂停、重开、结算和悬停动效。
- 场内对手复用桌宠现有 `idle` 与 `badminton` 动画；主桌宠在比赛开始后进入持续羽毛球活动，比赛结束或关闭窗口后恢复待机。
- `scripts/pet.gd`：养成窗口“娱乐 → 羽毛球”改为打开小游戏；小游戏期间暂停主动陪伴插话并收起养成/聊天/设置窗口。打开时会把主桌宠排到游戏窗口侧边，避免置顶窗口挡住球场，关闭后恢复原位置；小游戏打开时 `Esc` 不再触发主程序调试退出。
- `scripts/care_system.gd`：比赛结束按胜负和最长回合增加少量心情、好感并保存本地养成状态；重开后的每局分别结算。
- 大图 `TextureRect` 必须先设置 `EXPAND_IGNORE_SIZE` 再赋目标尺寸，否则 Godot 会先按 3072x2304 原图最小尺寸夹紧控件，造成地图和 UI 只显示左上角。本轮已统一修正球场、计分板、弹窗和提示牌的构建顺序。
- 调试直达小游戏：`godot --path "D:\game creat\DesktopPet" -- --show-badminton-game`；正常入口仍是右键打开“她的日常”，选择娱乐中的羽毛球。
- 运行验证：Godot 4.7.1 编辑器解析通过；实测养成入口、三档选择、开始比赛、鼠标跟拍、点击回球、连击与扣杀蓄力、暂停/继续、`Esc`、关闭恢复均正常。测试连续回击达到连击 2、扣杀 32%；`logs/badminton_runtime.log` 与 `logs/care_entry_runtime.log` 无脚本错误或警告。
- 视觉 QA：`logs/badminton_final_no_overlap.png` 为难度页，`logs/badminton_native_match_late.png` 为球在近场飞行画面，`logs/badminton_after_autoplay.png` 为实际回击和 HUD 更新画面，`logs/badminton_pause_final.png` 为暂停页。

## 验证方法

运行时验证点击穿透的行为判定：点击透明区域时，焦点应落到后方窗口而非桌宠；点击角色本体时，焦点应为桌宠窗口。可用 `GetForegroundWindow`（Python ctypes 或任何窗口枚举工具）确认焦点归属。

## 2026-08-08 羽毛球窗口细化与完整音频

- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-221759`。
- `scripts/badminton_game_panel.gd`：游戏内容保持 `960x720`，原生窗口扩为 `984x744`，新增 12px 奶油粉双层边框；边框可拖动窗口，球拍坐标同步扣除内容偏移。
- 计分板回合数字按源图爱心中心重新定位到运行时约 `(496, 47)`；视觉 QA 见 `logs/badminton_frame_and_heart_qa.png`。
- `scripts/companion_settings_panel.gd`：移除大按钮 `StyleBoxTexture` 的错误 90px 上下边距，并将底部按钮调整为完整的 `390x195`，花边、蝴蝶结和文字不再被切割；视觉 QA 见 `logs/settings_buttons_fixed_qa.png`。
- `assets/minigames/badminton/runtime/audio/`：接入一首约 173.453 秒的循环 BGM 和 9 个事件音效，覆盖 UI 确认、发球、普通击球、完美回击、扣杀、双方得分及胜负。
- BGM 默认 `-12 dB`、音效默认 `-4 dB`；窗口打开开始播放，暂停菜单同步暂停/恢复，窗口关闭停止。音频支持运行目录中的 OGG、MP3 或 WAV 同名替换。
- `docs/BADMINTON_AUDIO_MEOWA_PROMPTS.md`：记录本次英文提示词、Meowa 音乐/音效包生成步骤、语义化文件名与验收标准；原始生成结果保留在 `outputs/meowa-badminton-audio-20260808/`。
- `tools/badminton_audio_qa.gd`：自动检查 10 个运行时音频是否可加载、时长是否有效以及 MP3 循环标记；Godot 4.7.1 实测全部通过。
- 运行验证：Godot 编辑器导入和脚本解析通过；真实比赛、暂停与恢复正常，`logs/badminton_audio_runtime.err.log` 无错误。最终画面见 `logs/badminton_audio_live.png` 与 `logs/badminton_audio_pause_live.png`。

## 2026-08-08 用户生成羽毛球音频替换

- 替换前完整稳定版备份：`D:\game creat\DesktopPet_backup_20260808-230433`；源项目与备份均为 `3021` 个文件、`189044917` 字节。
- `assets/minigames/badminton/packages/audio_user_20260808/`：归档用户在 Meowa 中生成的 10 个中文原名 MP3，并使用 `.gdignore` 避免 Godot 重复导入归档副本。
- `assets/minigames/badminton/runtime/audio/`：替换为用户版 BGM、UI 确认、发球、普通击球、完美击球、扣杀、双方得分及胜负音效；现有游戏逻辑和音量设置不变。
- 新 BGM 实测 `136.960` 秒，九个音效均为 `1.000` 秒；`tools/badminton_audio_qa.gd` 验证全部可加载且 BGM 可开启循环。
- 导入日志：`logs/badminton_user_audio_import.log`；自动检查日志：`logs/badminton_user_audio_qa.log`。需要恢复旧版时，从上述稳定版备份复制 `assets/minigames/badminton/runtime/audio/` 即可。

## 2026-08-08 羽毛球花边框与气泡出场动效

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260808-232125`；源项目与备份均为 `3036` 个文件、`190715186` 字节。
- `assets/minigames/badminton/runtime/ui/court_floral_frame.png`：从现有“她的日常”面板本地整理出的 `960x720` 透明花边层，保留顶部蕾丝、底部爱心花边与两角玫瑰，没有调用 Meowa。
- `scripts/badminton_game_panel.gd`：花边层位于球场角色上方、HUD 与弹窗下方，既能压住场景边缘又不会遮挡比分、暂停/关闭按钮和操作文字；原生外沿由 12px 双线框缩为 8px 单线粉边。
- `scripts/speech_bubble.gd`：所有普通互动与主动陪伴气泡显示前先建立完整可点击区域，再用 0.20 秒淡入和 0.24 秒的 96%→100% 轻弹呈现；隐藏仍即时完成，避免透明残影继续拦截鼠标。
- 视觉 QA：`logs/badminton_floral_frame_live.png`、`logs/bubble_fade_mid_qa_v2.png` 和 `logs/bubble_fade_complete_qa_v2.png`；Godot 4.7.1 导入和脚本解析通过，运行日志无错误。

## 2026-08-09 羽毛球外置花边与小狗系统素材规划

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260809-001916`；源项目与备份均为 `3078` 个文件、`196770231` 字节。
- `scripts/badminton_game_panel.gd`：游戏内容继续保持 `960x720`，原生窗口使用 `54px` 外部装饰空间；原先压在球场内部的花边已替换为窗口最外侧的上下装饰层，球场内不再夹入大面积装饰底板。
- `assets/minigames/badminton/runtime/ui/window_outer_floral_frame.png`：上下蕾丝和爱心花边增加奶白不透明衬底，避免透明窗口位于深色桌面时把蕾丝孔洞显示成黑色；中央球场区域仍透明。
- `scripts/pet.gd`：打开扩大后的羽毛球窗口时增加工作区边界钳制，防止窗口在小屏幕或任务栏附近越界。
- `docs/DOG_SYSTEM_MEOWA_PROMPTS.md`：新增白色线条小狗的身份参考、五方向、首批动作、淡蓝 UI、家具道具与反馈特效的英文提示词和低额度生成顺序；同时记录巨龙骑乘彩蛋的右向飞行参考图提示词。
- 运行验证：Godot 4.7.1 重新导入和脚本解析通过；真实窗口下完成开始比赛、球拍跟随、暂停、外框拖动和关闭恢复检查。视觉 QA 见 `logs/badminton_outer_frame_final_live.png`、`logs/badminton_outer_frame_gameplay_live.png` 和 `logs/badminton_outer_frame_pause_live.png`。

## 2026-08-09 羽毛球窗口回退

- 按用户要求将 `scripts/badminton_game_panel.gd` 精确恢复为 `DesktopPet_backup_20260808-232125` 中的版本，即两次花边实验之前的 `960x720` 球场与 `12px` 奶油粉双层边框。
- 删除不再使用的 `window_outer_floral_frame.png`；用户版羽毛球 BGM、九个音效、玩法逻辑、计分板定位和设置窗口按钮修复均保留。
- Godot 4.7.1 导入检查退出码为 0；实际窗口尺寸恢复为 `984x744`，视觉 QA 见 `logs/badminton_rollback_live.png`。

## 2026-08-09 骑龙飞行隐藏彩蛋

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260809-020510`；源项目与备份均为 `3124` 个文件、`204900503` 字节。
- `assets/activities/dragon_ride/`：归档用户提供的“骑着巨龙资源包”，接入 `16` 帧透明像素动画；运行时以 `8 FPS` 循环，单轮约 `1.6` 秒。
- `scripts/companion_settings_panel.gd`：彩蛋隐藏在陪伴设置原有“重新识别”按钮中；按钮单击功能、外观和动画不变，`3.2` 秒内连续点击 `5` 次才发出触发信号，关闭设置窗口会清空未完成的连击。
- `scripts/pet.gd`：触发后先显示骑龙剧情台词，再进入约 `18` 秒的桌面飞行；窗口以约 `165px/s` 横向巡航、轻微上下起伏并在屏幕右侧飞出后从左侧重新进入。飞行中点击角色可提前降落，结束后恢复原位置、待机和点击穿透。
- 剧情气泡带短暂优先级锁，主动陪伴回复不会覆盖起飞和降落台词；调试直达参数为 `--show-dragon-ride`。
- Godot 4.7.1 导入与脚本解析通过；真实设置按钮五连点会收起设置并触发起飞，视觉 QA 见 `logs/dragon_secret_dialogue.png` 和 `logs/dragon_secret_flight.png`。

## 2026-08-09 小狗陪伴系统 1.0

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260809-111522`；源项目与备份均为 `3194` 个文件、`207931344` 字节。
- `assets/dog/packages/`：归档用户提供的淡蓝 UI、家具、人狗互动、八向行走和待机五个原始 ZIP，并用 `.gdignore` 避免 Godot 重复导入归档副本；`assets/dog/source/` 保留完整 Meowa Godot 导出源文件，未改写原始素材。
- `scripts/dog_companion.gd`：新增 `128x128` 原生透明置顶小狗窗口。小狗以 `2x` 最近邻显示 `64x64` 像素帧，支持 8 帧待机、八方向各 8 帧散步、屏幕边缘转向、玩球加速、左键摸摸、拖动和右键打开小屋。
- 小狗窗口按当前动画帧的 Alpha 轮廓生成点击区域，透明背景穿透到后方应用；拖动期间临时接管窗口，松手后恢复逐帧穿透。
- `scripts/dog_home_panel.gd`：新增可拖动的淡蓝“小雪球的小屋”普通层级窗口，使用生成 UI 的大面板、预览框、状态条和关闭按钮；狗粮盆、水盆、球与软床分别提供喂点心、喝水、玩球和休息反馈，按钮仅做缩放/轻摆，不使用透明度悬停动画。
- `scripts/pet.gd`：右键菜单新增“小雪球的小屋”；点击小狗在冷却允许时播放用户提供的 16 帧人狗合成互动约 4.8 秒，独立小狗会临时隐藏，结束后回到女孩脚边。主动陪伴在小屋或人狗互动期间不会插话。
- 调试直达小屋：`godot --path "D:\game creat\DesktopPet" -- --show-dog-home`。
- 验证方式改为资源结构检查 → 直接实现 → Godot headless 导入/运行 → 单次最终画面检查，不再反复截图或模拟鼠标点击。本轮 Godot 4.7.1 编辑器导入、普通 headless 运行和小屋直达运行均退出码为 0；可见实例日志无脚本错误，最终画面为 `logs/dog_companion_smoke.png`。

## 2026-08-09 小狗方向、领养与主动互动 1.1

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260809-114659`；源项目与备份均为 `3495` 个文件、`236078190` 字节。
- `assets/dog/packages/directions/`：归档用户重新分类的八个原始 ZIP；`assets/dog/source/directions/` 保留八份独立 Godot 导出。每个方向均为 `64x64`、8 帧、8 FPS，运行时直接按 `left/right/down_left/down/down_right/up_right/up/up_left` 路径加载，不再根据旧合并包编号猜方向。
- 修正后的资源编号关系为：左 `1786212275164`、右 `1786212452832`、左下 `1786244060394`、下 `1786212524262`、右下 `1786212560196`、右上 `1786244074452`、上 `1786244089872`、左上 `1786244156078`。
- `scripts/dog_companion.gd`：新增持久化领养状态。首次无 `user://dog_companion.cfg` 时小狗不会直接出现；领养后保存 `adopted/active`，支持回窝隐藏、叫出恢复。小狗以女孩附近为活动中心，超过约 `180px` 主动跟回，最远活动半径约 `300px`。
- 人狗互动改为两段式：小狗先以约 `92px/s` 走到女孩脚边，抵达后才隐藏独立窗口并播放 16 帧合成互动；首次主动互动在领养后约 9～16 秒，之后约 30～55 秒随机触发。用户左键摸小狗也走同一套靠近流程，不再从远处突然切换动画。
- `scripts/dog_home_panel.gd`：首次显示“流浪小狗领养处”，复用爪印按钮完成领养；领养后恢复食物、饮水、玩球和休息功能，并新增狗窝按钮在“回窝/叫出来”之间切换。女孩右键菜单同步提供“小屋”和“回窝/叫出”入口。
- 小屋重复打开时不再重播透明度 Tween；每次打开、隐藏或重复右键都会恢复 `Color.WHITE`、稳定缩放和完整鼠标接收区域，解决透明且无法点击的问题。标题、状态、预览名称和两排物品文字已避开蝴蝶结、爱心花边与底部装饰。
- 尚未领养时不创建小狗原生窗口；透明窗口标志只在领养或重新叫出、窗口实际出现后设置，避免 Windows DisplayServer 对不存在窗口的报错。
- `scripts/pet.gd`：新增五条本地小狗话题、主动靠近调度、领养剧情台词和回窝反馈；`scripts/proactive_companion.gd` 接收“小雪球是否已领养、是否在桌面”的结构化状态，AI 与本地限流兜底都可以自然谈到小狗，但不虚构屏幕或具体行为。
- 调试参数：`--show-dog-home` 直达领养/小屋窗口，`--adopt-dog --show-dog-interaction` 在隔离 `APPDATA` 下验证领养、靠近和互动完整流程。
- Godot 4.7.1 编辑器导入通过；无领养存档的小屋运行、隔离领养存档写入、主动靠近互动和最终回归均无脚本错误。遵循精简 QA，只进行一次最终可见检查，记录为 `logs/dog_adoption_panel_final.png`，检查后仅用坐标调整名称文字，不再追加截图。

## 2026-08-09 小狗命名与小屋窗口稳定性 1.2

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260809-122130`；备份包含 `3781` 个条目、文件总计 `237156659` 字节。
- `scripts/dog_companion.gd`：`user://dog_companion.cfg` 新增持久化 `name`；首次领养必须输入名字，领养后仍可改名，名称限制为 8 个字符。旧存档没有 `name` 时使用“小狗”作为显示称呼，不自动覆盖用户存档。
- `scripts/dog_home_panel.gd`：预览区新增名字输入框与淡蓝确认按钮；未领养时输入名字后完成领养，已领养时可随时保存新名字。原生小屋已经可见时，重复打开不再重设 `Window.mode`、透明标志或播放开窗 Tween，只恢复鼠标接收并聚焦，避免 Windows 下窗口变成透明空壳。
- `scripts/pet.gd`：女孩右键菜单、小屋标题、回窝/叫出提示、人狗互动气泡、养护反馈和主动陪伴事件全部改用动态名字；`scripts/proactive_companion.gd` 的模型上下文与本地兜底台词同步读取 `dog_companion.name`，代码中不再硬编码旧称呼。
- 调试参数新增 `--reopen-dog-home`，用于在 `--show-dog-home` 后自动再次打开小屋并覆盖重复打开分支，不需要模拟鼠标点击。
- Godot 4.7.1 编辑器解析通过；隔离存档自动领养后正确写入 `name="测试小狗"`，旧版无名存档及重复打开小屋的 headless 回归均退出码为 0，日志中无脚本错误。

## 2026-08-09 小狗自然动作 1.3

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260809-125636`；备份包含 `3801` 个条目、文件总计 `237520969` 字节。
- `assets/dog/packages/actions/` 归档用户提供的睡觉待机、睡觉过渡、坐下待机、坐下过渡和开心五份原始 ZIP；`assets/dog/source/actions/` 保留对应 Meowa Godot 导出。五套均为透明 `64x64`、8 帧素材。
- `scripts/dog_companion.gd`：桌面小狗显示比例从 `2.0` 调整为 `1.7`，透明点击轮廓继续按缩放后的逐帧 Alpha 计算。状态机新增坐下、睡觉、起身和开心状态；坐下与睡觉过渡非循环，结束后进入各自待机，离开时倒放过渡。
- 小狗在普通待机结束后约 `24%` 概率坐下、`10%` 概率睡觉；坐姿持续约 `6-11` 秒，睡眠持续约 `12-24` 秒。喂食、喝水、领养和从窝中叫出会循环播放开心动作约 `2.6` 秒，“回窝休息”会直接进入睡觉链路。
- `tools/dog_actions_qa.gd`：验证五套动画存在、每套 8 帧、循环标记、开心反馈，以及睡下/醒来、坐下/站起完整状态切换。最终输出 `DOG_ACTIONS_QA_OK animations=5 frames_each=8 scale=1.7`。
- `docs/DOG_SYSTEM_MEOWA_PROMPTS.md`：新增拖动真实桌面窗口的分层实现、两套小狗拉扯动画提示词，以及女孩训斥和小狗认错的分层生成流程与英文提示词。
- Godot 4.7.1 资源导入和脚本解析通过；完整桌宠场景在隔离领养存档下运行 20 秒退出码为 0，无脚本错误。

## 2026-08-09 小狗回窝话题门控

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260809-134019`；备份包含 `3913` 个条目、文件总计 `237990293` 字节。
- `scripts/proactive_companion.gd`：只有 `dog_companion.active=true` 时，AI 与本地兜底才允许主动谈到小狗。回窝状态不再加入“正在窝里休息”候选，并过滤近期小狗互动与小狗台词，避免弱模型顺着旧上下文继续谈论。
- AI 请求若在小狗回窝前已经发出，返回后会按当前状态再次校验；含动态名字或小狗关键词的返回会被丢弃并换成本地普通陪伴台词。已经排队等待气泡结束的小狗消息也会在回窝状态同步后立即清除。
- `scripts/pet.gd`：小狗可用状态变化时立即刷新主动陪伴上下文，消除 `send_home()` 与下一帧常规上下文更新之间的竞态窗口。用户主动执行回窝时的确认气泡仍保留。
- `tools/proactive_dog_home_qa.gd`：覆盖回窝后的队列清理、近期上下文过滤、本地候选过滤和重新叫出后的话题恢复。最终输出 `PROACTIVE_DOG_HOME_QA_OK inactive_suppressed=true active_restored=true`，Godot 4.7.1 脚本解析通过。
## 2026-08-11 本地音乐播放器检测与音乐中心 1.0

- `assets/music/`：归档用户提供的 `音乐播放器ui.zip`，完整 Godot 导出保存在 `source/`，运行时语义化素材位于 `runtime/ui/`；主窗口使用 1678x951 花边播放器面板缩放到 820x465，文字与状态由 Godot 原生字体绘制。
- `tools/music_session_bridge.cs/.exe`：通过 Windows GSMTC 读取 QQ音乐、网易云音乐媒体会话，返回来源、歌名、歌手、专辑、播放状态、进度、时长、控制能力和封面；支持播放、暂停、上一首、下一首及跳转进度。桥接器仅读取 Windows 已公开给系统媒体控件的信息，不读取播放器账号、Cookie 或歌单。
- `tools/build_music_session_bridge.ps1`：桥接器可复现构建脚本；系统限制 PowerShell 脚本时使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build_music_session_bridge.ps1`。
- `scripts/music_session_monitor.gd`：约 1.5 秒异步轮询桥接器，主线程不等待外部进程；命令与状态读取串行执行，并在播放中估算平滑进度。
- `scripts/music_lyrics_service.gd`：根据歌名、歌手和时长匹配 QQ音乐搜索结果，达到可信阈值后获取同步歌词；匹配失败时不显示可能错误的歌词。当前歌词仅保存在运行期内存缓存。
- `scripts/music_player_panel.gd` + `music_progress_control.gd`：新增可拖动音乐中心，支持封面、来源、播放状态、原生高清文字、三行同步歌词、播放控制和真实可移动玫瑰进度条；窗口层级为普通窗口，关闭/最小化后可再次打开，打开和按钮悬停动画不改变透明度。
- `scripts/pet.gd`：右键菜单新增“音乐中心”；检测到播放后，空闲桌宠会持续循环现有 16 帧听歌动画，暂停或播放器停止后回到待机。睡觉、羽毛球、掌机、骑龙和小狗互动优先，不会被音乐状态强制打断；首次播放和部分切歌会用歌曲名主动说话。
- 验证：C# 桥接器重新编译成功；无活动媒体会话时返回结构化空状态；`tools/music_feature_qa.gd` 用“晴天 / 周杰伦 / 269秒”真实请求获取并排序 63 行同步歌词；Godot 4.7.1 新脚本逐个 `--check-only` 通过，音乐窗口实际启动日志无脚本错误。测试时 QQ音乐进程存在但尚未注册活动 GSMTC 会话，需实际播放歌曲后验证客户端提供的封面与控制能力。
- 本轮修改前完整备份：`D:\game creat\DesktopPet_backup_20260811-225203`。
- 音乐窗口首次实机显示发现缩放中心未补偿，导致底图整体向右下偏移、文字与底图分层；`music_player_panel.gd` 已改为统一左上角布局原点，并在打开动画中同时补偿缩放位置。修复前备份：`D:\game creat\DesktopPet_backup_20260811-231635`，修复版实机启动日志无脚本错误。

## 2026-08-11 音乐中心控制区修正

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260811-232421`。
- `tools/build_music_player_background.ps1` 从原始面板的干净内层纹理重建底部区域，生成 `player_panel_clean.png`；移除了素材中烘焙的静态进度条和七个重复控制按钮，保留外框、花边、角落玫瑰与两侧爱心。
- `music_player_panel.gd` 改为上一首、单一播放/暂停、下一首三个真实按钮；中央按钮根据系统播放状态切换播放与暂停图案，不再同时出现两个功能相反的按钮。左上角来源文案只显示 `QQ音乐`、`网易云音乐` 或等待状态。
- 删除进度条下方的白色 `ColorRect` 遮罩。`music_progress_control.gd` 在拖动期间保持用户位置，不再被逐帧媒体状态覆盖；松手后立即显示预览位置并向本地播放器发送跳转请求。QQ音乐当前通过 GSMTC 报告 `can_seek=false`，且实测会接受命令但可能不改变真实位置，因此界面允许尝试拖动，最终仍以播放器返回的真实进度为准。
- 封面加载先检查文件头再选择 PNG、JPEG 或 WebP 解码，QQ音乐的 JPEG 封面不再触发无意义的 PNG 损坏日志。
- Godot 4.7.1 资源导入、两个修改脚本的 `--check-only`、完整音乐窗口 headless 运行均通过；歌词 QA 继续返回 `MUSIC_FEATURE_QA_OK source=QQ音乐歌词 lines=63`。

## 2026-08-11 音乐元数据编码与播放顺序

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260811-233834`。
- 音乐窗口乱码并非 `ZCOOLKuaiLe-Regular.ttf` 字体损坏，而是 Windows 上 Godot `OS.execute` 按系统代码页接收了桥接器强制输出的 UTF-8。`music_session_bridge.cs` 现将所有非 ASCII 字符写成 JSON `\uXXXX` 转义，协议全程只包含 ASCII，Godot JSON 解析后可稳定还原中文、日文及其他 Unicode 元数据。
- 桥接器与监控层新增 GSMTC 的随机播放、重复模式能力与命令。音乐窗口恢复一个播放顺序按钮，统一表达顺序播放、列表循环、单曲循环和随机播放，不再显示多个重复按钮；当前 QQ音乐报告 `can_repeat=false`、`can_shuffle=false`，因此按钮保留并提示在 QQ音乐内切换，不伪装成已生效。
- 左上角播放器来源从 `x=55` 移到 `x=91`，避开底图自带音符装饰；歌名、歌手、专辑继续使用固定宽度和省略号约束，修复编码后不会再以超长乱码覆盖底图。
- 新增 `tools/music_bridge_qa.gd`，实测 Godot 收到 `QQ音乐 / 同桌的你 / 胡夏`，并验证四个播放模式字段存在；歌词 QA 继续返回 63 行，音乐窗口完整 headless 运行无错误。

## 2026-08-11 音乐封面嵌入与动效

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260811-235320`。
- `music_player_panel.gd` 将封面从 `168x148` 收至 `168x132`，底边停在蝴蝶结前；新增暖白内衬、粉色细边和 CanvasItem 圆角遮罩，四角半径 `12px`，重点贴合底图相框上方两个圆弧。封面切换时仅做 `0.24s` 淡入，不改变相框布局。
- 三行歌词根据时间索引方向滑动：正常播放从下向上 `10px`，回退/拖回进度时从上向下；前后行与当前行使用不同的初始透明度，当前行附带轻微 `0.96 -> 1.0` 回弹，完整过渡约 `0.3s`。歌词错误或等待文案会先重置 Tween，避免残留偏移。
- 播放/暂停状态切换采用单按钮图标变换：先缩至 `0.82` 并旋转约 `6°`，替换图案后回弹至 `1.08` 再归位，总时长约 `0.32s`；切换时会终止同按钮的悬停 Tween，避免动画互相争抢。
- Godot 4.7.1 `--check-only` 和完整音乐窗口 headless 运行通过，无 Shader、Tween 或脚本错误。

## 2026-08-12 Windows 小正式版 0.1.0

- 发布前完整备份：`D:\game creat\DesktopPet_backup_20260812-114914`（另有同轮早期备份 `D:\game creat\DesktopPet_backup_20260812-114822`）。
- `project.godot` 增加 `config/version="0.1.0"`；`export_presets.cfg` 增加 `Windows Desktop` 预设，并排除 `.env`、日志、开发工具、交接文档和原始资源 ZIP。
- 新增 `tools/build_windows_release.ps1`、`tools/build_app_icon.ps1` 与 `release/` 发布资料。脚本会重新编译两个 Windows 辅助程序、导出 PCK、生成便携 ZIP、调用 Inno Setup 生成当前用户安装器，并输出 SHA-256 校验文件。
- 当前机器没有 Godot 4.7.1 正式导出模板，因此本版临时旁置完全同版本的官方 Godot GUI 运行时；功能已验证，但运行目录和安装包比使用正式模板更大。以后将 `windows_release_x86_64.exe` 传给构建脚本的 `-WindowsTemplatePath` 即可缩小体积。
- `scripts/foreground_app_monitor.gd` 和 `scripts/music_session_monitor.gd` 优先从主程序同目录加载辅助程序，开发环境继续回退到 `res://tools/`。`scripts/pet.gd` 修复发布运行时调用不存在的 `SpriteFrames.get_animation_count()` 导致的启动错误。
- 正式产物：`dist/DesktopPet-0.1.0-Setup.exe`、`dist/DesktopPet-0.1.0-Portable.zip`、`dist/SHA256SUMS.txt`。安装器支持开始菜单、桌面快捷方式、可选开机启动和 Windows 设置中的卸载入口，默认安装到当前用户目录且无需管理员权限。
- 便携版使用隔离的 `APPDATA/LOCALAPPDATA` 启动 15 秒，进程持续运行，主动陪伴采用新用户默认 `90.00s`，日志无 `SCRIPT ERROR` 或 `ERROR`。安装器随后完成静默安装、安装目录启动 15 秒和静默卸载，三个阶段退出码均为 `0`，卸载后安装目录已移除。
- PCK 已按 `.env` 中的真实密钥值做二进制扫描，命中数为 `0`；便携包不包含 `.env`、开发者 API Key 或已有用户存档。安装器尚未使用项目方代码签名证书，陌生电脑首次下载时可能出现 Windows SmartScreen 提示；正式公开发行建议购买代码签名证书并签署最终安装器。

## 2026-08-12 Windows Release 透明角色与任务栏图标修复

- 修复前完整备份：`D:\game creat\DesktopPet_backup_20260812-125427`。
- 初版包错误地把 Godot 4.7.1 编辑器 GUI EXE 当作便携运行时，导致窗口标题含 `(DEBUG)`、任务栏使用 Godot 默认图标，并在 Release 资源重映射下暴露透明角色问题。现在已下载官方 `Godot_v4.7.1-stable_export_templates.tpz`，核对官方 SHA-256 `86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72` 后提取 `windows_release_x86_64.exe` 到 `.release-cache/`。
- `export_presets.cfg` 改为显式使用正式 Windows Release 模板；`tools/build_windows_release.ps1` 改用 `--export-release`，缺少正式模板时直接失败，不再允许编辑器 EXE 降级。构建开始前若 `build/windows` 被运行中的桌宠占用且无法清空，也会直接失败，防止 `DesktopPet.exe~RF*.TMP` 被误收入安装包。
- 角色透明的根因是基础待机动画原先在运行时用 `DirAccess` 扫描 `assets/sprites/**/*.png`。Release 导出把 PNG 转成内部纹理资源后，原始 `.png` 不再能按开发目录方式枚举，因此角色动画库为空，但气泡仍能显示。新增 `tools/build_pet_sprite_frames.gd`，构建前把待机、移动、睡觉、娱乐、骑龙和人狗互动合并为 `assets/runtime/pet_sprite_frames.tres`；当前共 19 个动画、185 帧。`scripts/pet.gd` 发布运行时优先加载该静态资源，开发环境仍保留动态构建回退。
- `project.godot` 的运行图标改为 `release/app_icon.png`；`tools/build_app_icon.ps1` 现在生成包含 `16/32/48/64/128/256` 六个 PNG 图层的 ICO。Godot 导出不再报告图标尺寸缺失，安装后 EXE 提取图标已确认为桌宠头像。
- 最终 Release 透明窗口使用 Windows `PrintWindow(PW_RENDERFULLCONTENT)` 检查合成表面：窗口标题为 `DesktopPet`，角色主体采样像素 3137、彩色主体像素 1437，日志错误数 0。安装包隔离安装后的 EXE 再次检查为主体像素 3138、彩色像素 1454，安装目录无 `.env`、临时 EXE 或 `*.TMP`；静默卸载退出码 0 且安装目录已移除。

## 2026-08-12 音乐封面前景遮挡修复

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260812-132748`。
- `scripts/music_player_panel.gd` 将封面区域调整为 `168x166`，使封面继续延伸到相框底部装饰后方；新增独立的前景装饰层，使用 `bow_large.png` 和左右两枚 `rose.png` 覆盖封面底部，形成蝴蝶结与玫瑰压在唱片封面前面的真实层级。
- `tools/build_music_player_background.ps1` 会清除原底图中烘焙的相框底部蝴蝶结与花簇，避免运行时前景装饰出现双层重影；`tools/build_windows_release.ps1` 在发布构建前自动重建播放器底图。
- 播放器来源标签改用 `Microsoft YaHei UI` / `Segoe UI` 系统字体，避免原可爱字体把 `QQ音乐` 的拉丁字母 `Q` 显示成方框装饰字形。
- 正式 Windows Release 已重新构建。安装器 SHA-256 为 `83d5e34c14d6fa4ea854df19fb79ebc10b135406de74f09df38d39fbef473fef`，便携包 SHA-256 为 `b36e049350982bf4a825fc7de70d039e8940c8fd3ea853ad660ae59e51ca2d4a`。

## 2026-08-12 沉浸音乐、听歌陪伴与屏幕感知 1.0

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260812-144003`。
- `scripts/music_player_panel.gd` 新增沉浸全屏切换按钮；`scripts/immersive_music_view.gd` 提供覆盖当前显示器的无边框大屏布局，包括大封面呼吸、五行同步歌词、歌词方向过渡、播放进度、上一首/播放暂停/下一首/播放顺序、`Esc`/`F11` 退出与桌宠听歌心声。退出后恢复原 `820x465` 透明花边窗口及原位置，避免透明空壳。
- `scripts/proactive_companion.gd` 的主动意识上下文加入当前歌曲、歌手、来源、进度和当前歌词。切歌后约 5 秒、连续播放约 75 至 150 秒会低频触发一次具体听歌感受；API 失败时本地兜底也会引用当前歌词。听歌动画与音乐全屏不再阻断主动陪伴，全屏时台词进入播放器左下方心声区，普通桌面仍使用气泡。
- `scripts/screen_awareness_service.gd` + `screen_awareness_panel.gd` 新增默认关闭的屏幕画面感知 1.0。入口位于“陪伴设置 -> 画面感知”，与只读进程名的“前台应用感知”明确分开。支持“立即看看”和可选每 10 分钟自动观察；截图仅在内存中缩放到最长边 1280、JPEG 低细节发送，既不写磁盘也不把画面正文写进陪伴记忆。自动观察只在所有功能窗关闭且桌宠空闲时计时。
- 屏幕感知复用 AI 聊天接口和 Key，可单独填写视觉模型名；留空则使用聊天模型。文本模型不支持图片时会用桌宠口吻提示换视觉模型，不会假装看到了画面。屏幕分析提示词禁止抄录密码、密钥、聊天内容、账号和私人文件名，只返回场景概述、建议和一句桌宠台词。
- 新增 `tools/companion_music_screen_qa.gd` 和 `tools/music_fullscreen_qa.gd`。Godot 4.7.1 脚本解析、音乐上下文/歌词兜底/隐私门逻辑、全屏窗口 `1920x1080` 与退出恢复均通过；普通播放器、屏幕授权窗、全屏播放器三种直达运行日志错误数为 0。
- 正式包已重建：安装器 SHA-256 `dee88b47176abb53204f113e906058a9eead84192a8c359f3c9321ca5786fd68`，便携包 SHA-256 `32c53432d4c265e5c077283477f8a5ba16ad7f5ad105bcaaf858a5d5118821c7`。

## 2026-08-12 画面感知 2.0

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260812-200958`（1837 个文件，130289671 bytes）。
- 参考豆豆 AI 游戏助手公开页面的场景识别、主动提示、攻略问询、成就赞赏、情景共情和跨场景记忆思路，将原先的单截图描述升级为“识别当前任务和重要事件，再决定是否打扰”。新增游戏、工作、日常和自动四种模式。
- 新增 `scripts/screen_change_detector.gd`：自动观察平时只在本地比较 `48x27` 灰度采样，不调用 API；明显变化后等待两次稳定采样，再取约 1.5 秒内的三个关键帧。新增 `scripts/screen_context_memory.gd`：只在内存保留最多 8 条结构化任务摘要，30 分钟自动过期，敏感结果不进入记忆。
- `scripts/screen_awareness_service.gd` 支持应用切换、明显变化、定时复查和手动观察原因；关键帧最长边压到 1120、JPEG 质量 0.68，仅用内存 buffer 上传，从不写截图文件。分析结果增加场景类型、事件、置信度、重要度、任务摘要和敏感标志；低于 0.62 置信度或低优先级重复场景保持安静，台词等待桌宠空闲后再显示。
- 感知设置窗扩至 `680x477`，分为“智能观察”和“隐私与额度”两页。支持总授权、智能观察、立即暂停、四种模式、单独视觉模型、每天 1 至 60 次 API 上限、敏感应用黑名单、上传原因/状态提示及清空短期画面记忆。默认仍关闭；暂停或命中黑名单时不会截屏和上传。
- 前台进程监控现在由主动陪伴或画面感知任一功能按需启用；修复重复同步时每帧重置进程轮询的问题。`proactive_companion.gd` 保存陪伴设置时先加载同一配置文件，避免覆盖画面感知配置段。
- 新增 `tools/screen_awareness_2_qa.gd`。所有修改脚本 `--check-only`、完整 headless 项目运行、变化检测/短期记忆/额度/黑名单/置信度/不落盘 QA、预编译动画生成及 Windows Release 导出均通过。最终构建日志为 `logs/screen_awareness_2_build.log`，无 `SCRIPT ERROR`、`Parse Error`、`Compile Error` 或 Godot `ERROR:`。
- 正式 Release 用隔离用户目录和 `--show-screen-awareness` 直达参数启动 7 秒，进程持续运行且日志无错误；便携 ZIP 不包含 `.env`、API/陪伴配置或临时 EXE，PCK 对开发 `.env` 中的密钥扫描无命中。暂停开关会立即终止尚未完成的关键帧采集或视觉请求。安装器 SHA-256 `92a0bad49e274435fb1e5e7ff905d6e426ecc7cb1644db9048550ff10e492132`，便携包 SHA-256 `4228600d818fe45ec57fb4dad75bed179723b8694f618be0d0e6c3de7473d496`。

## 2026-08-12 画面感知窗口布局修复

- 修复前备份：`D:\game creat\DesktopPet_backup_20260812-210352`。
- 初版把 `1478x1037` 设计坐标、`680x477` 原生窗口和根节点缩放混用，导致子窗口内容裁切、开关文字重叠。`screen_awareness_panel.gd` 已改为统一 `680x477` 真实像素布局：背景仅由 TextureRect 缩放，所有文字、按钮和点击区域使用相同坐标系；授权/智能观察与暂停/陪伴模式分成两行，视觉模型独占一行。
- 用 Windows `PrintWindow` 直接抓取真正的 `680x477` 子窗口验证，标题、标签页、三组开关、模式、模型输入、状态和底部按钮均完整，无重叠或越界。标题去掉可爱字体显示异常的拉丁数字；服务启动时会根据授权、自动观察和暂停状态显示正确文案。

## 2026-08-12 陪伴设置整合、DeepSeek 视觉分流与音乐全屏修复

- 修改前完整备份：`D:\game creat\DesktopPet_backup_20260812-211303`。
- `scripts/companion_settings_panel.gd` 重做为统一 `740x520` 原生像素窗口，包含“陪伴 / 画面感知 / 隐私与接口”三个页签。主动陪伴频率、夜间安静、前台应用感知、陪伴记忆、重新识别五连击骑龙彩蛋、画面授权、智能观察、临时暂停、模式、每日额度、敏感应用名单、画面短期记忆和视觉接口均在同一窗口内。页签创建在页面之后且 `z_index=50`，不会再被透明页面挡住。
- `scripts/pet.gd` 调整初始化顺序：先创建 `PetScreenAwarenessService`，再注入 `PetCompanionSettingsPanel`；不再实例化独立画面感知窗口。`--show-screen-awareness` 保留为调试兼容参数，但现在直接打开“陪伴设置 -> 画面感知”。旧 `scripts/screen_awareness_panel.gd` 已删除。
- `scripts/screen_awareness_service.gd` 新增独立视觉接口配置 `user://screen_vision.cfg`，可单独保存 Endpoint、视觉模型、API Key 和是否记住 Key。聊天继续使用 `user://ai_chat.cfg` 中的 DeepSeek；画面分析使用支持图片输入的 OpenAI 兼容视觉模型。若沿用配置被识别为 DeepSeek endpoint/model，手动分析会在截图前用桌宠口吻提示，自动观察也不会进行本地屏幕采样、截图、上传或消耗每日额度。
- `scripts/music_player_panel.gd` 的沉浸模式改为原生 `Window.MODE_FULLSCREEN`。进入前保存窗口位置与尺寸，先关闭透明合成并进入当前显示器全屏；两帧后检查实际尺寸，必要时回退到无边框屏幕尺寸，再失败则完整恢复普通播放器。退出后恢复 `820x465`、原位置、透明背景、最小尺寸和不可缩放状态，不会再出现“只隐藏全屏按钮但窗口没变”的半切换状态。
- 新增 `tools/companion_settings_integration_qa.gd`、`tools/companion_settings_visual_qa.gd` 与 `tools/screen_deepseek_guard_qa.gd`；更新 `tools/music_fullscreen_qa.gd`。验证结果：三个页签可切换且按钮在页面上层；DeepSeek 路径 `captured=false local_sample=false uploaded=false usage=0`；屏幕感知 2.0 原 QA 通过；播放器实测进入 `1920x1080`，沉浸 UI 正常渲染，退出恢复 `820x465 @ 40,40`。视觉记录为 `logs/companion_settings_integrated_qa.png` 和 `logs/music_fullscreen_fixed_qa.png`。
- 正式 Release 已重建：`dist/DesktopPet-0.1.0-Setup.exe` SHA-256 `3064e2ca875489b8346b171c643ba21778b8eb7c8f55a8c50736224bfde32918`；`dist/DesktopPet-0.1.0-Portable.zip` SHA-256 `7bce30f0f91e25423a6a66a0a8bb1bb965d96e3c7a6303eb7af29e8c76426796`。便携包共 9 个发布文件，不包含 `.env`、`ai_chat.cfg`、`screen_vision.cfg` 或 `companion_settings.cfg`。
