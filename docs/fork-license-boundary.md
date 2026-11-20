# Fork 代码权属与商业授权边界

## 1. 总原则

本仓库采用两层代码权属边界：

| 内容来源 | 适用许可 | 商业使用 |
|---|---|---|
| 上游原始代码及未修改的上游内容 | Apache 2.0 | 按 Apache 2.0 允许的范围使用 |
| 本 Fork 权利人拥有的新增代码和修改部分 | `LICENSE-FORK-COMMERCIAL.md` | 必须另行取得书面商业授权 |
| 混合文件中的上游原始部分 | Apache 2.0 | 按 Apache 2.0 |
| 混合文件中的 Fork 自有修改部分 | `LICENSE-FORK-COMMERCIAL.md` | 必须另行取得书面商业授权 |
| 知识库与资料内容 | 各自原许可证/来源声明 | 不受本 Fork 商业授权文件重新限制 |
| 第三方代码、模型和服务 | 各自许可证/服务条款 | 按其自身条件 |

**不再使用“之前写入仓库 / 之后新增”的时间边界。** Fork 自有 AI 代码，无论此前已经实现还是之后增加，统一进入商业授权范围。AI 与非 AI 功能之间不再采用不同的权属时间规则。

## 2. 为什么保留根目录 LICENSE

上游 `jangviktor-web/nihaixia-app` 与本 Fork 根目录原有许可证均为 Apache License 2.0。Apache 2.0 允许商业使用，并非非商业许可证。

Apache 2.0 第 4 条允许贡献者对自己所作的修改或衍生作品增加不同许可条件，但分发时仍必须遵守该许可证对上游作品的要求。因此本仓库保留根目录 `LICENSE`，另以 `LICENSE-FORK-COMMERCIAL.md` 对本 Fork 自有修改增加商业授权边界。

这不表示本 Fork 可以撤销上游作者已经授予的 Apache 2.0 权利，也不表示本 Fork 权利人取得上游代码的版权。

## 3. Fork 自有修改的范围

本许可覆盖本 Fork 权利人拥有或已取得充分授权的所有原创修改，包括：

- 新增文件、模块、服务、模型、页面、控件、Native 代码和构建/工程工具；
- 对上游文件增加的功能、逻辑、UI、状态管理、接口、测试和其他原创修改；
- 对既有业务规则、确定性计算、诊断流程、排盘服务、数据处理代码所作的原创修改；
- 本 Fork 新增的 AI 系统、AI 功能和 AI 与其他业务模块的集成；
- 为上述修改编写的实现文档、测试和工程说明。

该规则覆盖 AI 和非 AI 修改。对于未由 `just2512` 拥有版权或未获合法再许可权的内容，不能因提交到本仓库就纳入商业授权。

## 4. AI 功能边界

本 Fork 的 AI 功能属于 Fork 自有修改层，整体适用商业授权，包括：

1. 本地模型加载、导入、完整性验证、GPU/CPU backend 选择、Conversation/Engine 生命周期和 Native 推理桥接；
2. 统一助手会话、模式路由、意图理解、参数提取、缺项澄清、对话历史、恢复和任务状态；
3. AI 上下文引用、知识检索上下文、Prompt 构建、上下文解析、来源校验、结构化快照和结果解释；
4. Assistant Tool Router、Headless 工具适配器、工具参数校验、结果回流及 AI 解释流程；
5. 经典、本草、方剂、医案、内经、八字、紫微、易经、梅花、五运六气、黄历等页面中的 Fork 新增“问 AI”入口及其上下文接入；
6. AI 附件处理、AI 数据清除、TRACE、模型调用安全边界、设置入口及其相关 UI；
7. 上述功能对应的测试、集成测试、执行契约和工程实现文档。

**页面接入的边界按功能代码划分，不把整个上游页面视为 Fork 原创。** 例如原有方剂/本草/经典详情页的展示和资料内容仍保留其原许可；其中由 Fork 新增的情境提问入口、上下文适配和 AI 会话接入属于商业授权修改。

## 5. 混合文件如何识别

混合文件指文件中既有上游原始代码，又有本 Fork 自有修改。例如：

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt`
- `lib/screens/chat_screen.dart`
- `lib/screens/classic_library_screen.dart`
- `lib/screens/markdown_doc_screen.dart`
- `lib/screens/ziwei_chart_screen.dart`
- `lib/screens/formula_detail_screen.dart`
- `lib/screens/herb_detail_screen.dart`
- `lib/screens/neijing_entries_screen.dart`
- `lib/screens/meihua_screen.dart`
- `lib/screens/bazi_paipan_screen.dart`
- `lib/widgets/bazi_paipan_widgets.dart`
- `lib/screens/yunqi_screen.dart`
- `lib/screens/medical_case_detail_screen.dart`
- `lib/screens/daily_almanac_screen.dart`
- `lib/screens/yijing_result_screen.dart`
- `lib/screens/yijing_screen.dart`
- `lib/screens/yuxiaji_omen_screen.dart`

以上路径是已核查的 AI 集成/混合代码示例，不代表所有上游原始行都归 Fork 权利人所有。混合文件应保留上游声明，并以双层 SPDX 表达：

```
SPDX-License-Identifier: Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial
```

纯 Fork 新增的 AI 文件应使用：

```
SPDX-License-Identifier: LicenseRef-Nihaixia-Fork-Commercial
```

如后续发现其他混合文件或新的 AI 页面入口，按相同的功能和权属规则登记，不需要重新发明许可证类别。

## 6. 知识库和第三方组件排除

- `assets/**` 中的经典、讲义、医案、本草、方剂、穴位、易学等资料内容继续按各自原许可证、来源声明或授权条件使用。
- 知识库数据本身不纳入商业授权；不以知识库内容是否经过某种审计来判断 AI 代码是否授权。
- 读取知识库的检索器、上下文组装器、来源解析器和 AI 工具适配器，如属于本 Fork 原创修改，仍属于商业授权代码。
- Flutter/Dart/Android、第三方插件、SDK、LiteRT-LM、Gemma 或其他模型文件/权重、外部 API 和第三方资料均不由本许可重新授权。

## 7. 当前 Fork AI 核心代码定位

AI 核心代码的目录和功能清单见 [AI 功能商业授权清单](ai-commercial-license.md)。当前本地 AI 主链路与 AI 专属工具适配器是本 Fork 新增实现；上游原始页面/基础模块只在被 Fork 修改的部分适用商业授权，不改变上游原始内容的许可。

## 8. 既有版本说明

本次规则用于当前仓库修订版本及后续发布。已经依据此前版本取得许可的副本，继续适用其当时已授予的权利；本次不主张追溯撤销既有授权。当前版本中本 Fork 自有修改的商业授权边界，以本文件和文件标识/功能清单为准。


## 9. 机器可读的文件映射

AI 核心文件与混合页面的文件级许可映射记录在 `.reuse/dep5`，使用 `LicenseRef-Nihaixia-Fork-Commercial` 指向 `LICENSES/LicenseRef-Nihaixia-Fork-Commercial.md`。该映射是功能清单的机器可读补充：纯 Fork AI 文件为商业授权；混合文件为 Apache 2.0 与商业授权并存。其他 Fork 自有修改仍依第 3 节的权属规则，不因未出现在 AI 清单中而变成 Apache 原始代码。


## 10. 全仓库 Fork 修改文件清单与自动门禁

- 完整新增/修改文件清单见 [fork-license-file-inventory.md](fork-license-file-inventory.md)，机器可读清单见 [fork-license-file-inventory.json](fork-license-file-inventory.json)。清单以共同上游基线 c0f14e77a7fb721fc332576d21fef5f100392d0b 为比较点，逐文件区分 Fork 商业授权、Apache 2.0 + Fork 商业双层许可、知识库排除和第三方排除。
- .reuse/dep5 对清单中的每个变更路径使用精确路径登记，不使用 lib/**、assets/** 等会误覆盖知识库或上游文件的宽泛通配符。
- 知识库与第三方排除项采用 NOASSERTION，仅表示本 Fork 不作新的许可声明；其来源许可、版权和服务条款继续独立适用。
- tool/check_fork_license_inventory.py 比对基线至当前 HEAD 的全部路径变化，检查清单是否缺项/过期、DEP5 是否逐项覆盖、修改文件是否双层许可、新增文件是否 Fork 商业许可、知识库/第三方是否排除、商业许可文本副本是否一致，以及根目录 Apache LICENSE 是否未改动。


## 11. GitHub 公开仓库的平台许可限制

本仓库当前为 GitHub 公开仓库。GitHub 服务条款 D.5 对公开仓库的内容授予 GitHub 用户通过平台查看和 Fork 的权利；GitHub 的许可说明也明确提醒，公开仓库可以被其他用户 Fork。该平台许可独立于本仓库自定义许可，不能仅通过本许可撤销。

因此，在仓库维持 Public 时，不能宣称“未经书面许可不得公开再分发”能够阻止 GitHub 平台内的 Fork。本仓库本身是上游项目的 Fork；GitHub 规定 Fork 继承上游可见性，不能单独将 Fork 改为 Private。若权利人要求阻止新的平台内 Fork，须先按 GitHub 官方流程永久脱离 Fork network、转为独立仓库，或先向 GitHub Support 确认其他可行路径，再决定是否设为 Private。手动离网可能丢失 PR、Issue、Wiki、评论、Star、Watcher 等仓库元数据；本仓库当前有 9 个开放 Issue 和 PR #332，执行前必须备份并评估。既有 public forks 和本地 clones 不会自动删除或变为 private。该操作不可逆，未获权利人明确批准不得执行。平台许可问题不能通过文件映射或 CI 自动改变。

参考：
- [GitHub Terms of Service, Section D.5](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#d-github-additional-product-terms)
- [GitHub: About licenses](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-licenses)
