#!/system/bin/sh
# ============================================================================
# CleanSlate-FuckShitAling — 开源设备标识重置 + 应用数据清理 (KSU/APatch/Magisk)
# ----------------------------------------------------------------------------
# 行为基线来自对某 T-Protector 加壳闭源工具的行为逆向：
#   清理边界 / 重置流程 / 模板命令均按 2026-11-01 标记实验与内存取证实测还原。
# 修正原版两处缺陷：
#   [fix1] 原版先删 settings_ssaid.xml 再写 settings，SettingsProvider 被删崩
#          (Failed transaction)，后续 android_id/UUID 写入全部静默失败。
#          本版：先写 settings，最后才删 ssaid。
#   [fix2] 原版伪模块缺 module.prop，被 ksud 即时清理，从未生效。
#          本版 serialno 经合法模块 system.prop 持久生效。
# 声明：无网络 / 无卡密 / 无遥测；全部操作仅作用于本机。MIT 许可。
# ============================================================================
MODDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WL="$MODDIR/config/whitelist.conf"
BK=/data/local/tmp/cleanslate_backup
DRY=${FSA_DRYRUN:-0}

C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_0='\033[0m'
say()  { printf "${C_G}[fsa]${C_0} %s\n" "$1"; }
warn() { printf "${C_Y}[fsa]!${C_0} %s\n" "$1"; }
err()  { printf "${C_R}[fsa]x${C_0} %s\n" "$1"; }

# ---- dry-run 封装 -----------------------------------------------------------
run() {
  if [ "$DRY" = "1" ]; then echo "  DRY: $*"; else "$@"; fi
}
runsh() {  # 复合 shell 命令（含重定向/管道时用）
  if [ "$DRY" = "1" ]; then echo "  DRY(sh): $*"; else sh -c "$*"; fi
}

# ---- 随机值生成（全走 /dev/urandom，无 shell 算术陷阱） ----------------------
hex_rand() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }

new_android_id() { hex_rand 8; }   # 16 位小写 hex（实测样本格式）

new_uuid() {                        # RFC4122 v4
  h=$(hex_rand 16)
  a=$(echo "$h" | cut -c1-8)
  b=$(echo "$h" | cut -c9-12)
  c=4$(echo "$h" | cut -c14-16)     # 版本位 -> 4
  v=$(echo "$h" | cut -c17)
  case "$v" in [89ab]) x=$v ;; *) x=8 ;; esac
  d="$x$(echo "$h" | cut -c18-20)"  # 变体位 -> 8/9/a/b
  e=$(echo "$h" | cut -c21-32)
  echo "$a-$b-$c-$d-$e"
}

new_imei() {                        # 15 位数字，末位 Luhn 校验
  d=$(od -An -N28 -tu1 /dev/urandom | awk '{
    o="";
    for(i=1;i<=NF;i++){ o=o sprintf("%d", $i%10); if(length(o)>=14){print substr(o,1,14); exit} }
  }')
  c=$(echo "$d" | awk '{
    s=0; dbl=1;
    for(i=length($0);i>=1;i--){ x=substr($0,i,1)+0; if(dbl){x*=2; if(x>9)x-=9}; s+=x; dbl=1-dbl }
    print (10-s%10)%10
  }')
  echo "$d$c"
}

new_serial() {                      # 12 位字母数字（实测字符池 62）
  od -An -N96 -tu1 /dev/urandom | awk '{
    pool="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    o="";
    for(i=1;i<=NF;i++){ o=o substr(pool, ($i%62)+1, 1); if(length(o)>=12){print substr(o,1,12); exit} }
  }'
}

# ---- 备份 / 恢复 ------------------------------------------------------------
do_backup() {
  mkdir -p $BK
  settings get secure android_id > $BK/android_id.txt 2>/dev/null
  for kv in "global:gcbooster_uuid" "global:extm_uuid" "system:key_mqs_uuid" "system:local_uuid"; do
    ns=${kv%%:*}; key=${kv#*:}
    settings get "$ns" "$key" > "$BK/$key.txt" 2>/dev/null
  done
  for f in /data/system/users/*/settings_ssaid.xml; do
    [ -f "$f" ] && cp "$f" "$BK/ssaid_u$(echo "$f" | cut -d/ -f5).xml"
  done
  say "已备份原身份到 $BK"
}

restore_key() {
  ns=$1; key=$2
  v=$(cat "$BK/$key.txt" 2>/dev/null)
  [ -z "$v" ] && return 0
  if [ "$v" = "null" ]; then run settings delete "$ns" "$key"
  else run settings put "$ns" "$key" "$v"; fi
}

do_restore() {
  [ -d "$BK" ] || { err "没有备份（$BK 不存在）"; exit 1; }
  v=$(cat "$BK/android_id.txt" 2>/dev/null)
  if [ "$v" = "null" ] || [ -z "$v" ]; then run settings delete secure android_id
  else run settings put secure android_id "$v"; fi
  restore_key global gcbooster_uuid
  restore_key global extm_uuid
  restore_key system key_mqs_uuid
  restore_key system local_uuid
  for f in $BK/ssaid_u*.xml; do
    [ -f "$f" ] || continue
    u=$(echo "$f" | sed "s/.*ssaid_u\(.*\)\.xml/\1/")
    runsh "cp '$f' /data/system/users/$u/settings_ssaid.xml && chown system:system /data/system/users/$u/settings_ssaid.xml && chmod 600 /data/system/users/$u/settings_ssaid.xml"
  done
  warn "恢复完成，需重启生效"
}

# ---- 清理（边界按实测：UE 白名单保留，其余全删） -----------------------------
users_of() { pm list users 2>/dev/null | awk -F'[{:]' '/UserInfo/{print $2}'; }

whitelisted() {  # $1 = 相对路径
  [ -f "$WL" ] || return 1
  while IFS= read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    case "$1" in "$p"|"$p"/*) return 0 ;; esac
  done < "$WL"
  return 1
}

clean_tree() {  # $1 = 应用数据根目录
  [ -d "$1" ] || return 0
  for child in "$1"/* "$1"/.[!.]*; do
    [ -e "$child" ] || continue
    rel=${child#"$1"/}
    if whitelisted "$rel"; then say "保留 $child"; continue; fi
    run rm -rf "$child"
  done
}

do_clean() {
  PKG=$1
  [ -n "$PKG" ] || { err "缺少包名"; exit 1; }
  say "清理 $PKG"
  runsh "am force-stop $PKG"
  for u in $(users_of); do
    say "user $u:"
    # 原版用 --cache-only（仅缓存）；失败时回退整体 clear
    if [ "$DRY" = "1" ]; then
      echo "  DRY(sh): pm clear --user $u --cache-only $PKG"
    else
      pm clear --user "$u" --cache-only "$PKG" 2>/dev/null || pm clear --user "$u" "$PKG" 2>/dev/null
    fi
    clean_tree "/data/user/$u/$PKG"
    clean_tree "/storage/emulated/$u/Android/data/$PKG"
    # Android/obb/<pkg> 与 /sdcard/<pkg> 按实测白名单语义：保留
  done
  run logcat -c -b all
  run dmesg -c
  say "清理完毕"
}

# ---- 标识重置（顺序即 fix1：先 settings，后 ssaid） --------------------------
do_reset() {
  do_backup
  NID=$(new_android_id)
  say "android_id -> $NID"
  run settings put secure android_id "$NID"
  for kv in "global gcbooster_uuid" "global extm_uuid" "system key_mqs_uuid" "system local_uuid"; do
    ns=${kv%% *}; key=${kv#* }
    NU=$(new_uuid)
    say "$key -> $NU"
    run settings put "$ns" "$key" "$NU"
  done
  # fix1：settings 全部写完之后才动 ssaid
  warn "删除 settings_ssaid.xml（重启后按新身份重建）"
  runsh "rm -rf /data/system/users/*/settings_ssaid.xml /data/system/users/*/settings_ssaid.xml.fallback"
}

# ---- serialno 持久模块（fix2：带合法 module.prop，ksud 不会剪） --------------
do_props() {
  M=/data/adb/modules/cleanslate_props
  SN=$(new_serial)
  say "serialno -> $SN"
  if [ "$DRY" = "1" ]; then
    echo "  DRY: 写 $M/{module.prop,system.prop}"
    return 0
  fi
  mkdir -p "$M"
  cat > "$M/module.prop" <<EOF
id=cleanslate_props
name=CleanSlate-FuckShitAling props
version=v1.0.0
versionCode=1
author=fsa
description=serialno override for CleanSlate-FuckShitAling. Remove dir to revert.
EOF
  printf 'ro.serialno=%s\nro.boot.serialno=%s\n' "$SN" "$SN" > "$M/system.prop"
  warn "重启后生效；删除 $M 即还原"
  # IMEI 说明：RIL 层上报不受 prop 控制，本版不做假承诺（原版此处同样从未生效）
}

# ---- 入口 --------------------------------------------------------------------
confirm() {
  [ "${FSA_YES:-0}" = "1" ] && return 0
  printf "${C_Y}确认执行？此操作会改变设备标识/删除数据 (yes/no): ${C_0}"
  read -r a
  [ "$a" = "yes" ] || { err "已取消"; exit 1; }
}

usage() {
  cat <<EOF
CleanSlate-FuckShitAling v1.0.0 — 用法:
  sh fsa.sh clean <包名>     清理目标应用数据（白名单保留，见 config/whitelist.conf）
  sh fsa.sh reset            重置设备标识（android_id + 4×UUID + SSAID）
  sh fsa.sh props            写入 serialno 持久模块（重启生效）
  sh fsa.sh all <包名>       清理 + 重置 + props
  sh fsa.sh restore          从备份恢复上一次 reset 前的身份
环境变量:
  FSA_DRYRUN=1               试运行，只打印不执行
  FSA_YES=1                  跳过确认
示例:
  FSA_DRYRUN=1 su -c 'sh $MODDIR/fsa.sh all com.tencent.tmgp.sgame'
EOF
}

case "$1" in
  clean)   do_clean "$2" ;;
  reset)   confirm; do_reset ;;
  props)   do_props ;;
  all)     confirm; do_clean "$2"; do_reset; do_props ;;
  restore) do_restore ;;
  help|*)  usage ;;
esac
