# 研纪品牌与应用身份规范

## 当前对外名称

- **唯一对外产品名称：研纪**
- **产品定位：中医诊疗全过程辅助学习工具**
- **建议对外描述：研纪：中医诊疗全过程辅助学习工具，离线优先，提供中医经典、方剂、本草、针灸、医案研习与本地 AI 辅助理解。**
- Android 桌面短名称、Flutter 标题、关于页、导出/分享文案、AI 助手自称、Web/PWA 元数据、README、推广文案和当前项目文档均使用「研纪」。

## 名称边界

「研纪」是本仓库当前产品名称。倪海厦相关历史机构、经典资料和医案中出现的来源名称属于内容事实，不等同于本应用名称，不做无差别替换。

项目更名前生成的 APK 文件名、历史发布记录和历史截图按原始事实留存；应标注为历史记录，不得在当前入口中把旧名称展示为现行产品名。

## 必须保留的内部标识

以下标识仅用于兼容和工程引用，不属于用户可见品牌，不得为更名而改动：

- Dart package name：`nihaisha_app`
- Android `applicationId`：`com.nihaisha.nihaisha_app`
- Kotlin `namespace`：`com.nihaisha.nihaisha_app`
- GitHub 仓库 slug：`just2512/nihaixia-app`（保留 Fork 来源和工程地址）

更名不能改变签名、安装身份、数据库位置、应用私有目录、本地模型路径或旧 APK 覆盖升级能力。

## 仓库公开信息

GitHub About/Description 使用以下描述：

> 研纪：中医诊疗全过程辅助学习工具，离线优先，提供中医经典、方剂、本草、针灸、医案研习与本地 AI 辅助理解。

仓库 slug 与 package id 可继续保留旧技术标识；不得把它们当作对外应用名称。

### GitHub 仓库 Settings 元数据（已完成，2026-11-21 复核）

- **Description 已设置为上面的建议描述。** 通过 GitHub 仓库元数据接口实时读取，字段值与建议描述完全一致。
- **Homepage 已清空原上游 GitHub Pages 地址。** 本仓库当前 GitHub Pages 未启用（仓库元数据 `has_pages=false`），因此保持空白，不填写未经部署验证的网址。
- 以上状态以 2026-11-21 的仓库元数据复核结果为准。后续若启用本仓库 Pages，应先确认实际部署 URL，再更新 Homepage。
- GitHub About/Description 与 Homepage 属于仓库 Settings 元数据，不随普通代码提交自动变化；代码文档记录当前状态，仓库元数据本身以 GitHub 设置为准。

## 自动化验收

`tool/audit_product_brand.py --strict` 扫描 Git 跟踪的文本文件，检查旧产品名称是否重新进入当前产品文案。中医原始知识库不参与品牌扫描；历史 APK 原始文件名可在明确的历史记录中保留。CI 必须运行该检查。
