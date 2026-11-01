#!/system/bin/sh
# CleanSlate-FuckShitAling installer (KernelSU / APatch / Magisk)
SKIPUNZIP=0

ui_print "- CleanSlate-FuckShitAling v1.0.0"
ui_print "- 开源设备标识重置 + 应用数据清理"
ui_print "- 无网络 / 无卡密 / 无遥测"
ui_print ""

# 主脚本可执行
set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm "$MODDIR/fsa.sh" 0 0 0755
set_perm "$MODDIR/config/whitelist.conf" 0 0 0644

ui_print "- 用法:"
ui_print "  su -c 'sh /data/adb/modules/cleanslate/fsa.sh help'"
ui_print "- 试运行(不落盘):"
ui_print "  FSA_DRYRUN=1 su -c 'sh .../fsa.sh all <包名>'"
