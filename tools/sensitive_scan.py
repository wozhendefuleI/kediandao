# -*- coding: utf-8 -*-
"""敏感词扫描器（M5 push 前闸门，B1 本地先行模式核心工具）

用法:
    python tools/sensitive_scan.py          # 扫描全部 git 跟踪文件
    python tools/sensitive_scan.py --staged # 只扫暂存区文件

规则:
    - 词表: tools/sensitive_words.txt（每行一个正则）
    - 豁免: 本脚本自身 + 词表文件本身（否则自指命中）
    - 结果: 零命中 exit 0（可 push）; 任何命中 exit 1（禁止 push）并打印 文件:行号:原文
"""
import sys
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
WORDLIST = os.path.join(HERE, "sensitive_words.txt")
EXEMPT = {os.path.relpath(WORDLIST, REPO).replace("\\", "/"),
          os.path.relpath(os.path.abspath(__file__), REPO).replace("\\", "/")}


def load_patterns():
    pats = []
    with open(WORDLIST, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                pats.append(line)
    return pats


def list_files(staged_only=False):
    if staged_only:
        out = subprocess.run(["git", "diff", "--cached", "--name-only", "-z"],
                             cwd=REPO, capture_output=True, text=True).stdout
    else:
        out = subprocess.run(["git", "ls-files", "-z"],
                             cwd=REPO, capture_output=True, text=True).stdout
    files = [f for f in out.split("\0") if f]
    return [f for f in files if f.replace("\\", "/") not in EXEMPT]


def main():
    staged = "--staged" in sys.argv
    patterns = [re.compile(p) for p in load_patterns()]
    if not patterns:
        print("FATAL: 词表为空", file=sys.stderr)
        return 2
    hits = 0
    for rel in list_files(staged):
        path = os.path.join(REPO, rel)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for i, line in enumerate(f, 1):
                    for pat in patterns:
                        m = pat.search(line)
                        if m:
                            hits += 1
                            print(f"HIT {rel}:{i}: ...{line.strip()[:120]}")
                            break
        except OSError as e:
            print(f"WARN 无法读取 {rel}: {e}", file=sys.stderr)
    if hits:
        print(f"\n❌ 命中 {hits} 处 —— 禁止 push。逐条处置后重扫。")
        return 1
    print("✅ 敏感词扫描零命中 —— 可进入 push 审批（仍需蔡老师过目）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
