# CleanSlate-FuckShitAling

开源版设备标识重置 + 应用数据清理工具（KernelSU / APatch / Magisk 模块）。

行为基线来自对闭源 **aling** 脚本（T-Protector 1.0.25 壳，TG @Whitelist520 分发）
的完整行为逆向：清理边界、重置流程、命令模板均按 2026-11-01 的标记实验与
内存取证实测还原。区别是：本版无壳、无卡密、无联网、无遥测，代码全部可审计。

## 功能

| 命令 | 作用 |
|---|---|
| `clean <包名>` | 清理目标应用数据：force-stop → pm clear（cache-only）→ 内外部数据目录遍历删除（白名单保留）→ 清 logcat/dmesg |
| `reset` | 重置设备标识：android_id（16 位 hex）+ 4 处 UUID（RFC4122 v4）+ SSAID 抹除 |
| `props` | 写入 serialno 持久覆盖模块（合法 module.prop + system.prop，重启生效） |
| `all <包名>` | 以上全部 |
| `restore` | 从备份恢复 reset 前的身份 |

清理边界按实测还原：

- 删：内外部 `cache`、`code_cache`、`databases`、`shared_prefs`、`app_webview` 及一切非白名单目录
- 留：`files/UE4Game/**`（游戏存档，见 `config/whitelist.conf`，可自行增删）、`Android/obb/<pkg>`、`/sdcard/<pkg>`
- 遍历所有用户（`pm list users`，含分身空间），原版硬编码 0/999

## 相对原版的修正与差异

1. **[bug fix] 执行顺序**：原版先 `rm settings_ssaid.xml` 再写 settings，
   活系统上 SettingsProvider 被删崩（`Failed transaction`），后续 android_id/UUID
   写入全部**静默失败**——实测在 Android 16 上原版的标识重置从不生效。
   本版：先写全部 settings，最后删 ssaid。
2. **[bug fix] serialno 模块**：原版建的 `ALING_IMEI/ALING_Serialno` 目录缺
   `module.prop`，被 ksud 即时清理，从未产出过任何文件。本版模块带合法
   `module.prop`，`system.prop` 覆盖 `ro.serialno`/`ro.boot.serialno`，重启后真实生效。
3. **IMEI**：RIL 层上报不受 prop 控制，本版不做假承诺（原版声称随机 IMEI，
   实测其产出物在 KSU 上同样从未存在）。如需 RIL 级伪装属于另一个工程。
4. **备份/恢复**：reset 前自动备份原身份到 `/data/local/tmp/cleanslate_backup/`，
   `restore` 一键还原（原版无任何回滚手段）。
5. **试运行**：`FSA_DRYRUN=1` 全程只打印不落盘。
6. **移除**：卡密验证、公告拉取、TG 引流、内核参数扰动
   （`nf_conntrack_max=0` 等对清理无用且有副作用）、`setenforce 1`（无必要）。

## 用法

```sh
# 安装：刷入模块 zip 后
su -c 'sh /data/adb/modules/cleanslate/fsa.sh help'

# 试运行（强烈建议先看一遍要做什么）
FSA_DRYRUN=1 su -c 'sh /data/adb/modules/cleanslate/fsa.sh all com.tencent.tmgp.sgame'

# 实际执行
su -c 'sh /data/adb/modules/cleanslate/fsa.sh all com.tencent.tmgp.sgame'

# 反悔
su -c 'sh /data/adb/modules/cleanslate/fsa.sh restore'
```

## 自行打包

```sh
zip -r9 CleanSlate-FuckShitAling-v1.0.0.zip module.prop customize.sh fsa.sh config/ README.md LICENSE
```

## 免责声明

仅用于本人拥有 root 权限的设备上的数据管理与隐私重置。使用本工具产生的
一切后果（包括但不限于应用重新登录、账号风控）由使用者自行承担。

## License

MIT
