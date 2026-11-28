# YUNQI-ORACLE-FIXTURE-20261128 — CI 外部对拍夹具接收

> 状态：AWAITING_LOCAL_FILE_AND_REPUBLICATION_REVIEW / FIXTURE MISSING
> Master 基线：56baacebd08e8e90e818471ba558ceff209b9ca7
> 责任：Local 提供原始夹具及来源/再发布证明；Integration 管理入库路径、workflow 和 inventory；Remote 不伪造测试数据。

## 1. 当前事实

CI 的 test/yunqi_engine_test.dart 通过 YUNQI_REF_PATH 环境变量接收 oracle JSON；未设置时使用历史 Windows 路径 D:\tools\yunqi_ref.json。GitHub Actions runner 不具备该本地文件，因此 15 项外部 oracle 对拍显示 MISSING/SKIPPED。

测试需要的数据范围包括：
- 62 年运气年度参考数据（1900、1949，以及 1984–2043）；
- 每年 24 个字段的逐格对拍数据；
- 62 × 6 = 372 个客气六步采样点（双口径）；
- 节气边界/年份归属等 oracle 字段，按现有测试 schema 原样提供。

上述只是现有测试读取合同，不是生成数据的许可，也不是让脚本推算出一份参考答案。

## 2. 目标路径与 CI 接入

原始文件经来源、结构、再发布权审查后，目标路径：test/fixtures/yunqi_ref.json

flutter-tests.yml 的 full Flutter regression 环境设置 YUNQI_REF_PATH 为 GitHub workspace 下的 test/fixtures/yunqi_ref.json。

不得改测试为跳过条件、不得删除 oracle 断言、不得内嵌模拟值或从被测引擎反向生成 golden fixture。若文件缺失，测试继续明确 MISSING/SKIPPED。

## 3. 公开仓库发布前置门

just2512/nihaixia-app 为公开仓库。提交 fixture 后，全部 JSON 数据、元数据和来源线索都会公开。入库前必须由文件提供者确认：
- 该文件是可再发布的自有数据，或已取得明确的公开再分发许可；
- 数据不包含个人信息、设备信息、访问令牌、API Key、私人路径或受合同/NDA/第三方限制的内容；
- 来源、版本、生成/人工校验方法和许可可写入 provenance 记录；
- 允许该内容公开存储于 GitHub 公开仓库，并纳入 Fork License inventory（该清单不授予第三方来源内容新的权利）。

未通过上述检查前，不提交 fixture bytes，也不声称 Assistant 能读取用户电脑上的 D:\tools\yunqi_ref.json。

## 4. 文件提供后的验收

1. 检查 JSON UTF-8/无 BOM、schema、62 年完整性、24 字段清单、372 采样点、必要边界字段和重复/缺失项。
2. 计算 SHA-256，记录来源、版本、许可和该哈希；不得修改数据值来适配当前算法。
3. 将 fixture 放在 test/fixtures/yunqi_ref.json，只增加路径配置，不改变对拍语义。
4. 本地运行原有 Yunqi oracle tests，所有 15 个相关 skip 必须真实执行；对不上时保留失败并修复真实算法/夹具差异。
5. GitHub Actions exact HEAD 全量 Flutter regression 必须给出实际 passed/skipped 统计；目标是这 15 项不再因 fixture missing 而 skip，其他独立 skip 也逐项保留。
6. 复核 Fork License inventory、Branch validation、Flutter regression、Android arm64/JVM、PR required gate、Fork License；合并后再核验 master Push CI。

## 5. 文件所有权与当前状态

- Local：提供源文件、来源说明、许可/再发布权确认；不得让 Remote 编写替代 fixture。
- Integration：接收后检查公共仓库风险、管理 fixture 路径、inventory 和 CI 路径配置。
- Remote：只有 fixture 正式入库且许可状态明确后，负责验证 GitHub runner 能否按 YUNQI_REF_PATH 读取；不得更改 oracle 内容。
- 当前文件 D:\tools\yunqi_ref.json 不在本次 GitHub 仓库或 Assistant 可读取的文件上下文中，状态保持 MISSING。未取得原始文件前，本任务不可标记完成。