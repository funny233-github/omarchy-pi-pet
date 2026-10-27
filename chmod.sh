#!/usr/bin/env bash
# 给需要可执行位的脚本统一 chmod +x。
#
# 为什么要单独一个脚本：这个仓库常被放在 sandboxfs / 只读挂载里（例如 gondolin 的 /workspace），
# 那边 chmod 会直接失败，QML 只好一律用 `bash <path>` 调用。在正常的宿主目录里跑一次这个脚本，
# 脚本就能直接执行、也符合 Omarchy 插件的一般预期。
#
# 用法：
#   ./chmod.sh            # 设置可执行位
#   ./chmod.sh --check    # 只检查，不修改；有缺失则退出码 1
#
# 幂等，可以反复跑。新加 bin/ 下的脚本不用改这里（按 shebang 自动识别）。

set -uo pipefail

cd "$(dirname "$0")" || exit 1
mode=apply
[[ ${1:-} == --check ]] && mode=check

problems=0
changed=0
skipped=0

# 仓库根脚本 + bin/ 下所有带 shebang 的文件
candidates=(chmod.sh)
for file in bin/*; do
  [[ -f $file ]] || continue
  IFS= read -r first <"$file" || true
  [[ $first == '#!'* ]] && candidates+=("$file")
done

for file in "${candidates[@]}"; do
  if [[ ! -f $file ]]; then
    printf 'missing  %s\n' "$file"
    problems=$((problems + 1))
    continue
  fi
  if [[ -x $file ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  if [[ $mode == check ]]; then
    printf 'not +x   %s\n' "$file"
    problems=$((problems + 1))
    continue
  fi
  # 注意：在 sandboxfs 这类挂载上 chmod 会返回 0 却不生效，所以必须回头验证一次。
  if ! chmod +x -- "$file" 2>/dev/null || [[ ! -x $file ]]; then
    printf 'FAILED   %s（chmod 报成功但位没变，多半是 sandboxfs/只读挂载；请到宿主目录执行）\n' "$file"
    problems=$((problems + 1))
    continue
  fi
  printf 'chmod +x %s\n' "$file"
  changed=$((changed + 1))
done

printf -- '---\n%s: %d changed, %d already ok, %d problem(s)\n' \
  "$mode" "$changed" "$skipped" "$problems"
exit $((problems > 0))
