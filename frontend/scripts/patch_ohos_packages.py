#!/usr/bin/env python3
"""
patch_ohos_packages.py - 为 pub-cache 中的插件补丁 TargetPlatform.ohos 穷尽 switch。

背景：鸿蒙版 Flutter 新增了 TargetPlatform.ohos，但大量第三方插件的
`switch (defaultTargetPlatform)` 是穷尽匹配（列出 android/iOS/macOS/linux/windows/fuchsia），
缺 ohos case 会编译失败。

修复方式：把 `switch (defaultTargetPlatform)` 替换为
`switch (defaultTargetPlatform.name == 'ohos' ? TargetPlatform.android : defaultTargetPlatform)`，
让 ohos 走 android 分支（鸿蒙的 UI 行为与 android 接近）。

幂等：已含 `name == 'ohos'` 的文件跳过。可多次运行。

用法：
    python3 frontend/scripts/patch_ohos_packages.py [--pub-cache <path>] [--dry-run]

退出码 0 表示成功；非 0 表示出错。
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

# 需要补丁的 switch 模式（捕获 switch 关键字后的表达式变量名）
SWITCH_PATTERNS = [
    # switch (defaultTargetPlatform)
    re.compile(r'switch\s*\(\s*(defaultTargetPlatform)\s*\)'),
    # switch (Theme.of(context).platform) 等带属性访问的——只处理 defaultTargetPlatform 直接使用
]

# ohos 补丁标记（已补丁的文件含此字符串）
OHOS_MARKER = "name == 'ohos'"


def find_pub_cache() -> Path:
    """定位 pub-cache 目录。"""
    env = os.environ.get("PUB_CACHE")
    if env:
        return Path(env)
    home = Path.home()
    candidates = [
        home / ".pub-cache",
        home / "AppData" / "Local" / "Pub" / "Cache",  # Windows
    ]
    for c in candidates:
        if c.exists():
            return c
    return home / ".pub-cache"


def get_plugin_paths(project_dir: Path) -> list:
    """从 .flutter-plugins-dependencies 读取插件路径列表。"""
    deps_file = project_dir / ".dart_tool" / ".flutter-plugins-dependencies"
    if not deps_file.exists():
        return []
    try:
        data = json.loads(deps_file.read_text())
    except (json.JSONDecodeError, OSError):
        return []
    paths = []
    for platform_plugins in data.get("plugins", {}).values():
        for p in platform_plugins:
            path = p.get("path")
            if path and Path(path).exists():
                paths.append(Path(path))
    return paths


def patch_file(file_path: Path, dry_run: bool) -> int:
    """补丁单个文件，返回补丁数（0 表示无需补丁）。"""
    try:
        content = file_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return 0

    if OHOS_MARKER in content:
        return 0  # 已补丁，幂等跳过

    patch_count = 0
    new_content = content

    for pattern in SWITCH_PATTERNS:
        matches = pattern.findall(content)
        if not matches:
            continue
        # 对每个匹配，替换为带 ohos 映射的写法
        def replacer(m):
            var = m.group(1)
            return (
                f"switch ({var}.name == 'ohos' ? TargetPlatform.android : {var})"
            )
        new_content = pattern.sub(replacer, new_content)
        # sub 是全局替换，统计替换次数
        patch_count += len(matches)

    if patch_count == 0:
        return 0

    if not dry_run:
        file_path.write_text(new_content, encoding="utf-8")

    return patch_count


def main():
    parser = argparse.ArgumentParser(
        description="Patch pub-cache packages for TargetPlatform.ohos"
    )
    parser.add_argument(
        "--pub-cache",
        type=Path,
        default=None,
        help="pub-cache 根目录（默认自动检测）",
    )
    parser.add_argument(
        "--project-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent.parent / "appflowy_flutter",
        help="Flutter 工程目录（用于读取插件列表）",
    )
    parser.add_argument("--dry-run", action="store_true", help="只统计不修改")
    args = parser.parse_args()

    pub_cache = args.pub_cache or find_pub_cache()
    hosted = pub_cache / "hosted"
    if not hosted.exists():
        print(f"[ERROR] pub-cache hosted 目录不存在: {hosted}")
        return 1

    # 收集要扫描的目录：pub-cache 里所有插件的 lib/ + 项目 path 插件的 lib/
    scan_dirs = []
    for provider in hosted.iterdir():
        for pkg in provider.iterdir():
            lib = pkg / "lib"
            if lib.is_dir():
                scan_dirs.append(lib)

    for plugin_path in get_plugin_paths(args.project_dir):
        lib = plugin_path / "lib"
        if lib.is_dir():
            scan_dirs.append(lib)

    print(f"[INFO] 扫描 {len(scan_dirs)} 个插件 lib/ 目录...")

    total_patched = 0
    patched_files = []

    for lib_dir in scan_dirs:
        for dart_file in lib_dir.rglob("*.dart"):
            count = patch_file(dart_file, args.dry_run)
            if count > 0:
                total_patched += count
                patched_files.append((str(dart_file), count))

    mode = "[DRY-RUN] " if args.dry_run else ""
    print(f"{mode}[DONE] 共补丁 {total_patched} 处 switch，涉及 {len(patched_files)} 个文件:")
    for f, c in patched_files:
        print(f"  {c:3d} 处  {f}")

    if not args.dry_run and total_patched > 0:
        print("\n[INFO] 补丁已完成。如需还原，重新 flutter pub get 即可恢复原始文件。")

    return 0


if __name__ == "__main__":
    sys.exit(main())
