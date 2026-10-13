#!/usr/bin/env bash
# ============================================================
#  发布脚本：在 GitHub 与 Gitee 创建公开仓库并推送当前 main 分支
#  ⚠️ AI 生成脚本。token 只从环境变量读取，不落盘、不写进 git 配置。
#
#  用法（在你自己的终端执行）：
#     export GH_TOKEN=<GitHub 个人访问令牌，勾选 repo 权限>
#     export GITEE_TOKEN=<Gitee 私人令牌，勾选 projects 权限>
#     bash scripts_publish.sh
#
#  可选：
#     REPO_NAME=tmoelike   PRIVATE=false（默认公开）
# ============================================================
set -euo pipefail

REPO_NAME="${REPO_NAME:-tmoelike}"
PRIVATE="${PRIVATE:-false}"
DESC="TMOE-LIKE：类 TMOE 的 Termux Linux 容器管理器（proot/chroot/桌面/备份）。⚠️ 代码由 AI 生成。"

cd "$(dirname "${BASH_SOURCE[0]}")"

# ---------- 前置检查 ----------
command -v git >/dev/null || { echo "错误：缺少 git"; exit 1; }
command -v curl >/dev/null || { echo "错误：缺少 curl"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "错误：当前目录不是 git 仓库"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "警告：工作区不干净，建议先提交"; }

GH_TOKEN="${GH_TOKEN:-}"
GITEE_TOKEN="${GITEE_TOKEN:-}"
[ -n "$GH_TOKEN" ] || echo "提示：未设置 GH_TOKEN，将跳过 GitHub"
[ -n "$GITEE_TOKEN" ] || echo "提示：未设置 GITEE_TOKEN，将跳过 Gitee"
[ -n "$GH_TOKEN$GITEE_TOKEN" ] || { echo "错误：至少需要一个 token"; exit 1; }

# ---------- GitHub ----------
if [ -n "$GH_TOKEN" ]; then
    echo "== 检查/创建 GitHub 仓库 =="
    GH_USER=$(curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
        -H 'Accept: application/vnd.github+json' https://api.github.com/user \
        | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$GH_USER" ] || { echo "GitHub token 无效"; exit 1; }
    echo "   账号：$GH_USER"

    code=$(curl -s -o /tmp/gh_create.json -w '%{http_code}' -X POST \
        -H "Authorization: Bearer $GH_TOKEN" \
        -H 'Accept: application/vnd.github+json' \
        https://api.github.com/user/repos \
        -d "{\"name\":\"$REPO_NAME\",\"private\":$PRIVATE,\"description\":\"$DESC\",\"auto_init\":false}")
    case "$code" in
        201) echo "   已创建：https://github.com/$GH_USER/$REPO_NAME" ;;
        422) echo "   已存在，跳过创建" ;;
        *)   echo "   创建失败 HTTP $code"; head -c 400 /tmp/gh_create.json; echo; exit 1 ;;
    esac

    git remote remove github 2>/dev/null || true
    git remote add github "https://github.com/$GH_USER/$REPO_NAME.git"
    echo "   推送 main..."
    git -c credential.helper= \
        push "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$REPO_NAME.git" main:main
    git branch --set-upstream-to=github/main main 2>/dev/null || true
    echo "   GitHub 完成"
fi

# ---------- Gitee ----------
if [ -n "$GITEE_TOKEN" ]; then
    echo "== 检查/创建 Gitee 仓库 =="
    GITEE_USER=$(curl -fsSL "https://gitee.com/api/v5/user?access_token=$GITEE_TOKEN" \
        | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$GITEE_USER" ] || { echo "Gitee token 无效"; exit 1; }
    echo "   账号：$GITEE_USER"

    code=$(curl -s -o /tmp/gitee_create.json -w '%{http_code}' -X POST \
        "https://gitee.com/api/v5/user/repos" \
        --data-urlencode "access_token=$GITEE_TOKEN" \
        --data-urlencode "name=$REPO_NAME" \
        --data-urlencode "private=$PRIVATE" \
        --data-urlencode "auto_init=false" \
        --data-urlencode "description=$DESC")
    case "$code" in
        201) echo "   已创建：https://gitee.com/$GITEE_USER/$REPO_NAME" ;;
        400) echo "   可能已存在或参数问题（HTTP 400），继续尝试推送" ;;
        *)   echo "   创建响应 HTTP $code"; head -c 400 /tmp/gitee_create.json; echo ;;
    esac

    git remote remove gitee 2>/dev/null || true
    git remote add gitee "https://gitee.com/$GITEE_USER/$REPO_NAME.git"
    echo "   推送 main..."
    git -c credential.helper= \
        push "https://$GITEE_USER:$GITEE_TOKEN@gitee.com/$GITEE_USER/$REPO_NAME.git" main:main
    echo "   Gitee 完成"
fi

rm -f /tmp/gh_create.json /tmp/gitee_create.json
echo
echo "== remote 配置 =="
git remote -v
