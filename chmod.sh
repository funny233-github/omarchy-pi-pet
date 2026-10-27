#!/usr/bin/env bash
# 给 bin/ 下的脚本补可执行位。
#
# 正常情况不需要它：git 索引里这些文件是 100755，clone / checkout 下来本来就是可执行的。
# 只有在这种「改了 chmod 却不生效」的挂载上（例如 gondolin 的 sandboxfs）才需要跑一次，
# 让脚本能被直接执行；QML 内部一律用 `bash <path>` 调用，不受影响。
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

# bin/ 下所有带 shebang 的文件（不修自己：能跑起来说明已经可执行，跑不起来说明是挂载问题）
candidates=()
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
