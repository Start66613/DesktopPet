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

## 验证方法

运行时验证点击穿透的行为判定：点击透明区域时，焦点应落到后方窗口而非桌宠；点击角色本体时，焦点应为桌宠窗口。可用 `GetForegroundWindow`（Python ctypes 或任何窗口枚举工具）确认焦点归属。
