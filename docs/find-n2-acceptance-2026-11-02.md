# Find N2 真机验收记录（2026-11-02）

## 设备信息

| 项 | 值 |
|---|---|
| 设备型号 | OPPO Find N2（PGU110） |
| Android 版本 | 16 |
| CPU ABI | arm64-v8a |
| 内存 | 15.5 GB |
| 外屏 | 1080×2120，450dpi，~427dp 宽 |
| 内屏 | 1920×1792，450dpi，~760dp 宽，120Hz |
| 字号缩放 | 1.15 |

## APK 信息

| 项 | 值 |
|---|---|
| 版本 | 1.11.29（含对抗性审计 5 项 bug 修复） |
| 构建方式 | WSL 本地 `flutter build apk --release`，正式签名 |
| arm64-v8a APK SHA-256 | `48fb6e541f989364ddd13fd875f20e33bff00d71ddb300cbbbfb8558388858b5` |

## 模型信息

| 项 | 值 |
|---|---|
| 模型 | Gemma 4 E4B IT（litert-community） |
| 文件 | gemma-4-E4B-it.litertlm |
| 大小 | 3,659,530,240 bytes（3.66 GB） |
| SHA-256 | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` |
| 导入方式 | App 内文件选择器导入（SHA-256 校验通过） |

## 验收结果

| # | 验收项 | 结果 | 证据 |
|---|--------|------|------|
| 1 | App 安装 | PASS | `adb install` Success，versionName=1.11.29 |
| 2 | 模型导入 + SHA-256 校验 | PASS | 哈希完全匹配 |
| 3 | 外屏布局（折叠态） | PASS | 1080×2120 截图：`docs/images/find-n2-test/01_outer_screen_folded.png` |
| 4 | 内屏布局（展开态） | PASS | 1920×1792 截图：`docs/images/find-n2-test/02_inner_screen_ai_reply.png` |
| 5 | 半折叠姿态 | PASS | App 无崩溃，截图：`docs/images/find-n2-test/04_half_fold.png` |
| 6 | E4B 文字推理 | PASS | 内屏发送消息，收到模型回复 |
| 7 | E4B 音频推理 | PASS | 录音发送，模型成功转写语音 |
| 8 | E4B 图像推理 | PASS | 拍照发送，Graphics +9MB（视觉后端激活），模型描述照片 |
| 9 | GPU 后端 | PASS | Graphics 内存 345-354MB（GPU 缓冲区） |
| 10 | 内存稳定性 | PASS | 推理前后 PSS ~1GB 无持续增长 |
| 11 | 温度 / 热降频 | PASS | CPU 62°C，skin 45.9°C，无 throttling |
| 12 | 释放 + 重载 | PASS | 释放后重载成功，App 无崩溃 |
| 13 | 历史持久化 | 已知缺口 | 释放/退出后聊天历史清空（见下） |

## 内存数据

| 阶段 | TOTAL PSS | Native Heap | Graphics |
|------|-----------|-------------|----------|
| 模型加载前 | 90 MB | 20 MB | 1.4 MB |
| 模型加载后 | 1,238 MB | 413 MB | 345 MB |
| 文字推理后 | 995 MB | 143 MB | 345 MB |
| 音频推理后 | 1,030 MB | — | 345 MB |
| 图像推理后 | 1,022 MB | — | 354 MB |
| 释放+重载后 | 1,304 MB | — | 346 MB |

## 温度数据

| 传感器 | 温度 |
|--------|------|
| CPU0 | 62.3°C |
| CPU1 | 62.7°C |
| Skin | 45.9°C |
| Battery | 31.6°C |

全测试过程无热降频。

## 已知功能缺口

### 聊天历史未持久化

- **现象**：释放模型后重载，对话框历史被清空；退出本地 AI 问诊再返回，历史记录消失。
- **根因**：聊天消息仅存在 Flutter widget 内存（`_messages` List），未持久化到数据库。
- **设计意图**：`releaseLocalModel()` 释放原生 Conversation 时主动清空 `userReportedInputs`；Dart 侧 `_refreshStatus` 检测到 `ready=false` 时清空消息列表并提示"此前会话已结束"。E4B 的对话上下文绑定在原生 Conversation 对象上，释放即销毁。
- **修复方向**：将聊天消息持久化到 sqflite（App 已使用 sqflite），退出/释放后可恢复历史记录（模型上下文无法恢复，但用户可查看历史）。

## 截图清单

| 文件 | 内容 |
|------|------|
| `01_outer_screen_folded.png` | 外屏折叠态，App 主界面 |
| `02_inner_screen_ai_reply.png` | 内屏展开态，E4B 文字推理回复 |
| `03_photo_inference_reply.png` | E4B 图像推理回复 |
| `04_half_fold.png` | 半折叠姿态 |
| `05_after_release_reload.png` | 释放重载后 |
