# AcaTerminal v0.1 · build 8 验收记录

2026-09-29，macOS 15.4.1 / Apple silicon / Swift 5.8.1，独立测试工作区。

这次在已交付 build 7 上改进 Reader 空间、项目界面、原生菜单和许可证，没有重写 ResearchObject、Zotero、引用监测、全文解析或本地存储。原 outputs/AcaTerminal 源码目录已不存在，因此从本线程交付的 build 7 源码包恢复后继续。正式用户数据库未用于测试。

## 1. Reader 问题根因与行为

旧 Reader 对 PDFSurface 设置了固定的 `maxWidth: 860`，缩放动作只修改 PDFKit 的 `scaleFactor`。窗口有更多空间时，阅读区仍受固定宽度限制；放大只会在狭窄容器里扩大内容。旧自动适配也没有表达明确的“适合可用宽度”。

现在由 ReaderViewport 管理实际 PDFView frame，由 ReaderSession 管理一个连续的相对倍率：

- 舒适模式初始使用当前可用宽度的 92%，宽模式使用 100%。
- 倍率低于 1 时，实际阅读区域与 PDF 一起扩大；达到可用宽度后，容器保持全宽，由 PDFKit 继续放大内容并提供原生水平/垂直滚动。
- 缩小时按同一公式反向经过边界，不使用视图图层缩放伪装。
- 可见目录和 Inspector 先占用各自宽度，不被 PDF 放大挤压。Focus 收起面板后重新计算可用空间。
- 每次布局前捕获物理页码及归一化横纵坐标，布局后恢复；同一个 PDFView/PDFDocument 保留选区，Evidence 坐标不变。
- 工具栏、原生菜单、PDFKit zoom responder 和 magnify/smartMagnify 入口共用 session 动作。⌘0 适合宽度，⌘+ / ⌘− 缩放，⇧⌘F 专注。

实测 1500 点可用宽度初始得到 1380 点阅读区；继续放大先填满空间，再产生原生可水平滚动的 PDF 内容。原 PDF 字节 SHA-256 保持一致。

## 2. UI 减法与原生菜单

- 项目主导航：文献 / 论证 / 动态；研究问题留在标题下。
- 列表 / 图谱放在论证内；研究变化 / 时间线放在动态内；发现从文献页进入。
- 项目列表可收起；图谱 Inspector 在选择节点后出现，可关闭。
- 发现方式、算法局限和变化定义进入展开区；OpenAlex 来源、时间和潜在关联标记仍可见。
- 推荐行保留打开阅读器、添加到项目；其他操作进入更多菜单，反馈功能保持。
- 图谱 → Claim → Evidence → Reader 第 3 页原选区，通过实际 UI 验证。
- 原生 About 显示 `v0.1（8）`；标准设置菜单保留，File 继续提供导入，Reader 提供缩放/适合宽度/搜索/专注。隐私说明、许可证移到 Help。
- 本次发现并修复中文 segmented picker 标签挤成竖排的问题，最终截图检查正常。全行命中和 Reduce Motion 继续使用已有 AcaButtonStyle / AcaMotion。

## 3. GPL 与版本

`CFBundleShortVersionString = 0.1.0`，`CFBundleVersion = 8`。LICENSE 为 GNU 官方 GPL v3 全文，项目明确采用 `GPL-3.0-only`；COPYRIGHT、README、CONTRIBUTING、PRIOR_ART、品牌说明及中英文内置说明同步。应用 Resources 内含 LICENSE.txt / COPYRIGHT.txt，Help 可打开许可证。

参考项目自身的 MIT/GPL 等许可证记录保留原样，没有引入参考项目代码。用户提供图标的来源记录仍独立保留。

## 4. 数据与新增类型

SQLite schema 仍为 **1**，JSON payload 仍为 **4**。本次仅增加可选 `ReadingPosition.readingScale`。旧记录没有该字段时，继续根据原物理 zoom 恢复，再换算为相对倍率；原 zoom 和横纵阅读位置同时保留。新增字段有合法范围校验，没有破坏性迁移。

新增应用层类型：ReaderViewport、ApplicationVersion、ReaderMenuItems、ProjectSurface、ProjectPapersView、ProjectClaimsView。没有新增网络协议或重复创建 ResearchObject / Claim / Evidence。build 7 的 ClaimRelation、DiscoveryProvider、ProjectResearchProfile、LiteratureSnapshot、LiteratureChangeSet、ResearchQuerying 等继续使用；详情见 ADVANCED_RESEARCH.md 和 ADVANCED_VERIFICATION.md。

## 5. 测试结果

当前完整通过的套件共 **138 项/组**，不是 138 个 XCTest 方法：

| 套件 | 数量 | 结果 |
| --- | ---: | --- |
| AcaChecks | 50 | 包含旧格式迁移、Zotero、引用去重、provider 隔离、Advanced 和新增阅读倍率兼容校验 |
| Reader | 17 | 页码/选区/搜索/Focus/恢复及大文件回归 |
| ReadingSpace | 25 | 两阶段缩放、侧栏空间、横向滚动、旧 zoom、重开和原 PDF 字节 |
| Document import | 9 | Word/文本/PDF 与原生批注菜单 |
| Appearance / localization / icon | 16 | 中英文覆盖、计数格式、透明图标 |
| Advanced integration | 11 | Claim/Evidence 原文跳转、发现反馈、变化与通知 claim、离线重启 |
| Citation/impact integration | 10 | 通知路由、引用导入、Reader/版本来源、历史重启 |

另核对交付 bundle 版本、GPL 文件内容、regular app 元数据与签名。UI 用独立 QA bundle、确定性研究数据和生成的 120 页 PDF，交付 App 不包含这些数据。

### 未通过或受限的测试（不计入上表）

- 本轮 LifecycleChecks 两次未完整通过，分别在 Reader 恢复和 Command-M 恢复的 `isKeyWindow` 断言失败；日志为 mini=false、visible=true、key=false、active=false。窗口已经恢复，但合成后台回调未取得应用激活。本轮没有更改 build 7 的窗口生命周期代码，也没有删除或放宽这些断言来宣称通过。
- 随后用隔离的实际应用、Finder 的系统 reopen 事件完成 **20 次有效最小化/恢复循环**，保留 Reader 搜索词、Focus 和 AX 输入焦点；没有观察到重复主窗口。少数自动输入没有触发最小化，未计入有效循环。隐藏后系统 reopen 也恢复了原 Reader。
- Finder reopen 不是物理 Dock 点击。当前工具无法直接操作 Dock，跨 Spaces/显示器完整矩阵、关闭窗口后的完整真实事件矩阵，仍待验收。AX 输入焦点观察也不等价于每次读取 NSWindow.isKeyWindow。
- ReadingSpace 最初一次测试进程在 objc_msgSend 崩溃，没有证据确认是 Reader 布局重入。相同 Reader 实现重跑通过；随后为测试窗明确设置 isReleasedWhenClosed=false，最终再次 25 项通过。生产应用 UI 过程中未观察到崩溃，但这次测试进程崩溃根因未确认。
- 未模拟硬件触控板原始事件，只验证了 magnification 回调与公共缩放状态一致；未测滚动 FPS。

## 6. Dock 修复的历史根因

build 7 已修复的根因：原 App 是 regular，Info.plist 无 LSUIElement/LSBackgroundOnly；缺少统一主 NSWindow 所有者及 applicationShouldHandleReopen 路由，原 openWindow 回调仅服务于 citation 跳转，没有明确区分最小化、隐藏、关闭。

现有修复：注册实际 main window；最小化优先 deminiaturize / makeKeyAndOrderFront；隐藏时 unhide；关闭后才调用稳定 Window(id: "main") 的 openWindow，并抑制并发重复打开。Reader/Project 状态在同一 WorkspaceStore；退出仍等待保存队列。本轮原样保留，详见 WINDOW_LIFECYCLE.md。不能据此承诺跨设备 Dock 恢复 100% 验收。

## 7. API、heuristic 与性能

本次是 UI/Reader 本地改进，没有新增或重新进行真实网络 API 验证。build 7 已真实验证的 OpenAlex DOI/related/cites/topic/author 路径及约 8.85 秒结果保留在 ADVANCED_VERIFICATION.md，不能算成本次新实测。Zotero/OAuth/引用监测使用确定性离线回归；没有请求用户新凭据，也没有发送 private claims/evidence/PDF。

推荐的共享参考文献/直接引用取自 provider 元数据；关键词、方法提示、潜在挑战/支持、重要性排序仍是本地 heuristic，界面明确提示核实，不冒充学术判断。正式交付不含 mock/demo 研究数据；测试 fixtures 只在测试目录。

本机调试构建测得：

- 1000 claims 图谱构造 + 1000 candidates 排序：34 ms。
- 1000 works Analytics：94 ms。
- PDF 准备：320 页 198 ms；120 页 165 ms；52 MB 扫描文档 221 ms。

这些是准备/计算耗时，不是帧率保证。网络、图谱排序和数据库写入的后台边界未改变。

## 8. 修改文件

核心：Sources/AcaCore/Reading.swift、Validation.swift。

Reader：Sources/AcaTerminal/ReaderSession.swift、ReaderView.swift。

UI：Sources/AcaTerminal/ProjectsView.swift、ClaimGraphView.swift、DiscoveryView.swift、PreferencesView.swift、App.swift、新增 ApplicationVersion.swift、en/zh-Hans Localizable.strings。

版本/许可证：Resources/Info.plist、LICENSE、新增 COPYRIGHT、README.md、CONTRIBUTING.md、ARCHITECTURE.md、docs/PRIOR_ART.md、docs/BRANDING.md、scripts/package.sh。

测试/记录：Tests/AcaChecks/Checks.swift、新增 Tests/ReadingSpaceChecks/Main.swift、scripts/check-reading-space.sh、本记录。

## 9. 下一阶段建议

1. 在可控桌面与多 macOS/多显示器上完成物理 Dock、Spaces、关闭/恢复的全矩阵，独立解决后台测试进程激活限制。
2. 用 Instruments 量测 300+ 页、扫描 PDF、混合页宽/旋转页面、常驻滚动条及触控板缩放的帧时间和 anchor 偏差。
3. 用真实项目校准发现规则，增加作者/主题追踪管理与中英文分词；现阶段不扩大 provider 数量。

交付为 Apple silicon 本地 ad-hoc 签名开发包，尚未 Developer ID 公证。build 7 应用仍在运行，因此未直接覆盖它；新包独立交付。

## 10. 交付归档核验

最终应用 ZIP 在独立临时目录签名，并重新解压、恢复 Unix executable mode 后通过 `codesign --verify --deep --strict`。Documents/iCloud 路径会重新附加 FinderInfo，曾导致就地签名校验失败，因此最终交付以独立目录验证过的 ZIP 为准，没有覆盖当前运行的旧 App。源码包不包含研究数据库、测试文献、构建缓存或凭据。
