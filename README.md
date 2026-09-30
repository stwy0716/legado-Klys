<div align="center">

# 📖 Legado MD3

**使用 Flutter 构建的 Material Design 3 跨平台网络文学阅读器**

基于 [Legado](https://github.com/gedoor/legado) 与 [legado-with-MD3](https://github.com/HapeLee/legado-with-MD3)，一套代码同时运行于 Android 与 iOS。

![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-3DDC84?logo=android&logoColor=white)
![Material](https://img.shields.io/badge/Design-Material%203-6750A4)
![License](https://img.shields.io/badge/License-GPL%20v3-orange)

[最新下载](https://github.com/stwy0716/legado-K/releases) · [功能特性](#-功能特性) · [快速开始](#-快速开始) · [书源规则](#-书源规则)

</div>

---

## ✨ 功能特性

| 模块 | 能力 |
| --- | --- |
| 📚 **书架** | 列表 / 网格 / 详细网格多布局、书籍分组、批量管理、排序、一键更新、进度自动保存 |
| 🔍 **书源** | CSS / XPath / JSONPath / 正则 / JS 规则引擎，多源**并发聚合搜索**，网络 / 本地 / 二维码导入，编辑、调试、校验、分组 |
| 🌐 **发现** | 按书源浏览发现分类、分页加载、一键加入书架 |
| 📖 **阅读** | 多套配色与护眼主题，字号 / 字体 / 行距 / 缩进实时调节，多种翻页动画，点击三区、章节滑块、目录与章节内搜索、亮度调节、替换净化、内容字典、高亮标签 |
| 🔊 **朗读** | 系统 TTS 与多家云语音，独立播放器、语速音调调节、自动连播 |
| 📡 **RSS 订阅** | RSS / Atom 源管理、文章列表、已读 / 收藏、内置浏览器打开 |
| 📁 **本地书籍** | TXT / EPUB / UMD / MOBI(AZW) 导入与解析、本地目录规则 |
| 🌍 **Web 服务** | 内置 HTTP REST API 与 WebSocket，可在同一网络下管理书库 |
| ☁️ **备份同步** | 本地备份 / 恢复、WebDAV 云端同步、阅读进度同步 |
| 📊 **统计** | 今日 / 累计时长、阅读天数、近 30 天趋势与时间轴 |
| ⚙️ **其他** | 深色模式与动态取色、主题管理、缓存清理、崩溃日志、漫画阅读、角色 / 知识、二维码扫描等 |

## 🧱 技术栈

- **框架**：Flutter 3.24 / Dart 3
- **状态管理**：Provider
- **本地存储**：SQLite（sqflite）+ SharedPreferences
- **网络**：Dio（含 Cookie 管理）
- **解析**：html / csslib、自研 CSS·XPath·JSONPath·JS 规则管线
- **朗读**：flutter_tts；**网页/JS**：flutter_inappwebview
- **本地书**：epubx + 自研 UMD / MOBI 解析
- **其他**：shelf（Web 服务）、file_picker、archive、mobile_scanner、audioplayers 等

## 📂 项目结构

```
lib/
├── main.dart / app.dart        # 入口与根 Widget
├── constant/                  # 常量、MD3 主题
├── data/                      # 数据层：model / 本地数据库 / repository
├── domain/                    # 领域层：usecase 与仓库接口
├── di/                        # 依赖注入与全局状态（Provider）
├── help/                      # 核心能力
│   ├── source/                #   书源规则引擎（CSS / XPath / JSONPath / 正则 / JS）
│   ├── http/                  #   网络请求与 RSS 解析
│   ├── storage/               #   备份、WebDAV、本地书导入解析
│   ├── readaloud/             #   TTS 朗读与云语音
│   ├── web/                   #   内置 Web 服务（HTTP + WebSocket）
│   └── translate/ crypto/ config/
└── ui/                        # 界面：main / book / rss / config / backup / stats ...
```

## 🚀 快速开始

**环境要求**：Flutter `3.24`、Dart `3.x`；Android 端 Android Studio，iOS 端需 macOS + Xcode。

```bash
# 安装依赖
flutter pub get

# 运行
flutter run

# 构建 Android
flutter build apk --release                                          # 通用包
flutter build apk --release --target-platform android-arm64          # arm64 精简包

# 构建 iOS（需 macOS + Xcode）
flutter build ios --release
```

## 📥 下载安装

每个版本会在 [GitHub Releases](https://github.com/stwy0716/legado-K/releases) 发布预编译 APK：

- `app-universal-release.apk`：通用包，适配所有架构
- `app-arm64-release.apk`：arm64 专用，体积更小

> iOS 端因签名限制需自行编译安装。

## 🧩 书源规则

兼容 Legado 书源格式，支持 `{{key}}` 模板、分页与多规则组合，主要字段：

| 类别 | 字段 |
| --- | --- |
| 搜索 | `searchUrl`、`ruleSearch.bookList`、`name` / `author` / `coverUrl` / `bookUrl` / `intro` |
| 发现 | `exploreUrl`、`ruleExplore` |
| 详情 | `ruleBookInfo` |
| 目录 | `ruleToc.chapterList`、`chapterName`、`chapterUrl`、`nextTocUrl` |
| 正文 | `ruleContent.content`、`nextContentUrl`、`imageUrl` |

规则可使用 `@css:` / `@xpath:` / `@json:` 前缀、`@js:` 脚本、`||`（或）、`&&`（链式）、`@@`（取全部）及正则替换等组合语法。

## 📄 许可证

基于 **GPL-3.0** 开源，遵循原 Legado 项目的许可要求。

## 🙏 致谢

- [Legado](https://github.com/gedoor/legado) — 原版开源阅读器
- [legado-with-MD3](https://github.com/HapeLee/legado-with-MD3) — MD3 设计参考
