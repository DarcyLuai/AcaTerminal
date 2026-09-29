<a id="english"></a>

# AcaTerminal

**A local-first research workspace for reading, organizing, connecting, and tracking academic work.**

[English](#english) · [中文](#chinese)

AcaTerminal is an open-source desktop workspace designed around the academic research lifecycle.

Instead of treating papers, notes, arguments, submissions, and research impact as separate tasks, AcaTerminal brings them into one place—from reading a paper to developing an argument, tracking a submission, and following the later impact of your work.

Built first for **macOS**, with a focus on privacy, simplicity, and a calm research experience.

## Overview

Academic work rarely ends with managing a PDF library. A paper becomes evidence. Evidence contributes to an argument. Arguments become manuscripts. Manuscripts become submissions. Published work generates citations and new research questions.

AcaTerminal is built around these connections. The first release focuses on six parts of the research workflow:

- **Library** — manage and read academic papers.
- **Projects** — organize literature around research projects.
- **Arguments** — connect claims and evidence.
- **Research Marks** — work with structured research marks from AcaTex.
- **Submissions** — track manuscripts and submission history.
- **Impact** — follow publications and citation information.

## Features

### Research Library

Keep academic papers in a local research library.

- Import PDFs, Word documents, and text files.
- Optionally add or edit bibliographic metadata.
- Search your library and organize papers into projects.
- Double-click a paper or book to read it.
- Continue reading from your previous position.

Your library and private research structure remain on your Mac.

### Academic PDF Reader

AcaTerminal includes a native PDFKit reader designed for research.

- Continuous scrolling, search, and zoom controls.
- Reading-position restoration and reading progress.
- Highlights and annotations.
- Focus Mode and an optional document outline.
- Research actions directly from selected text.

Selected passages can become part of your research workflow instead of remaining isolated highlights.

### Claims & Evidence

Use passages from papers as **Evidence** and connect them to **Claims** inside a project:

```text
Paper → Passage → Evidence → Claim → Argument
```

Choose the relationship yourself: supports, challenges, qualifies, extends, or background. Evidence retains its source, page, quote, and available selection anchor, so you can return to the original passage in the Reader.

Internal identifiers remain hidden from the everyday interface. AcaTerminal presents research objects through their content, source, and location.

### AcaTex Research Marks

Connect a saved local AcaTex project to read its structured research marks:

- Research Question
- Claim
- Hypothesis
- Finding

Imported marks preserve their underlying identity, allowing AcaTerminal to recognize updates without creating duplicate research objects. Marks appear alongside project literature and evidence. Conflicting edits are retained for review.

Available actions include:

- Edit mark text locally.
- Show the related AcaTex project in Finder.
- Find related papers.
- Export Research Marks to a local exchange file.

Connecting a project does not require an account or upload manuscript content. Exporting marks does not modify the source manuscript. See [Research Marks](docs/ACATEX_RESEARCH_MARKS.md) for supported formats and compatibility.

### Literature Discovery

Find literature related to a project's existing sources, then consider its relevance to your research questions and arguments.

Discovery helps you explore:

- What should I read next?
- What literature is related to this project?
- What work may be relevant to this claim?
- What might be missing from the current literature set?

Recommendations include reasons and feedback actions. Potential support or challenge labels are **keyword-based suggestions to verify**, not academic judgments. OpenAlex queries use public paper identifiers; private mark text is matched locally against returned public results.

### Research Projects

A project can represent a paper, a research question, or a longer research agenda. It brings together literature, claims, evidence, Research Marks, related-paper discovery, and research activity.

The project interface has three primary views:

**Literature · Argument · Activity**

Manage sources, develop arguments, and review changes without crowding them into one screen.

### Submission Tracking

Keep the research lifecycle visible after a manuscript leaves the writing environment.

Record the journal, manuscript title, submission date, manuscript ID, submission-system URL, current status, and status history.

Start with a URL and supplement the available information. **Private journal statuses are updated manually**; supported public OpenReview decisions can be refreshed. AcaTerminal does not automate journal logins or store journal passwords.

### Research Impact

Follow publications and citation information using **OpenAlex**:

- Citation counts with their data source clearly identified.
- Annual, cumulative, and per-paper charts.
- Locally retained citation snapshots and newly detected citing works.
- Research impact updates in Today.

You can also save a **Google Scholar profile link** to open in your browser. AcaTerminal does not scrape Google Scholar or import its citation counts.

Notification preferences cover new citations, submission changes, and important literature changes. Native notifications require macOS permission. Monitoring runs through in-app refreshes, not an always-running cloud service; see the [verification record](docs/BUILD10_VERIFICATION.md) and [current limits](docs/DEVELOPMENT.md#known-boundaries).

### Connected Services

| Service | Role |
| --- | --- |
| **Zotero** | Import collections, items, metadata, and notes through the official local API or a read-only Web API key. |
| **OpenAlex** | Retrieve scholarly metadata, related literature, and citation information. |
| **ORCID** | Look up researcher identity information; the developer OAuth flow requires your own registered client. |

The core workspace stays local while external scholarly services provide metadata where useful. Zotero remains a library provider; AcaTerminal does not replace it.

## Local First & Privacy

Research projects may contain unpublished manuscripts, hypotheses, arguments, annotations, and other private academic material. Your core research data is stored locally by default.

External services are used for requested metadata, citation information, and accessible full text. Private notes, claims, evidence, manuscripts, and PDFs are not uploaded to discovery providers. API credentials use macOS Keychain; the local research database is not encrypted by AcaTerminal itself.

Review the privacy policies and terms of any third-party services you use. See [storage and backup details](docs/DEVELOPMENT.md#storage-and-privacy).

## Interface

- System, Light, Dark, and Comfort / Eye Comfort appearance.
- English and 简体中文.
- Restrained transitions that respect Reduce Motion.
- Focus Mode and native macOS interactions.

The visual direction follows AcaTex: research content should remain more prominent than application controls.

## Platform & Status

The first version is built for **macOS 13 or later**. Other platforms are not included.

AcaTerminal is an **early open-source release, v0.1 build 10**. The core workflow is:

```text
Literature → Reading → Evidence → Claims / Arguments
                    → Research Project → Submission → Impact
```

The application and data model will continue evolving. Current builds are locally ad-hoc signed, not Developer ID–signed or notarized distributions. [Verified behavior and remaining boundaries](docs/BUILD10_VERIFICATION.md) are documented separately.

## Build from Source

Requires macOS 13+ and Apple Swift 5.8+ through Xcode or Command Line Tools. No third-party Swift packages are required.

```sh
git clone https://github.com/DarcyLuai/AcaTerminal.git
cd AcaTerminal
./scripts/package.sh --check
open dist/AcaTerminal.app
```

See the [development guide](docs/DEVELOPMENT.md) for build options, tests, storage, and current limitations.

## Relationship with AcaTex

**AcaTex** focuses on writing and structuring academic manuscripts.

**AcaTerminal** focuses on literature, evidence, arguments, projects, submissions, and research impact. It can read structured Research Marks from saved AcaTex projects and use them in its project workflow.

The two applications remain independently usable.

## Open Source

Contributions, bug reports, feature discussions, and research-workflow suggestions are welcome. Feedback from real academic projects is especially valuable.

- [Contributing](CONTRIBUTING.md)
- [Architecture](ARCHITECTURE.md)
- [Connector guide](docs/CONNECTOR_GUIDE.md)
- [Prior art and independent implementation](docs/PRIOR_ART.md)
- [Report an issue](https://github.com/DarcyLuai/AcaTerminal/issues)

## License

Licensed under the **GNU General Public License v3.0 only (`GPL-3.0-only`)**. See [LICENSE](LICENSE) and [COPYRIGHT](COPYRIGHT).

---

<a id="chinese"></a>

## 中文

[↑ Back to English](#english)

**一个面向研究者的本地优先研究工作台。**

AcaTerminal 是一个开源桌面研究工作台，把阅读文献、整理证据、构建论证、管理研究项目、追踪投稿和关注研究影响力放进同一个工作流。

首个版本面向 **macOS**，强调本地优先、隐私、简洁以及舒适的研究体验。

### AcaTerminal 是什么？

学术研究并不会停在「管理 PDF」。一篇论文会成为证据，证据会进入论证，论证会成为稿件，稿件会进入投稿流程。发表后的研究又会产生引用和新的研究问题。

AcaTerminal 希望连接这一整条研究链。第一版主要覆盖：

- **文献库** — 管理与阅读论文。
- **研究项目** — 围绕具体研究组织文献。
- **论证** — 管理 Claim 与 Evidence。
- **Research Marks** — 使用来自 AcaTex 的结构化研究标记。
- **投稿** — 记录稿件与投稿进度。
- **影响力** — 查看论文与引用信息。

### 文献库

建立本地学术文献库，支持导入 PDF、Word 和文本文件，按需填写或修改书目信息，搜索文献并将其加入研究项目。

双击论文或书籍即可阅读，再次打开时可恢复上次阅读位置。文献库与私人研究结构保存在你的 Mac 本地。

### 学术 PDF 阅读器

AcaTerminal 内置基于原生 PDFKit 的学术阅读器，提供：

- 连续滚动、PDF 搜索和缩放。
- 阅读位置恢复与阅读进度。
- 高亮与批注。
- 专注模式与可选的文档目录。
- 从选中文字直接进入研究操作。

阅读中的一段文字不再只是孤立的高亮，还可以继续进入 Evidence 和论证工作流。

### Claim 与 Evidence

把论文中的具体文本保存为 **Evidence（证据）**，再关联到项目中的 **Claim（论点）**：

```text
论文 → 原文 → Evidence → Claim → 论证
```

由你选择支持、质疑、限定、扩展或背景关系。证据保留来源、页码、引文以及可用的选区锚点，可以返回 Reader 中的原文位置。

内部 ID 不会显示在日常界面中。你看到的是论点、来源文献、原文与位置，而不是数据库编号。

### AcaTex Research Marks

连接已保存的本地 AcaTex 项目，即可读取：

- Research Question / 研究问题
- Claim / 论点
- Hypothesis / 假设
- Finding / 发现

标记保留稳定的底层身份。原有标记修改后，AcaTerminal 能识别同一对象的更新，避免重复创建；出现冲突时，保留版本供你审阅。

相关操作包括：

- 在本地编辑标记文本。
- 在访达中显示对应 AcaTex 项目。
- 查找相关论文。
- 将 Research Marks 导出为本地交换文件。

连接项目不需要账号，也不会上传论文正文。导出标记不会修改源稿件。支持格式与兼容性见 [Research Marks 说明](docs/ACATEX_RESEARCH_MARKS.md)。

### 相关文献发现

围绕项目已有文献寻找相关研究，再判断它们与研究问题、论点或假设的关系：

- 接下来应该读什么？
- 哪些研究与这个项目相关？
- 哪些文献可能与当前论点有关？
- 当前文献集合可能遗漏了什么？

推荐会附带原因，并支持相关性反馈。「可能支持」「可能质疑」属于**基于关键词、需要核实的建议**，不是系统替你作出的学术判断。OpenAlex 查询使用公开文献标识符，私人标记文本仅在本机匹配返回的公开结果。

### 研究项目

每个 Project 可以对应一篇论文、一个研究问题或一条长期研究议程，集中管理文献、Claims、Evidence、Research Marks、相关文献发现与研究动态。

项目界面分为三个主要视图：

**文献 · 论证 · 动态**

让管理资料、构建论证和查看变化各有清楚的位置。

### 投稿追踪

研究并不会在稿件写完时结束。AcaTerminal 可以记录期刊、稿件标题、投稿日期、Manuscript ID、投稿系统网址、当前状态和状态历史。

从网址开始，获取可用信息后再补充详情。**私有期刊投稿状态仍以手动更新为主**，受支持的 OpenReview 公开决定可刷新。不会模拟期刊登录或保存期刊账号密码。

### 研究影响力

通过 **OpenAlex** 查看论文与引用信息：

- 明确标注数据来源的引用数量。
- 年度、累计和单篇论文图表。
- 本地保留的引用快照与新检测到的引用文献。
- Today 中的研究影响力更新。

可以保存 **Google Scholar 主页链接**并在浏览器打开；AcaTerminal 不抓取 Google Scholar，也不导入其引用数量。

通知设置涵盖新引用、投稿状态变化和重要文献动态，需要 macOS 通知权限。监测依赖应用内刷新，不是持续运行的云端服务；实际验证范围见 [验证记录](docs/BUILD10_VERIFICATION.md)和[当前限制](docs/DEVELOPMENT.md#known-boundaries)。

### 外部服务

| 服务 | 用途 |
| --- | --- |
| **Zotero** | 通过官方本地 API 或只读 Web API 密钥导入分类、条目、元数据与笔记。 |
| **OpenAlex** | 获取论文元数据、相关研究与引用信息。 |
| **ORCID** | 查询研究者身份信息；开发者 OAuth 流程需使用自行注册的客户端。 |

核心研究工作区保持本地优先，需要外部学术数据时再连接相应服务。Zotero 仍是文献库来源，AcaTerminal 不取代它。

### 本地优先与隐私

研究项目可能包含尚未发表的稿件、假设、论点、证据和阅读批注，因此核心研究数据默认保存在本地。

外部服务用于所请求的元数据、引用信息与可访问全文。私人笔记、Claim、Evidence、稿件和 PDF 不会上传给文献发现服务。API 凭据存储在 macOS Keychain 中；AcaTerminal 本身不加密本地研究数据库。

使用第三方服务时，请同时查看其隐私政策与使用条款。[存储与备份说明](docs/DEVELOPMENT.md#storage-and-privacy)

### 界面

- 跟随系统、浅色、深色与护眼模式。
- English 与简体中文。
- 克制的过渡动画，尊重 Reduce Motion。
- 专注模式与 macOS 原生交互。

整体视觉方向与 AcaTex 保持一致：让研究内容成为界面的主体。

### 当前平台与阶段

第一版面向 **macOS 13 及以上版本**，不包含其他平台。

当前为**早期开源版本 v0.1 build 10**，首先建立基础研究链：

```text
文献 → 阅读 → Evidence → Claim / 论证
          → 研究项目 → 投稿 → 影响力
```

功能和数据结构仍会继续完善。当前构建使用本地 ad-hoc 签名，尚不是经过 Developer ID 签名和公证的发行包。[已验证内容与剩余边界](docs/BUILD10_VERIFICATION.md)

### 从源码构建

需要 macOS 13+，以及 Xcode 或 Command Line Tools 提供的 Apple Swift 5.8+，无需下载第三方 Swift 包。

```sh
git clone https://github.com/DarcyLuai/AcaTerminal.git
cd AcaTerminal
./scripts/package.sh --check
open dist/AcaTerminal.app
```

构建选项、测试、存储和详细限制见[开发指南](docs/DEVELOPMENT.md)。

### 与 AcaTex 的关系

**AcaTex** 更关注学术论文的写作与结构。

**AcaTerminal** 更关注文献、证据、论证、项目、投稿和研究影响力。它可以读取已保存 AcaTex 项目的结构化 Research Marks，并将其用于项目工作流。

两个应用也可以分别独立使用。

### 开源

欢迎 Bug reports、功能建议、Pull requests 和学术工作流反馈。如果你正在真实研究项目中使用 AcaTerminal，也欢迎分享使用体验。

- [贡献指南](CONTRIBUTING.md)
- [架构](ARCHITECTURE.md)
- [连接器开发指南](docs/CONNECTOR_GUIDE.md)
- [参考项目与独立实现](docs/PRIOR_ART.md)
- [反馈问题](https://github.com/DarcyLuai/AcaTerminal/issues)

### 许可证

AcaTerminal 使用 **GNU General Public License v3.0 only（`GPL-3.0-only`）**。详情见 [LICENSE](LICENSE) 与 [COPYRIGHT](COPYRIGHT)。
