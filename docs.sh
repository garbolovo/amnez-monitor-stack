#!/usr/bin/env bash
set -euo pipefail

# Bootstrap/update deploy for the amnez monitoring stack.
#
# Important context:
# - The host uses snap Docker.
# - snap Docker cannot bind-mount project files from /opt/monitoring-stack.
# - The deploy work tree must live under /var/snap/docker/common.
# - The old apt docker.service/docker.socket must stay disabled, otherwise it can
#   resurrect stale containers and conflict on ports 9100/9115/8081.

GIT_DIR="/var/repo/amnez-monitoring-stack.git"
WORK_TREE="/var/snap/docker/common/monitoring-stack"
BRANCH="master"

mkdir -p "$(dirname "$GIT_DIR")" "$(dirname "$WORK_TREE")"

if [ ! -d "$GIT_DIR" ]; then
  git init --bare "$GIT_DIR"
fi

git --git-dir="$GIT_DIR" symbolic-ref HEAD "refs/heads/$BRANCH"

cat >"$GIT_DIR/hooks/post-receive" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

GIT_DIR="/var/repo/amnez-monitoring-stack.git"
WORK_TREE="/var/snap/docker/common/monitoring-stack"
BRANCH="master"

umask 0022
mkdir -p "$WORK_TREE"

while read -r oldrev newrev refname; do
  if [ "$refname" = "refs/heads/$BRANCH" ]; then
    echo "[deploy] $BRANCH -> ${newrev:0:7}"

    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" checkout -f "$BRANCH"
    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" clean -fd

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

chmod +x "$GIT_DIR/hooks/post-receive"

# Keep the old apt Docker daemon/socket disabled. snap Docker remains active.
if systemctl list-unit-files docker.service >/dev/null 2>&1; then
  systemctl disable --now docker.service docker.socket 2>/dev/null || true
fi

snap services docker 2>/dev/null || true

cat <<EOF
Deploy hook installed.

Bare repo:
  $GIT_DIR

Deploy work tree:
  $WORK_TREE

Deploy command from Mac:
  git push amnez-monitor master

Expected services:
  blackbox-exporter :9115
  cadvisor          :8081
  node-exporter     :9100
  zabbix-agent2     host network
EOF
