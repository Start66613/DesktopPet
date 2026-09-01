# DesktopPet - 小雪球桌宠

> 会在桌面上走路、睡觉、听歌、聊天，还会陪你打羽毛球的少女桌宠。

[![Godot](https://img.shields.io/badge/Godot-4.7.1-478cbf?logo=godotengine)](https://godotengine.org/)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011-0078d4?logo=windows)](#快速开始)
[![Language](https://img.shields.io/badge/Language-GDScript-355570)](https://gdscript.com/)
[![Visibility](https://img.shields.io/badge/Repository-private-8b5cf6.svg)](#隐私与安全)

## 项目简介

DesktopPet 是一个基于 **Godot 4** 开发的 Windows 少女桌宠。它想解决的是传统桌宠“只会挂在桌面上”的单调感：小雪球会根据自己的状态移动、休息和表达心情，也能通过 AI 对话、音乐联动、可选的屏幕感知、养成互动和小游戏，成为一个有反馈、有陪伴感的小助手。整个项目以本地桌面体验为中心，AI 与感知能力均由用户自主配置和授权。

> 当前为 `0.1.0` 开发版。沉浸音乐模式正在重构中，目标是让全屏状态仍保留桌宠自由活动的陪伴感。

## 动图预览

<p align="center">
  <img src="docs/images/desktop-pet-idle.gif" width="320" alt="小雪球待机动画" />
</p>

<p align="center">小雪球的真实待机动画：由项目内帧动画导出。</p>

## 截图预览

| 桌面互动 | 音乐中心 |
| --- | --- |
| ![桌宠在桌面上弹出气泡](docs/images/desktop-pet-interaction.png) | ![少女风格音乐中心](docs/images/music-player.png) |

| 陪伴设置 | 羽毛球小游戏 |
| --- | --- |
| ![陪伴与隐私设置窗口](docs/images/companion-settings.png) | ![桌面羽毛球小游戏结算画面](docs/images/badminton-gameplay.png) |

## 功能列表

### 桌面移动与休息

- 透明无边框桌面窗口，透明像素区域可以点击穿透，不影响正常办公。
- 八方向行走、待机、睡觉、翻身、听歌、掌机、羽毛球等动画状态。
- 支持鼠标拖拽、右键菜单，以及拖拽时随鼠标产生的轻微摇晃反馈。
- 会在合适的时机休息；睡觉期间不会弹出打扰性的文字气泡。

### 心情表达与养成

- 气泡文字、颜文字、互动反馈和主动说话，表达频率可配置。
- 食物、饮料、娱乐、礼物等日常养成互动与好感度反馈。
- 少女风格可拖动窗口、按钮悬停动效与右键快捷入口。
- 隐藏彩蛋：在特定设置操作后可以触发骑龙飞行。

### AI 对话与主动陪伴

- 内置聊天窗口，支持配置 OpenAI 兼容的 Chat Completions 接口。
- 对话错误会以桌宠口吻反馈，而不是生硬的技术报错。
- 主动陪伴可结合当前状态、音乐和前台应用提供更贴近情境的表达。
- 对话密钥只保存在本机配置中，仓库不会提交 `.env`、Token 或 API Key。

### 音乐陪伴

- 读取 Windows 系统媒体会话，可联动 QQ 音乐、网易云音乐等播放器。
- 显示歌曲封面、标题、歌手、专辑、歌词与播放进度。
- 支持播放/暂停、上一首、下一首、播放顺序与进度拖动。
- 会根据歌曲切换、歌词和播放状态给出听歌反应。

### 屏幕感知与应用场景

- 支持前台应用/进程感知，可为工作、游戏、听歌场景提供上下文。
- 屏幕感知默认关闭，必须在陪伴设置中明确授权才会启用。
- 感知能力定位为辅助与陪伴，不会默认上传、保存或共享屏幕截图。

### 小游戏与小狗伙伴

- 桌面羽毛球对战：回合、得分、连击、胜负结算和音效反馈。
- 可领养、命名、回窝和管理的小狗伙伴。
- 小狗具备八方向走路、坐下、睡觉、开心等状态；小雪球会围绕它产生互动对话。

## 技术栈

| 领域 | 方案 |
| --- | --- |
| 桌面与游戏层 | Godot `4.7.1` + GDScript |
| 透明与点击穿透 | 原生透明窗口、精灵 Alpha 命中检测、Windows 输入区域控制 |
| 动画系统 | `AnimatedSprite2D`、`SpriteFrames`、多帧像素动画 |
| AI 对话 | 可配置 OpenAI 兼容 Chat Completions API |
| 音乐读取 | Windows Global System Media Transport Controls 桥接程序 |
| 本地感知 | 前台应用检测、用户授权后的屏幕状态分析 |
| Windows 发布 | Godot Export、PowerShell、Inno Setup |

项目源码主要位于：[`scripts/`](scripts)、[`scenes/`](scenes)、[`assets/`](assets) 和 [`tools/`](tools)。素材来源、运行时资源和备用资源请查阅 [素材目录](docs/ASSET_CATALOG.md)。

## 快速开始

### 方式一：直接使用 Windows 发行包

1. 从项目 Release 下载 `DesktopPet-0.1.0-Setup.exe`（安装版）或 `DesktopPet-0.1.0-Portable.zip`（便携版）。
2. 安装或解压后运行 `DesktopPet.exe`。
3. 在桌宠上右键，可打开养成、聊天、陪伴设置、音乐中心、小游戏和小狗小屋。

### 方式二：从源码运行

**环境要求**

- Windows 10 / Windows 11
- Godot `4.7.1`
- 可选：QQ 音乐或网易云音乐，用于测试本地媒体会话联动

**运行步骤**

1. 克隆仓库：`git clone https://github.com/Start66613/DesktopPet.git`
2. 使用 Godot `4.7.1` 导入项目目录。
3. 运行项目主场景，或运行 `scenes/pet.tscn`。
4. 需要 AI 对话时，在应用内设置中填写接口地址、模型名和 API Key。

### 构建 Windows 发布包

构建脚本为 [`tools/build_windows_release.ps1`](tools/build_windows_release.ps1)，产物位于：

- `dist/DesktopPet-0.1.0-Setup.exe`：Inno Setup 安装包
- `dist/DesktopPet-0.1.0-Portable.zip`：免安装便携版

`build/`、`dist/`、`.env`、本地日志、Godot 导入缓存与临时备份均已被 `.gitignore` 排除。

## 开发日志

| 时间 | 里程碑 |
| --- | --- |
| 2026-08-07 | 完成少女风格养成面板、气泡交互与睡觉状态打磨。 |
| 2026-08-08 | 完成桌面羽毛球小游戏、音效接入和花边 UI 框架。 |
| 2026-08-09 | 上线小狗陪伴系统、领养命名、小屋与骑龙隐藏彩蛋。 |
| 2026-08-11 | 完成 Windows 本地音乐播放器检测、歌词和基础控制。 |
| 2026-08-12 | 发布 `0.1.0` Windows 小正式版；加入 AI 听歌陪伴、画面感知与陪伴设置。 |
| 2026-08-29 ~ 2026-08-31 | 重构沉浸音乐模式的窗口恢复、输入处理、长文本气泡和 UI 资源整理。 |
| 下一步 | 重做真正的全屏音乐陪伴场景，让小雪球在音乐全屏中依旧可自由活动。 |

完整提交记录可在 [Commit History](../../commits/main) 中查看。

## 隐私与安全

- AI 接口、前台应用检测与屏幕感知都是可选功能，默认不强制开启。
- API Key、Token、`.env` 和本地配置不会提交到 GitHub。
- 使用第三方模型、播放器、字体、音乐、音效或生成素材前，请确认各自许可证和服务条款。
- 反馈问题时，请先打码或移除日志、截图中的个人信息。

## 开发路线

- [x] 透明桌宠、点击穿透、拖拽和八方向移动
- [x] 睡觉、对话气泡、养成系统、右键菜单与少女风格 UI
- [x] AI 聊天、主动陪伴设置、前台应用检测与屏幕感知入口
- [x] Windows 媒体会话、歌词、音乐中心与听歌陪伴
- [x] 羽毛球小游戏、小狗伙伴、骑龙彩蛋
- [ ] 重做沉浸音乐模式：桌宠自由活动、自然进出场和可交互控制
- [ ] 补充更多小狗自主互动、家具与桌面事件
- [ ] 完善多模态屏幕感知和 AI 工作/游戏助手

## 使用与素材声明

本项目为私有学习与作品开发项目，未向公众授予代码、素材或构建产物的复制、修改或再发布许可。字体、音乐、音效、生成美术和第三方素材同样可能受各自许可限制；发布或二次分发前请查看 `release/` 内的声明文件，并遵守素材来源的使用条款。
