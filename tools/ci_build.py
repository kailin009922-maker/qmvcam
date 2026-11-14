#!/usr/bin/env python3
"""ci_build.py — 用 GitHub token 全自动：建仓 → 推码 → 跑 macOS Actions → 下载 deb。

用法:
    python ci_build.py <TOKEN> [repo_name]

依赖: requests（本机已装 2.34.2）、git（已装）
"""
import base64
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

import requests

SRC_ROOT = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam"
API = "https://api.github.com"


def hdr(token):
    return {
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


def run(cmd, cwd=None, env=None):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    if p.returncode != 0:
        print("$", " ".join(cmd))
        print(p.stdout[-3000:])
        print(p.stderr[-3000:])
        raise SystemExit("command failed")
    return p.stdout


def main():
    token = sys.argv[1].strip()
    repo = sys.argv[2] if len(sys.argv) > 2 else "qmvcam"
    H = hdr(token)

    me = requests.get(API + "/user", headers=H, timeout=30)
    if me.status_code != 200:
        raise SystemExit("token 无效: %s %s" % (me.status_code, me.text[:200]))
    owner = me.json()["login"]
    print("owner:", owner)

    r = requests.post(API + "/user/repos", headers=H, timeout=30,
                      json={"name": repo, "private": True, "auto_init": False})
    if r.status_code not in (201, 422):
        raise SystemExit("建仓失败: %s %s" % (r.status_code, r.text[:300]))
    print("repo:", "%s/%s" % (owner, repo), "(422 = 已存在)")

    tmp = tempfile.mkdtemp(prefix="qmrepo_")
    for name in os.listdir(SRC_ROOT):
        if name in ("build", "dist", ".verify", ".verify2", "toolchain"):
            continue
        s = os.path.join(SRC_ROOT, name)
        d = os.path.join(tmp, name)
        if os.path.isdir(s):
            shutil.copytree(s, d)
        else:
            shutil.copy2(s, d)
    print("files:", sorted(os.listdir(tmp)))

    env = dict(os.environ)
    env["GIT_TERMINAL_PROMPT"] = "0"
    run(["git", "init", "-q"], cwd=tmp, env=env)
    run(["git", "config", "user.email", "ci@local"], cwd=tmp, env=env)
    run(["git", "config", "user.name", "qmvcam"], cwd=tmp, env=env)
    run(["git", "add", "-A"], cwd=tmp, env=env)
    run(["git", "commit", "-q", "-m", "qmvcam source"], cwd=tmp, env=env)
    run(["git", "branch", "-M", "main"], cwd=tmp, env=env)
    remote = "https://x-access-token:%s@github.com/%s/%s.git" % (token, owner, repo)
    run(["git", "remote", "add", "origin", remote], cwd=tmp, env=env)
    out = run(["git", "push", "-u", "origin", "main", "--force"], cwd=tmp, env=env)
    print("pushed")

    # 等 workflow 出现
    run_id = None
    for _ in range(30):
        time.sleep(5)
        rr = requests.get(API + "/repos/%s/%s/actions/runs?per_page=5" % (owner, repo),
                          headers=H, timeout=30)
        if rr.status_code != 200:
            continue
        runs = rr.json().get("workflow_runs", [])
        if runs:
            run_id = runs[0]["id"]
            print("run:", run_id, runs[0]["status"], runs[0].get("conclusion"))
            break
    if not run_id:
        raise SystemExit("没有触发 workflow（检查 .github/workflows/build.yml 是否推送成功、token 是否有 workflow 权限）")

    # 等完成
    for _ in range(120):
        rr = requests.get(API + "/repos/%s/%s/actions/runs/%s" % (owner, repo, run_id),
                          headers=H, timeout=30).json()
        st = rr.get("status")
        if st == "completed":
            print("conclusion:", rr.get("conclusion"))
            if rr.get("conclusion") != "success":
                print("日志地址:", rr.get("html_url"))
                raise SystemExit("构建失败，去上面的地址看日志")
            break
        time.sleep(10)
    else:
        raise SystemExit("构建超时")

    arts = requests.get(API + "/repos/%s/%s/actions/runs/%s/artifacts" % (owner, repo, run_id),
                        headers=H, timeout=30).json()
    if not arts.get("artifacts"):
        raise SystemExit("没有 artifact")
    art = arts["artifacts"][0]
    url = API + "/repos/%s/%s/actions/artifacts/%s/zip" % (owner, repo, art["id"])
    z = requests.get(url, headers={"Authorization": "Bearer " + token}, timeout=120, allow_redirects=True)
    if z.status_code != 200:
        raise SystemExit("下载 artifact 失败: %s" % z.status_code)
    outdir = os.path.join(SRC_ROOT, "dist")
    os.makedirs(outdir, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(z.content)) as zf:
        zf.extractall(outdir)
    print("artifact ->", outdir)
    for f in os.listdir(outdir):
        if f.endswith(".deb"):
            print("DEB:", f, os.path.getsize(os.path.join(outdir, f)))


if __name__ == "__main__":
    main()
