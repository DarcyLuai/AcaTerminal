# AcaTerminal v0.1 build 10 — Terminal-only refinement

日期：2026-09-29。当前交付以用户最新范围为准：只修改和交付 AcaTerminal，内部 ID 隐藏，保持 build 8 已有视觉与导航。AcaTex 原应用、原源码、用户论文未在本次收敛中修改；既有隔离实验保留，非当前交付或使用前提。

## 本轮变化

- 论证行、Reader Evidence 选择器、Discovery 说明移除外部 ID 和 UUID 前缀；稳定 ID、绑定、去重逻辑仍保留。没有新造 C1/H1 编号。
- 论证行显示正文、来源与必要的变更/冲突状态；普通已同步状态不重复占一行。刷新采用轻量图标，相关论文的细节放入现有“为什么推荐？”折叠区。
- 分组留白、正文层级、冲突审阅 sheet 使用现有 AcaTerminal 原生排版。文献 / 论证 / 动态导航不变。
- “显示 AcaTex 项目”在 Finder 显示已连接文档；不自动复制 ID、不向不支持的 AcaTex 派发精确导航。
- “导出研究标记”生成用户选择的本地交换文件；不修改源论文，也不声称当前安装的 AcaTex 可以导入该文件。
- 新增操作文案提供英文和简体中文。

## 文件清单（相对 build 9）

- `README.md`
- `Resources/Info.plist`
- `docs/ACATEX_RESEARCH_MARKS.md`
- `Sources/AcaTerminal/ResearchMarkView.swift`
- `Sources/AcaTerminal/ReaderView.swift`
- `Sources/AcaTerminal/DiscoveryView.swift`
- `Sources/AcaTerminal/ResearchMarkWorkspace.swift`
- `Sources/AcaTerminal/ProjectsView.swift`
- `Sources/AcaTerminal/ApplicationVersion.swift`
- `Sources/AcaTerminal/Resources/zh-Hans.lproj/Localizable.strings`
- `Sources/AcaTerminal/Resources/en.lproj/Localizable.strings`

- 新增 `docs/BUILD10_VERIFICATION.md`（本报告）。

基础 Research Mark 模型、连接器、SQLite 存储和 ReaderSession 未在本轮重写。build 9 的完整功能实现记录在 `docs/BUILD9_VERIFICATION.md`；其中 companion 内容仅是此前隔离实验记录，已不属于当前交付范围。

## Schema 与 migration

本轮无新增模型或 schema 变更。沿用 Research Mark interchange v1、SQLite user_version 1、workspace JSON payload 5。相对 build 8 的 payload 4 → 5 是可保留旧数据的前向迁移：新增可选连接/绑定/证据关系字段，迁移前保存原 payload 备份。旧应用不能读取新格式，不能把“可迁移旧数据库”理解为旧版二进制可读新数据库。

使用实际 build 8 测试数据库的只读副本重新验证：打开迁移、保存、重新打开，两项通过。未针对用户当前工作数据库执行测试写入。

## 本轮实际检查：89 / 89 通过

| 检查 | 数量 | 结果 |
| --- | ---: | --- |
| `build.sh --check` / packaged build | 63 | 通过 |
| Appearance / en–zh key coverage / icon alpha | 16 | 通过 |
| Research Mark PDFKit + SQLite 分进程 fixture | 8 | 通过 |
| build 8 数据库副本迁移、再打开 | 2 | 通过 |

63 项包含 native AcaTex schema-13 导入、稳定 ID、同 ID 更新、防重复、三方冲突及显式处理、导出保护、按标记保存证据关系、持久化、隐私查询与 1000 标记场景。未将 build 9 的历史 161 项与本轮 89 项重复累计。

### 本地完整 fixture

1. 生成一个既有 AcaTex schema-13 格式的 `.texflow`：一个已锚定的 Claim。
2. AcaTerminal adapter 导入、绑定原始外部 ID。
3. 真实 PDFKit 打开生成的 20 页 PDF，选中第 17 页原文。
4. 保存 qualifies Evidence、页码、矩形选区、文档指纹、Claim 关联与 SQLite，并生成交换文件。
5. 测试脚本修改生成的 AcaTex fixture 段落，模拟源应用保存；不是在真实 AcaTex GUI 中编辑用户论文。
6. 另一个进程重开 SQLite、读取已更新文件：一个 Claim、同一 ID，更新正文。
7. 证据关系仍是 qualifies；Reader 恢复第 17 页原 quote 与选区。
8. PDF SHA-256 前后相同。

真实使用的是 Foundation 文件读取、SQLite、PDFKit；该过程没有网络请求，没有修改 AcaTex 源码或要求 companion。

### 实际 UI 观察

隔离 QA bundle 与生成测试库中验证：中文护眼、英文深色、中文浅色的论证页；三类导航、来源、证据页码、简洁菜单正常，未显示内部 ID。实际点击证据链接，Reader 显示第 17 / 20 页并选中原文。英文菜单显示 Show AcaTex Project / Export Research Mark。

PDF 选区右键菜单可观察到 Highlight / Note / Evidence / Claim / Copy 的中文操作，但 CUA 后续菜单点击出现失效元素与状态切换，未完成本轮 Evidence 下拉选择器的整段鼠标操作，因此不记为 GUI 通过。隐藏 ID 的选择器代码已编译并审阅；底层 Evidence 保存和恢复由上述 PDFKit fixture 验证。也未把每个主题/语言组合、冲突 sheet 的每个鼠标路径或触控板流畅度写成全面验收通过。

## 兼容性边界

- 原版 AcaTex 已保存项目的标记读取/刷新可用；只读本机文件。
- 原版 AcaTex 当前没有 research-exchange 导入与精确 mark URL handler。Terminal 的导出文件与路由抽象已保留；AcaTex 回写/精确定位不属于本次已完成功能。
- Terminal 自身 Evidence → Reader 精确选区已用真实 PDFKit 和鼠标点击验证。OS 冷启动 custom URL 默认 handler 仍未做全面 GUI 验收。
- 未验证本轮真实 OpenAlex / Zotero 网络服务；原接口未改，网络检查使用既有 fixtures。
- 发现推荐仍为本机关键词 heuristic，提示 potential / 请核实，不向 OpenAlex 发送私有 Claim。
- 包为本机 Apple silicon、macOS 13+ 的 ad-hoc 签名构建，非已公证发布包。

## 交付

只有 AcaTerminal build 10 应用 ZIP、源码 ZIP、此报告和验证日志。既有 AcaTex 隔离实验未删除，但不包含在当前交付内。
