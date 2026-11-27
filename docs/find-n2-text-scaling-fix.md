# Find N2 系统字号缩放修复记录

## 原始设备证据

docs/find-n2-test-results-ak-round4.md 记录了 2026-11-09 的 OPPO Find N2 实测：

- 系统 font_scale 从 1.15 调到 2.0 后，App 文本 bounds 未变化。
- 根因定位为 main.dart 和 HomeScreen 两处均使用线性 TextScaler 覆盖平台提供的 MediaQuery.textScaler。
- 原轮次 E 项为 FAIL；该记录保留为历史失败证据，不覆盖、不改写。

## 本次代码修复

- 新增 AppPreferenceTextScaler，先调用平台 TextScaler.scale(fontSize)，再乘以 App 内字号偏好值。
- 不把平台缩放压平成单一线性系数，因此保留 Android 非线性字号曲线。
- MaterialApp.builder 是唯一应用 App 内字号偏好的位置，覆盖 Navigator 内的页面、弹窗和详情路由。
- 移除 HomeScreen 内第二层 MediaQuery 覆盖，避免首页 Tab 再次丢弃系统无障碍字号。
- App 内设置仍保留 80%—200% 的调节范围；1.0 表示不额外缩放，系统字号始终生效。

## 自动化验证

- test/app_preference_text_scaler_test.dart 覆盖线性平台缩放、非线性平台缩放和不可变值相等性。
- test/home_screen_entry_test.dart 验证 HomeScreen 不覆盖继承到的系统 TextScaler。
- 当前代码修复尚需当前 HEAD 的 Flutter tests、Flutter Quality Gate 和 Android arm64 Debug APK 结果确认。

## 真机状态

原轮次 E 项历史状态为 FAIL。修复提交后必须在真实 OPPO Find N2 上重新执行 100%、150%、200% 系统字号测试，并覆盖外屏、内屏 flat、半折叠关键页面。

在取得新提交对应 APK 的真实设备日志和截图前，修复后的 E 项保持 MISSING；Widget 测试和 CI 不得替代真机验收。
