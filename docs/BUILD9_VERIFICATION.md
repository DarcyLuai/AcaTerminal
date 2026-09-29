# AcaTerminal v0.1 build 9 — Research Marks 验收记录

这轮保留 Reader、ResearchObject、Project、SQLite、Zotero、OpenAlex、引用监测的现有结构，加入本地 AcaTex Research Marks 连接。版本仍为 **0.1.0，build 9**。

## 已实现的核心链路

- 项目菜单连接本地 AcaTex `.texflow` / `.acatex` / JSON；从真实 AcaTex 源码的 `researchObjects` + `anchorNodeId` 格式独立实现读取。
- 论证页面分组显示 RQ / Claim / Hypothesis / Finding。外部 ID 原样保留；UUID 在不冲突时直接复用。标题和显示序号不参与身份匹配。
- Reader 选区保存为 Evidence，选择已有研究标记或新建 Claim。支持 supports / challenges / qualifies / extends / background，默认 background，由用户判断。
- 每条 Evidence–Mark 连接独立存储 relationship。同一证据可支持一条 Claim、限定另一条 Hypothesis。
- 三方比较 baseline / local / remote：远端单独修改更新原 Claim；双方不同修改进入 Conflict；显式选择版本，保留冲突历史。
- Send to AcaTex 输出本地交换文件。配套 AcaTex 实现逐项审阅、可撤销应用和保存；不会静默改论文正文。
- Discovery 可按具体研究标记筛选；潜在支持/质疑/扩展来自本地英文关键词启发式。请求仍只含公开 DOI/OpenAlex ID。
- Research Changes 增加潜在假设证据、RQ 相关新文献、论点扩展类型。
- 双向 URL 路由和严格解析已实现。AcaTex 只解析当前/最近打开的本地项目；未安装兼容处理器时 Terminal 显示文件并复制标记 ID。

## Schema 与 migration

SQLite 表结构 `user_version` **仍为 1**；JSON payload **4 → 5**。
新增可选数组 `acaTexConnections`、`markBindings`、`evidenceRelations`；Claim 增加可选 `markType` / `markStatus`；DiscoveryRecommendation 增加可选 `markMatches`。旧 Claim 仍默认为 active claim。原有 evidence.relationship 保留，旧 contradicts 继续可解码。迁移前原始 payload 原样写入独立 JSON 备份；不删除旧对象或修改 PDF。旧版 Terminal 拒绝新 payload，避免降级丢字段。

实际复制了本工作区 build 8 UI QA 的 SQLite 数据库进行迁移、保存和再次打开；同时测试了合成旧 payload 的逐字节备份和关系回填。**未对用户数据库进行破坏性迁移或清空。**

新增 Core 类型：ResearchMarkType、ResearchMark、ResearchMarkValue、ResearchMarkLink、ResearchMarkAnchor、ResearchMarkEvidence、ResearchMarkExchange、ResearchMarkCodec、AcaTexConnection、MarkBinding、ResearchSyncStatus、MarkConflict、EvidenceRelation、ResearchRoute、PotentialMarkMatch。新增协议 ResearchMarkProjectReader；独立实现 AcaTexProjectReader。

AcaTex 配套源代码增加可选 terminalEvidence / terminalEvidenceHistory，文档 schema **13 → 14**。这是为了让旧 AcaTex 明确拒绝可能丢失新增字段的文件。配套程序可打开旧文档；正式文稿建议在预览中使用副本。原 AcaTex 安装及源目录未覆盖。

## 实际测试结果

| 范围 | 结果 |
|---|---:|
| Core / SQLite / Connectors / sync / privacy / analytics | 63 通过 |
| PDFKit Reader | 17 通过 |
| Reading Space / focus / resize / themes | 25 通过 |
| PDF / Word / text import / context menu | 9 通过 |
| 本地化与外观资源 | 16 通过 |
| Advanced Research 集成 | 11 通过 |
| Citation Impact 集成 | 10 通过 |
| 跨应用文件 + SQLite + PDFKit E2E | 8 通过 |
| 实际 build 8 QA 数据库迁移/重启 | 2 通过 |
| **AcaTerminal 检查合计** | **161 通过** |
| AcaTex Vitest | 390 通过，10 跳过 |
| AcaTex 严格 URL 路由 Node tests | 2 通过 |
| AcaTex TypeScript / Vite build | 通过 |
| 两个 macOS 包 strict codesign verify | 通过（本地 ad-hoc） |

AcaTex 的跳过项为其已有测试环境限制；本轮跨应用 disk fixture 在设置 ACA_MARK_E2E_DIR 后确实执行，未计作空跑通过。日志附在本目录。

完整 E2E：生成真实 AcaTex 原生项目 → 导入 CLAIM-003 → PDFKit 打开独立生成的 PDF → 捕获物理第 17 页原文与矩形 → qualifies 关系 → SQLite 保存 → Swift 导出 JSON → AcaTex ProseMirror schema 加载、显式应用、作者修改原 Claim、保存原生文档 → 新进程重新加载 SQLite → 更新同一 Claim → PDFKit 恢复第 17 页相同 quote/selection → 原 PDF SHA-256 不变。

性能（本机单次测试，不代表各类 PDF/硬件的帧率保证）：1000 条标记首次导入 + 重复同步 **13 ms**；1000 claims 图谱 + 1000 works 排序 **28 ms**；1000 works analytics **91 ms**。320 页 PDF 准备 **169 ms**，120 页 **161 ms**，52 MB 扫描 PDF **212 ms**。

## UI 与真实 API 的验证边界

已实际看到中文论证页、稳定 ID、证据关系与页码，以及英文深色论证页；菜单过宽已修正。现有自动 Reading Space 检查覆盖 Light/Dark/Eye Comfort 下 Reader 的稳定性。AcaTex 原生 File → 导入研究标记能够打开审阅窗口，显示两份 Claim 文本、原文 quote 与未勾选默认状态。

**没有把完整 GUI 验收写成通过：** AcaTex 预览的鼠标勾选/应用/保存连续操作在本次 UI 自动化中未得到稳定可重复的结果；系统默认 URL handler 的双向冷启动跳转、未保存文档提示矩阵也尚未完整实测。相关事务、稳定 ID、路由解析及源定位已有自动化覆盖，不能替代这两项 macOS 实机验收。配套包因此标为 preview，不能视为官方 AcaTex release。

这轮未新增或宣称完成真实 OpenAlex/Zotero 网络请求验证；Connector 回归用可控 HTTP fixture。新同步、数据库、原生格式、ProseMirror 和 PDFKit 使用真实本地实现，没有 demo 内容注入正式数据库。

其他边界：仅连接已保存的单个 AcaTex 文稿，一个 Terminal 项目对应一个文稿；不监听未保存的编辑器缓冲区。源文件移动需重新定位；源 PDF 改变会使用 quote/page 降级。纯扫描 PDF 无 OCR 时不能产生文字选区。潜在关联为英文关键词启发式，中文研究内容的语义召回没有实现。note 类型已纳入 interchange schema，但本轮 AcaTex 正文同步仅处理四类论证标记和关联 Evidence。部分错误诊断仍为英文。

## 使用入口

AcaTerminal：项目 → 右上角 ⋯ → Connect AcaTex Project；论证 → 某条标记 ⋯ → Send to AcaTex / Open in AcaTex。
AcaTex companion：先打开该文稿 → macOS 文件菜单 → 导入研究标记 → 审阅选择 → 应用 → 保存 → 返回 Terminal 刷新。

配套预览使用独立 bundle ID / preferences，与原安装并存；两个包均未公证，不作为 App Store/Developer ID 发布版本。

## 修改文件

AcaTerminal：

- `docs/BUILD9_VERIFICATION.md`
- `docs/PRIOR_ART.md`
- `docs/CONNECTOR_GUIDE.md`
- `ARCHITECTURE.md`
- `README.md`
- `Resources/Info.plist`
- `docs/ACATEX_RESEARCH_MARKS.md`
- `scripts/check-research-marks.sh`
- `Tests/ResearchMarkFlowChecks/Main.swift`
- `Tests/AcaChecks/AdvancedChecks.swift`
- `Tests/AcaChecks/ImpactChecks.swift`
- `Tests/AcaChecks/Checks.swift`
- `Tests/AcaChecks/ResearchMarkChecks.swift`
- `docs/schemas/research-marks-v1.schema.json`
- `Sources/AcaCore/Reading.swift`
- `Sources/AcaCore/ClaimGraph.swift`
- `Sources/AcaCore/LiteratureChanges.swift`
- `Sources/AcaCore/Validation.swift`
- `Sources/AcaCore/Discovery.swift`
- `Sources/AcaCore/Models.swift`
- `Sources/AcaCore/ResearchMarks.swift`
- `Sources/AcaTerminal/ClaimGraphView.swift`
- `Sources/AcaTerminal/ResearchMarkView.swift`
- `Sources/AcaTerminal/ReaderView.swift`
- `Sources/AcaTerminal/DiscoveryView.swift`
- `Sources/AcaTerminal/WorkspaceStore.swift`
- `Sources/AcaTerminal/ResearchMarkWorkspace.swift`
- `Sources/AcaTerminal/ProjectsView.swift`
- `Sources/AcaTerminal/ApplicationVersion.swift`
- `Sources/AcaTerminal/App.swift`
- `Sources/AcaConnectors/AcaTexProjectReader.swift`
- `Sources/AcaStorage/SQLiteRepository.swift`
- `Sources/AcaTerminal/Resources/zh-Hans.lproj/Localizable.strings`
- `Sources/AcaTerminal/Resources/en.lproj/Localizable.strings`

AcaTex 配套（独立目录）：package.json；src/main.js；src/preload.js；src/applicationMenu.js；src/researchRoutes.cjs；src/researchRoutes.test.cjs；src/renderer/App.tsx；src/renderer/types/electron.d.ts；src/renderer/devBridge.ts；src/renderer/editor/extensions/DocumentStructure.ts；src/renderer/document/semanticIdentity.ts；src/renderer/document/acaResearchExchange.ts；src/renderer/document/acaResearchExchange.test.ts；src/renderer/components/ResearchExchangeReview.tsx；src/renderer/components/ResearchRelationships.tsx。另附 README 与可重现预览打包脚本。

## 正式发布前下一步

1. 用兼容 AcaTex 正式构建完成双向系统 URL 冷启动、不同文稿与未保存修改的人工验收。
2. 完成配套审阅界面的鼠标/键盘与三主题验收；目前不能据自动化事务测试宣称这项已完成。
3. 测试多页/旋转页/重排版 PDF 锚点与大型真实 AcaTex 文稿；再做发布签名和公证。
