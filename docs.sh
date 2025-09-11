# 1) убедись что bare существует (если нет — создай)
# git init --bare /var/repo/amnez-monitoring-stack.git

# 2) выстави основную ветку (на всякий случай)
git --git-dir=/var/repo/amnez-monitoring-stack.git symbolic-ref HEAD refs/heads/master

# 3) создать post-receive hook
cat >/var/repo/amnez-monitoring-stack.git/hooks/post-receive <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

GIT_DIR="/var/repo/amnez-monitoring-stack.git"
WORK_TREE="/opt/monitoring-stack"
BRANCH="master"

umask 0022
mkdir -p "$WORK_TREE"

while read -r oldrev newrev refname; do
  if [ "$refname" = "refs/heads/$BRANCH" ]; then
    echo "[deploy] $BRANCH -> ${newrev:0:7}"
    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" checkout -f "$BRANCH"
    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" submodule update --init --recursive || true
    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" clean -fd

    # Автозапуск Docker Compose если есть файл
    if [ -f "$WORK_TREE/docker-compose.yml" ] || [ -f "$WORK_TREE/compose.yml" ] || [ -f "$WORK_TREE/compose.yaml" ]; then
      cd "$WORK_TREE"
      /usr/bin/docker compose pull || true
      /usr/bin/docker compose up -d --remove-orphans
    fi
    echo "[deploy] done"
  else
    echo "[deploy] push to $refname ignored (only $BRANCH auto-deploys)"
  fi
done
HOOK

chmod +x /var/repo/amnez-monitoring-stack.git/hooks/post-receive
