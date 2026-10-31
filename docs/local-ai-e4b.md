# Gemma 4 E4B 本地文字问诊（Android）

## 模型文件

使用 LiteRT Community 提供的标准 Android .litertlm 文件：

- 仓库：litert-community/gemma-4-E4B-it-litert-lm
- 文件：gemma-4-E4B-it.litertlm
- 文件大小：3,659,530,240 bytes（约 3.66 GB）
- SHA-256：0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0
- 模型文件不打包进 APK，也不由应用自动联网下载。

下载地址：
https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm

应用只接受该标准文件的精确大小；文件缺失或大小不一致时，不会调用推理引擎。

## 安装到 OPPO Find N2

先安装本项目生成的 debug APK，并在电脑上准备好上面的模型文件。手机打开 USB 调试，确认：

```powershell
Get-FileHash .\gemma-4-E4B-it.litertlm -Algorithm SHA256
adb devices
```

将模型放入应用私有目录（Windows PowerShell）：

```powershell
adb push .\gemma-4-E4B-it.litertlm /data/local/tmp/gemma-4-E4B-it.litertlm
adb shell run-as com.nihaisha.nihaisha_app mkdir -p files/ai_models
adb shell run-as com.nihaisha.nihaisha_app cp /data/local/tmp/gemma-4-E4B-it.litertlm files/ai_models/gemma-4-E4B-it.litertlm
adb shell run-as com.nihaisha.nihaisha_app ls -l files/ai_models/
```

返回应用「问诊」页，点右上角本地 AI 入口，确认文件状态为已安装，再点「加载本地模型」。运行时优先尝试 GPU，GPU 初始化失败会自动改用 CPU；界面会显示实际使用的后端。

## 当前实现范围

- 完全离线：推理在 Android 本地执行，没有模型 API、远端服务或模型自动下载。
- 文字输入与多轮文字问诊。
- 将对话整理为固定字段的用户自述草稿；用户核对确认后才返回规则问诊页面。
- 模型加载、会话重置、释放模型内存。
- 初始化和推理都运行在单线程后台执行器，不阻塞 Flutter UI。
- GPU 不可用时回退 CPU。
- 模型提示词限制其职责为健康信息澄清与自述整理，不允许六经辨证、开方或修改剂量。
- AI 对话和结构化草稿不写入 DiagnosticEngine，不自动映射问诊选项，不改变既有规则辨证结果。

## 尚未接入

音频输入、语音播报、舌象拍照、图像质量检查和已确认症状到规则问诊选项的显式映射均不在当前文字桥接范围内。后续必须逐项实现并测试，不能将模型原始回复直接作为辨证输入。

## 实机验收记录

在 Find N2（PGU110，16 GB）上需要记录：

1. 模型完整加载时间和实际后端。
2. 首轮回复时间、连续多轮回复时间。
3. 前台峰值内存、系统是否杀进程。
4. 连续问答后的温度、降频、耗电。
5. 飞行模式下能否完成加载和多轮问答。
6. 释放模型后内存是否回落。

GitHub CI 只能验证 Flutter 测试和 Android 编译；不能替代真实设备上的模型加载、推理和热稳定性验收。