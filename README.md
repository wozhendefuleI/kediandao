# 课点到 · Android 版

体育老师的班级点名 / 课时统计工具。鸿蒙版（[kediandao](https://gitee.com/woshizhendefule1001298/kediandao)）的 Android 移植，Flutter 重写。

> 纯本机应用：**零网络权限、零遥测、零账号体系**，所有数据只存在你的手机上。

## 功能

- **点名**：按日期打卡 / 撤销，搜索过滤、一键全选/反选、删除学生（连带清除其记录）
- **课时统计**：月结（按次）/ 学期（按加权课时）双付费类型；月度统计、星期分布、学生明细
- **导入导出**：课时表 Excel/CSV 导入导出（与鸿蒙版互导兼容）、打卡记录导出、JSON 完整备份
- **数据安全**：导入前自动快照、原子写盘、学生 ID 单调递增防撞号、导入月结学生课时永不被覆写

## 构建

```bash
flutter build apk --release   # 需要 Flutter 3.47+ / Android SDK 36
```

国内网络建议先设置镜像：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

最低 Android 8.0（API 26）；Gradle 依赖走阿里云镜像（见 `android/settings.gradle.kts`，海外开发者可注释）。

## 口径说明

业务规则（课时算术、月度口径、导入红线）以 `docs/移植口径对照表.md` 为唯一真源，逐条对应鸿蒙版行为锚点。要点：

- 月度统计从打卡记录实时计算，不消费累计器字段（与鸿蒙 v1.0.20 修复形态一致）
- 导入课时表按姓名匹配：月结学生的已用/剩余课时**永不覆写**（由打卡累计驱动）
- 删除学生连带清除其全部打卡记录

## License

MIT
