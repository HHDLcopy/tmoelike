#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成/校验 lib/manifest.json —— 远端模块清单。

⚠️ AI 生成脚本。

为什么需要它：
  「只下载主脚本」的模式下，主脚本必须知道要下载哪些模块、以及每个模块的
  SHA256。清单把这份信息固定下来，主脚本据此逐文件校验，避免下载到被篡改
  或被截断的模块并直接 source 执行。

用法：
    python3 tools/gen_manifest.py            # 重新生成
    python3 tools/gen_manifest.py --check    # 只校验（CI 用，有不一致则非 0 退出）
"""
import argparse
import hashlib
import io
import json
import os
import sys

# 加载顺序即依赖顺序，不要随意调整：
#   deps/paths 依赖 common 的日志与常量；cli 依赖其余全部；
#   menu 在 cli 之前（cli 引用 main_menu 等）。
MODULE_ORDER = [
    "common", "tui", "archive", "deps", "paths", "registry", "download",
    "proot", "helper", "chroot", "desktop", "ssh", "vnc", "beautify",
    "plugin", "update", "backup_util", "menu", "cli",
]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
OUT = os.path.join(LIB, "manifest.json")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def build():
    mods = []
    for name in MODULE_ORDER:
        path = os.path.join(LIB, name + ".sh")
        if not os.path.isfile(path):
            sys.exit("错误：缺少模块 %s" % path)
        mods.append({
            "name": name,
            "file": name + ".sh",
            "sha256": sha256_file(path),
            "size": os.path.getsize(path),
        })
    doc = {
        "format": 1,
        "generated_by": "tools/gen_manifest.py",
        "generated_at": "",          # 校验时忽略（避免每次变动）
        "modules": mods,
    }
    return doc


def normalize(doc):
    """去除与内容无关的字段，便于 --check 比较。"""
    return {
        "format": doc.get("format"),
        "modules": [
            {k: m.get(k) for k in ("name", "file", "sha256", "size")}
            for m in doc.get("modules", [])
        ],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只校验 manifest 与 lib 是否一致")
    args = ap.parse_args()

    fresh = build()

    if args.check:
        if not os.path.isfile(OUT):
            sys.exit("错误：%s 不存在，请运行 gen_manifest.py 生成" % OUT)
        with io.open(OUT, encoding="utf-8") as f:
            current = json.load(f)
        if normalize(current) == normalize(fresh):
            print("manifest 与 lib/ 一致（%d 个模块）" % len(fresh["modules"]))
            return 0
        print("错误：manifest 与 lib/ 不一致，请重新运行 gen_manifest.py", file=sys.stderr)
        cur = {m["name"]: m for m in current.get("modules", [])}
        for m in fresh["modules"]:
            c = cur.get(m["name"])
            if not c:
                print("  + 新增：%s" % m["name"], file=sys.stderr)
            elif c.get("sha256") != m["sha256"]:
                print("  ~ 变更：%s" % m["name"], file=sys.stderr)
        for name in cur:
            if name not in [m["name"] for m in fresh["modules"]]:
                print("  - 移除：%s" % name, file=sys.stderr)
        return 1

    import datetime
    fresh["generated_at"] = datetime.datetime.now().strftime("%Y-%m-%d")
    with io.open(OUT, "w", encoding="utf-8") as f:
        json.dump(fresh, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("已生成 %s（%d 个模块）" % (OUT, len(fresh["modules"])))
    for m in fresh["modules"]:
        print("  %-12s %8d B  %s" % (m["name"], m["size"], m["sha256"][:16] + "…"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
