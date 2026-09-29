# Build 7 验收记录 — 2026-09-29

本轮完成 P0 窗口生命周期修复，以及 Claim Graph、Project-aware Discovery、Literature Change Detection 的本地闭环。没有重写 Reader、Zotero、OpenAlex citation monitoring 或 RepositoryWorker。

## 1. Dock 问题根因与修复

原 App 已经是 regular，Info.plist 没有 LSUIElement/LSBackgroundOnly。问题在于缺少统一的 main NSWindow 所有者及 applicationShouldHandleReopen 路由；原 ShellView 只为 citation 跳转保存了 openWindow 回调，Dock 的重新打开没有明确处理最小化、隐藏、关闭三种状态。

修复注册实际 main NSWindow：最小化时 deminiaturize + makeKeyAndOrderFront；隐藏时 unhide；只有关闭后才调用同一 `Window(id: "main")` 的 openWindow，并防止重复调用。没有改成 WindowGroup，也没有每次点击新建窗口。退出前保存队列继续等待完成。详见 WINDOW_LIFECYCLE.md。

16 项原生窗口断言通过，包括 20 次同一 key window 的最小化/恢复、Reader/PDF 实例、搜索、Focus、sheet、两种外观、后台写入、关闭后只创建一次和退出保存。隐藏后的“窗口可见”已验证；合成后台回调的前台激活受 macOS cooperative activation 限制，两次严格 key-window 断言失败，随后将该限制独立记录，没有以反复抢焦点掩盖。

另用 Finder 对运行中的测试 App 发出真实标准 reopen 事件，最小化/隐藏的原窗口恢复，保留当前 Library/Project；不是直接函数调用。**未完成物理 Dock 图标点击的全部验收矩阵，也不承诺跨设备 100%。**

## 2. 修改文件

新增核心：
- Sources/AcaCore/ClaimGraph.swift
- Sources/AcaCore/Discovery.swift
- Sources/AcaCore/LiteratureChanges.swift
- Sources/AcaConnectors/OpenAlexDiscoveryProvider.swift

新增应用层：
- Sources/AcaTerminal/MainWindowLifecycle.swift
- Sources/AcaTerminal/ClaimGraphView.swift
- Sources/AcaTerminal/DiscoveryView.swift
- Sources/AcaTerminal/DiscoveryWorkspace.swift

更新：
- AcaCore/Models.swift、Reading.swift、Validation.swift
- AcaStorage/SQLiteRepository.swift
- AcaTerminal/App.swift、WorkspaceStore.swift、ProjectsView.swift、ShellView.swift
- AcaTerminal/ReaderSession.swift、ReaderWorkspace.swift（复用证据定位）
- AcaTerminal/ResearchNotifications.swift、ImpactPreferences.swift
- 两份 Localizable.strings、Resources/Info.plist（build 7）
- README.md、ARCHITECTURE.md、docs/CONNECTOR_GUIDE.md、docs/VERIFICATION.md

测试与文档新增：AdvancedChecks、AdvancedFlowChecks、DiscoveryLiveChecks、LifecycleChecks 及对应脚本；WINDOW_LIFECYCLE.md、ADVANCED_RESEARCH.md、本记录。现有 Checks/ImpactChecks 更新格式迁移预期。

## 3. Migration

JSON payload **3 → 4**；SQLite 表结构仍为 **1**。新增可选数组：claimRelations、discoveryCaches、discoveryFeedback、literatureSnapshots、literatureChanges。迁移前保存原始 JSON 备份，旧 papers/claims/evidence/PDF 坐标/citation history 均保留；旧版本 App 拒绝格式 4。测试没有打开或改写用户正式数据库。

## 4. 新 models/protocols

ClaimRelation / ClaimRelationship / ClaimGraph；ProjectResearchProfile；DiscoveryRequest / DiscoveryProvider / DiscoveryWork / DiscoveryBatch / DiscoveryCache / DiscoveryRecommendation / DiscoveryReason / DiscoveryFeedback；LiteratureSnapshot / LiteratureChange / LiteratureChangeSet；ResearchQuerying / ResearchQuery / ResearchQueryResult。

统一查询接口目前为类型化本地查询，没有自然语言 AI。所有 private question/claims/evidence/tags 的匹配在本机执行；Connector 只收到经过验证的公开 DOI/OpenAlex ID。

## 5. 真实 API 与 fixtures

本轮真实验证 OpenAlex：DOI `10.48550/arXiv.2205.01833` → W4229010617，related IDs / cites / primary_topic.id / authorships.author.id 四种路径成功；返回 160 个候选，77 个含参考文献 ID，129 个含摘要，耗时约 8.85 秒（网络全程异步）。

图谱/增量变化/通知去重用确定性测试数据验证，不把现场短时间内没有发生的新论文伪装为真实通知。UI QA 文献和 PDF 仅存在独立 work 测试目录。交付 App **不内置 sample/demo 数据**。本轮没有新增 Semantic Scholar，也没有用用户账户重新验证 Zotero/ORCID；它们的原有离线 connector 回归通过。

## 6. Heuristics

共享参考文献和直接引用来自 API 元数据；相关列表来自 OpenAlex。关键词重合、方法类词汇、“潜在挑战/支持”、重要性排序属于本地规则。挑战/支持要求 claim 词汇重合及公共摘要中的相应词语，主要针对英文；不是语义蕴含，更不是确定的学术判断。UI 明确标注 potential，并展示 Why this paper。每次最多 5 篇种子、200 个候选，不是穷尽检索。新发现不一定是新发表。

## 7. Tests

最终独立测试共 **128 项/组通过**（不是 128 个 XCTest 方法）：

| 套件 | 数量 | 结果 |
|---|---:|---|
| AcaChecks | 49 | 通过，含新增 15 组 Advanced |
| Reader | 17 | 通过 |
| Document import | 9 | 通过 |
| Appearance / localization / icon | 16 | 通过 |
| Native lifecycle | 16 | 通过，隐藏后的前台焦点边界见上文 |
| Advanced integration | 11 | 通过 |
| Citation/impact integration | 10 | 通过 |

覆盖重复通知 claim、已知论文新增引用、离线缓存、format 1/2/3 迁移、provider 隔离、Zotero 分页与鉴权、证据选区、原 PDF 字节不变、重启后历史保留。另完成一次真实 OpenAlex discovery API 路径检查。

原生 UI 检查：Today → 对应项目；Graph 选择/Inspector/聚焦/缩放/搜索/拖动；Evidence → Reader 第 3 页及原选区；Include dismissed；Why this paper 展开后具体依据；Light 和 Dark 图谱。发现并修正了图谱节点无障碍名称重复和中文“Read”动词歧义。通知路由与持久化已测，**未申请新的 OS 权限，未验证真实系统横幅投递**。

## 8. 性能

本机调试构建测得：1000 个 claim 的图谱构造 + 1000 候选排序约 **34 ms**；1000 works 的既有 Analytics 约 **94 ms**。Reader 320 页 PDF 准备 **182 ms**，120 页 **204 ms**，52 MB 扫描 PDF **231 ms**。这些是准备/计算耗时，**不是帧率测量**；未声称大型图谱恒定 60/120 fps。生产代码在 worker task 上准备图谱与排序，数据库写入仍由串行后台队列完成。

## 9. 已知边界

- 物理 Dock 点击、Spaces/多显示器矩阵尚未完整验收；合成后台激活受系统策略影响。
- 通知是本地 App 运行/启动刷新后聚合；不具备关闭 App 后的服务器推送或定时唤醒。持久化 claim 后崩溃可能漏一次横幅，历史不会丢。
- 图谱是确定性分层布局；大型图谱帧率及完整 VoiceOver 验收待做。空间不足时可平移/缩放。
- 作者/主题从公开种子自动追踪，尚无逐项自定义管理；复杂语义和中文关键词分词仍有限。
- 单行 JSON 的历史会逐渐增长，后续需要保留策略/归档；当前未删除历史。
- App 为本地 ad-hoc 签名开发包，尚未 Developer ID 公证。

## 10. 下一阶段最值得做的三件事

1. 多 macOS/多显示器的物理 Dock 与 Spaces 验收，以及通知授权后真实横幅/点击测试。
2. 为真实研究项目标注文献相关性，校准重要性阈值；增加作者/主题追踪管理及中英文分词。
3. 大型图谱可视区域裁剪、位置持久化和 FPS 测量；再考虑扩展 Semantic Scholar，继续区分 provider 来源。
