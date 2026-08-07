# DesktopPet

DesktopPet 是一款使用 Godot 4 开发的 Windows 少女桌宠。她可以在桌面上移动、休息和表达心情，也能通过养成、小游戏、AI 对话、音乐陪伴与可选的屏幕感知功能陪伴用户。

## 当前功能

- 透明桌面窗口、透明区域点击穿透与拖拽互动
- 八方向移动、待机、睡觉、听歌及多种活动动画
- 饮食、饮水、娱乐、礼物和好感度养成
- AI 聊天与主动陪伴，可配置 OpenAI 兼容接口
- 可选的前台应用检测与屏幕画面建议
- Windows 媒体会话检测、歌词、进度控制和沉浸播放器
- 桌面羽毛球小游戏
- 可领养、命名和互动的小狗伙伴

## 开发环境

- Godot 4.7.1
- GDScript
- Windows 10/11
- PowerShell、.NET Framework 编译器和 Inno Setup 用于 Windows 发布构建

## 本地运行

1. 使用 Godot 4.7.1 打开项目目录。
2. 运行 `scenes/pet.tscn`，或直接运行项目主场景。
3. AI 功能通过应用内设置填写接口地址、模型和 API Key。请勿将真实密钥写入仓库文件。

## 构建

Windows 发布脚本位于 `tools/build_windows_release.ps1`。构建产物会写入 `build/` 和 `dist/`，这些目录不会提交到 Git。

## 隐私

屏幕感知默认关闭，启用前需要用户明确授权。项目的 `.env`、本地配置、密钥、构建缓存和运行日志均被 `.gitignore` 排除。

## 许可证

源代码按 [MIT License](LICENSE) 发布。项目中的字体、音频以及生成或第三方美术素材可能受各自许可证或服务条款约束，复用前请查看 `release/` 中的许可与声明文件。
