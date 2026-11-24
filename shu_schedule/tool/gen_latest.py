#!/usr/bin/env python3
"""生成「检查更新」用的 latest.json（简课表 v1.4.0 起）。

用法（在仓库根目录，Windows 上用 D:/conda/miniconda3/python.exe）：

    python shu_schedule/tool/gen_latest.py \\
        --apk "dist/简课表-v1.4.0-arm64.apk" --apk "dist/简课表-v1.4.0.apk" \\
        --changelog "新增上课提醒\\n新增 ICS 导出" \\
        --out latest.json

    # 发版之间只改了 shu_schedule/assets/holidays.json：只重算 holidays 一段
    python shu_schedule/tool/gen_latest.py --refresh-holidays --out latest.json

输出字段：
- versionCode / versionName：默认读 shu_schedule/pubspec.yaml 的 `version: x.y.z+N`，
  也可以用 --version 1.4.0+9 指定；
- changelog：--changelog 文本（`\\n` 换行）或 --changelog-file；
- downloadUrls：--download-url（可重复）；不给就按 lib/core/repo_config.dart 的 kRepo
  拼 Release 页面（Gitee 在前，若配置），kRepo 还是占位符时会给出警告；
- sha256：第一个 --apk 的 SHA-256（App 的更新对话框显示它，建议把 arm64 包放第一个）；
- apks：每个 APK 的文件名、ABI、字节数、SHA-256（App 不读，给人核对用）；
- holidays：assets/holidays.json 的 SHA-256 / updatedAt / 字节数。App 会用 sha256
  校验联网下载的假日表，所以**改了 holidays.json 一定要重新生成 latest.json 并一起提交**，
  否则新假日表会因为校验不一致被拒绝。

只用 Python 标准库。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent  # shu_schedule/
REPO_ROOT = PROJECT_DIR.parent
PUBSPEC = PROJECT_DIR / "pubspec.yaml"
REPO_CONFIG = PROJECT_DIR / "lib" / "core" / "repo_config.dart"
HOLIDAYS = PROJECT_DIR / "assets" / "holidays.json"
PLACEHOLDER_OWNER = "OWNER"
PLACEHOLDER_REPO = "REPO"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_version(explicit: str | None) -> tuple[str, int]:
    text = explicit
    if text is None:
        m = re.search(r"^version:\s*(\S+)", PUBSPEC.read_text(encoding="utf-8"), re.M)
        if not m:
            sys.exit(f"读不到 {PUBSPEC} 里的 version")
        text = m.group(1)
    m = re.fullmatch(r"(\d+\.\d+\.\d+)\+(\d+)", text.strip())
    if not m:
        sys.exit(f"版本号格式应为 x.y.z+N（例如 1.4.0+9），实际是 {text!r}")
    code = int(m.group(2))
    if code < 1:
        sys.exit("versionCode 必须 >= 1")
    return m.group(1), code


def read_repo_config() -> dict[str, str]:
    """从 repo_config.dart 的 `const RepoConfig kRepo = RepoConfig(...)` 读出配置。"""
    text = REPO_CONFIG.read_text(encoding="utf-8")
    m = re.search(r"const\s+RepoConfig\s+kRepo\s*=\s*RepoConfig\((.*?)\);", text, re.S)
    if not m:
        sys.exit(f"在 {REPO_CONFIG} 里找不到 kRepo")
    fields = dict(re.findall(r"(\w+)\s*:\s*'([^']*)'", m.group(1)))
    fields.setdefault("branch", "main")
    fields.setdefault("giteeOwner", "")
    fields.setdefault("giteeRepo", "")
    return fields


def default_download_urls(version_name: str) -> list[str]:
    repo = read_repo_config()
    owner, name = repo.get("githubOwner", ""), repo.get("githubRepo", "")
    if owner in ("", PLACEHOLDER_OWNER) or name in ("", PLACEHOLDER_REPO):
        print(
            "警告：lib/core/repo_config.dart 的 kRepo 还是占位符，downloadUrls 先用占位地址；"
            "发布前改好 kRepo 再重新生成。",
            file=sys.stderr,
        )
    urls = []
    if repo["giteeOwner"].strip() and repo["giteeRepo"].strip():
        urls.append(
            f"https://gitee.com/{repo['giteeOwner'].strip()}/{repo['giteeRepo'].strip()}"
            f"/releases/tag/v{version_name}"
        )
    urls.append(f"https://github.com/{owner}/{name}/releases/tag/v{version_name}")
    return urls


def holidays_block(path: Path) -> dict:
    raw = path.read_bytes()
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        sys.exit(f"{path} 不是合法的 UTF-8 JSON：{e}")
    if data.get("version") != 1:
        sys.exit(f"{path} 顶层 version 必须是 1（App 只认 1），实际是 {data.get('version')!r}")
    updated = data.get("updatedAt")
    if not isinstance(updated, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", updated):
        sys.exit(f"{path} 顶层缺少 updatedAt（yyyy-MM-dd）")
    if raw.startswith(b"\xef\xbb\xbf"):
        sys.exit(f"{path} 带 UTF-8 BOM，请去掉后再生成")
    if b"\r\n" in raw:
        print(
            f"警告：{path} 是 CRLF 换行；如果 git 提交时会转成 LF，"
            "线上文件的 SHA-256 会和这里算的不一样。建议先转成 LF。",
            file=sys.stderr,
        )
    if len(raw) > 256 * 1024:
        sys.exit(f"{path} 超过 256 KiB（App 的下载上限），请精简")
    return {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "updatedAt": updated,
        "bytes": len(raw),
    }


def apk_entry(path: Path) -> dict:
    if not path.is_file():
        sys.exit(f"找不到 APK：{path}")
    name = path.name
    abi = "arm64-v8a" if "arm64" in name.lower() else "universal"
    return {
        "file": name,
        "abi": abi,
        "bytes": path.stat().st_size,
        "sha256": sha256_of(path),
    }


def write_json(out: Path, data: dict) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    encoded = text.encode("utf-8")
    if len(encoded) > 64 * 1024:
        sys.exit(f"latest.json 有 {len(encoded)} 字节，超过 App 的 64 KiB 上限；请缩短 changelog")
    out.write_bytes(encoded)
    print(f"已写入 {out}（{len(encoded)} 字节）")


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description="生成简课表的 latest.json")
    ap.add_argument("--version", help="x.y.z+N；默认读 pubspec.yaml")
    ap.add_argument("--apk", action="append", default=[], type=Path,
                    help="APK 路径，可重复；第一个的 SHA-256 写进顶层 sha256")
    ap.add_argument("--changelog", default="", help="更新日志，\\n 表示换行")
    ap.add_argument("--changelog-file", type=Path, help="从文件读更新日志（UTF-8）")
    ap.add_argument("--download-url", action="append", default=[],
                    help="下载地址，可重复；默认按 kRepo 拼 Release 页面")
    ap.add_argument("--holidays", type=Path, default=HOLIDAYS, help="假日表路径")
    ap.add_argument("--out", type=Path, default=REPO_ROOT / "latest.json",
                    help="输出路径（默认仓库根目录 latest.json）")
    ap.add_argument("--refresh-holidays", action="store_true",
                    help="只重算已有 latest.json 里的 holidays 一段，其余字段不动")
    args = ap.parse_args(argv)

    holidays = holidays_block(args.holidays)

    if args.refresh_holidays:
        if not args.out.is_file():
            sys.exit(f"--refresh-holidays 需要已有的 {args.out}")
        data = json.loads(args.out.read_text(encoding="utf-8"))
        data["holidays"] = holidays
        write_json(args.out, data)
        return 0

    if not args.apk:
        sys.exit("至少给一个 --apk")
    version_name, version_code = read_version(args.version)
    if args.changelog_file:
        changelog = args.changelog_file.read_text(encoding="utf-8").strip()
    else:
        changelog = args.changelog.replace("\\n", "\n").strip()
    apks = [apk_entry(p) for p in args.apk]
    urls = args.download_url or default_download_urls(version_name)
    for u in urls:
        if not re.match(r"^https?://", u):
            sys.exit(f"下载地址必须是 http(s)：{u}")

    data = {
        "versionCode": version_code,
        "versionName": version_name,
        "changelog": changelog,
        "downloadUrls": urls,
        "sha256": apks[0]["sha256"],
        "apks": apks,
        "holidays": holidays,
    }
    write_json(args.out, data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
