#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在 GitHub / Gitee 创建公开仓库并推送当前 main 分支。

⚠️ AI 生成脚本。

设计要点：
- token 只从环境变量读取，不写入任何文件、不进入 git 配置；
- 不写临时文件（Termux 的 /tmp 常不可写），全程内存处理；
- 用 git credential.helper 的 -c 覆盖 + 单次 URL 注入完成 push，避免凭据残留；
- 每步失败都明确报错并给出平台返回体，不做静默重试。

用法：
    export GH_TOKEN=<GitHub PAT，需 repo 权限>
    export GITEE_TOKEN=<Gitee 私人令牌，需 projects 权限>
    python3 scripts_publish.py

可选环境变量：
    REPO_NAME=名字（默认取当前目录名）
    PRIVATE=true  设为私有（默认公开）
    SKIP_GITHUB=1 / SKIP_GITEE=1
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

DESC = ("TMOE-LIKE：类 TMOE 的 Termux Linux 容器管理器（proot/chroot/桌面/备份）。"
        "⚠️ 代码由 AI 生成（AI-Generated）。")


def die(msg, detail=None):
    print("错误：%s" % msg, file=sys.stderr)
    if detail:
        print("  " + str(detail)[:500], file=sys.stderr)
    sys.exit(1)


def http(method, url, headers=None, data=None, timeout=30):
    """返回 (status, body_bytes)。不抛 HTTPError，交给调用方判断。"""
    req = urllib.request.Request(url, method=method, data=data)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # 网络类错误
        die("请求失败：%s %s" % (method, url), e)


def jget(body, *path):
    try:
        d = json.loads(body.decode("utf-8", "replace"))
    except Exception:
        return None
    for p in path:
        if isinstance(d, dict):
            d = d.get(p)
        else:
            return None
    return d


def sh(args, **kw):
    return subprocess.run(args, **kw)


def push(repo_url_with_token, remote_name, plain_url):
    """推送 main 并配置 remote（remote 用不带 token 的 URL）。"""
    r = sh(["git", "remote", "remove", remote_name],
           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sh(["git", "remote", "add", remote_name, plain_url], check=True)
    r = sh(["git", "-c", "credential.helper=", "push", repo_url_with_token, "main:main"])
    if r.returncode != 0:
        die("推送到 %s 失败" % remote_name)
    sh(["git", "fetch", remote_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sh(["git", "branch", "--set-upstream-to=%s/main" % remote_name, "main"],
       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    repo = os.environ.get("REPO_NAME") or os.path.basename(os.getcwd())
    private = os.environ.get("PRIVATE", "false").lower() == "true"
    gh = os.environ.get("GH_TOKEN", "").strip()
    gitee = os.environ.get("GITEE_TOKEN", "").strip()

    if not (gh or gitee):
        die("至少需要一个 token（GH_TOKEN / GITEE_TOKEN）")
    if sh(["git", "rev-parse", "--is-inside-work-tree"],
          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        die("当前目录不是 git 仓库")
    dirty = sh(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
    if dirty:
        print("警告：工作区不干净，将推送已提交内容")

    results = []

    # ---------------- GitHub ----------------
    if gh and not os.environ.get("SKIP_GITHUB"):
        print("== GitHub ==")
        st, body = http("GET", "https://api.github.com/user", {
            "Authorization": "Bearer " + gh,
            "Accept": "application/vnd.github+json",
            "User-Agent": "tmoelike-publish",
        })
        login = jget(body, "login")
        if st != 200 or not login:
            die("GitHub token 无效或权限不足（HTTP %s）" % st, body)
        print("   账号：%s" % login)

        payload = json.dumps({
            "name": repo, "private": private,
            "description": DESC, "auto_init": False,
            "has_issues": True, "has_wiki": False,
        }).encode()
        st, body = http("POST", "https://api.github.com/user/repos", {
            "Authorization": "Bearer " + gh,
            "Accept": "application/vnd.github+json",
            "User-Agent": "tmoelike-publish",
            "Content-Type": "application/json",
        }, payload)
        if st == 201:
            print("   已创建：https://github.com/%s/%s" % (login, repo))
        elif st == 422:
            print("   仓库已存在，跳过创建")
        else:
            die("创建仓库失败（HTTP %s）" % st, body)

        url = "https://github.com/%s/%s.git" % (login, repo)
        tok_url = "https://%s:%s@github.com/%s/%s.git" % (login, urllib.parse.quote(gh, safe=""), login, repo)
        push(tok_url, "github", url)
        print("   推送完成：https://github.com/%s/%s" % (login, repo))
        results.append(("GitHub", "https://github.com/%s/%s" % (login, repo)))

    # ---------------- Gitee ----------------
    if gitee and not os.environ.get("SKIP_GITEE"):
        print("== Gitee ==")
        st, body = http("GET",
                        "https://gitee.com/api/v5/user?access_token=" + urllib.parse.quote(gitee, safe=""))
        login = jget(body, "login")
        if st != 200 or not login:
            die("Gitee token 无效或权限不足（HTTP %s）" % st, body)
        print("   账号：%s" % login)

        # 注意：Gitee 的 private 必须传布尔值；传字符串 "false" 会被当作真值
        # （本项目实测：表单传 "false" 建出来是私有仓库）。
        payload = json.dumps({
            "access_token": gitee,
            "name": repo,
            "private": private,
            "auto_init": False,
            "description": DESC,
        }).encode()
        st, body = http("POST", "https://gitee.com/api/v5/user/repos", {
            "Content-Type": "application/json",
            "User-Agent": "tmoelike-publish",
        }, payload)
        if st == 201:
            created_private = jget(body, "private")
            print("   已创建：https://gitee.com/%s/%s（private=%s）"
                  % (login, repo, created_private))
            if (not private) and created_private:
                print("   警告：期望公开但结果是私有——通常是 Gitee 账号安全评级不足"
                      "（需开启 2FA 或绑定第三方账号）")
        elif st in (400, 409):
            print("   仓库可能已存在（HTTP %s），继续尝试推送" % st)
        else:
            die("创建仓库失败（HTTP %s）" % st, body)

        # 已存在时：按期望修正可见性
        if st != 201:
            fix = json.dumps({"access_token": gitee, "name": repo,
                              "private": private}).encode()
            st2, body2 = http("PATCH",
                              "https://gitee.com/api/v5/repos/%s/%s" % (login, repo),
                              {"Content-Type": "application/json"}, fix)
            if st2 == 200:
                print("   可见性已修正：private=%s" % jget(body2, "private"))
            else:
                print("   可见性未修正（HTTP %s）：%s"
                      % (st2, body2.decode("utf-8", "replace")[:200]))

        url = "https://gitee.com/%s/%s.git" % (login, repo)
        tok_url = "https://%s:%s@gitee.com/%s/%s.git" % (login, urllib.parse.quote(gitee, safe=""), login, repo)
        push(tok_url, "gitee", url)
        print("   推送完成：https://gitee.com/%s/%s" % (login, repo))
        results.append(("Gitee", "https://gitee.com/%s/%s" % (login, repo)))

    print("\n== 结果 ==")
    for name, u in results:
        print("  %-8s %s" % (name, u))
    print("\n== remote ==")
    sh(["git", "remote", "-v"])


if __name__ == "__main__":
    main()
