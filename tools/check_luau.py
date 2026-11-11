"""粗略的 Luau 結構檢查（沒有裝 Luau 工具時用）。

檢查每個 .luau 檔：
  - function / do / if 和 end 數量對得上（repeat 對 until）
  - ( ) [ ] { } 括號成對
  - 字串、長註解有關上
  - 每個 require(script.Parent...) 指到的模組真的存在

這不是完整的語法檢查，Studio 的 Script Analysis 才是最終標準。
用法：python tools/check_luau.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

OPENERS = {"function", "do", "if"}
PAIRS = {")": "(", "]": "[", "}": "{"}


def long_bracket(text, i):
    """如果 text[i] 開始是 [[ 或 [==[，回傳 (等號數量, 開頭長度)，否則 None。"""
    m = re.match(r"\[(=*)\[", text[i:])
    if m:
        return len(m.group(1)), m.end()
    return None


def tokenize(text):
    tokens = []  # (kind, value, line)
    i, line, n = 0, 1, len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif text.startswith("--", i):
            lb = long_bracket(text, i + 2)
            if lb:
                eq, length = lb
                close = "]" + "=" * eq + "]"
                end = text.find(close, i + 2 + length)
                if end < 0:
                    raise SyntaxError(f"第 {line} 行：長註解沒有關上")
                line += text.count("\n", i, end)
                i = end + len(close)
            else:
                end = text.find("\n", i)
                i = n if end < 0 else end
        elif c in "\"'`":
            start_line = line
            j = i + 1
            while True:
                if j >= n or text[j] == "\n":
                    raise SyntaxError(f"第 {start_line} 行：字串沒有關上")
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == c:
                    break
                j += 1
            tokens.append(("string", "", start_line))
            i = j + 1
        elif c == "[" and long_bracket(text, i):
            eq, length = long_bracket(text, i)
            close = "]" + "=" * eq + "]"
            end = text.find(close, i + length)
            if end < 0:
                raise SyntaxError(f"第 {line} 行：長字串沒有關上")
            line += text.count("\n", i, end)
            tokens.append(("string", "", line))
            i = end + len(close)
        elif c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", text[i:])
            tokens.append(("name", m.group(0), line))
            i += m.end()
        elif c.isdigit():
            m = re.match(r"0[xX][0-9a-fA-F_]+|[0-9_]*\.?[0-9_]+(?:[eE][+-]?[0-9]+)?", text[i:])
            i += max(1, m.end() if m else 1)
        else:
            tokens.append(("sym", c, line))
            i += 1
    return tokens


def check_file(path: Path):
    errors = []
    text = path.read_text(encoding="utf-8")
    try:
        tokens = tokenize(text)
    except SyntaxError as e:
        return [str(e)]

    blocks = []  # (keyword, line)
    brackets = []
    prev = None
    for kind, value, line in tokens:
        if kind == "name":
            # 前面是 . 或 : 的話是欄位名稱，不是關鍵字
            is_field = prev is not None and prev[0] == "sym" and prev[1] in ".:"
            if not is_field:
                if value in OPENERS:
                    blocks.append((value, line))
                elif value == "repeat":
                    blocks.append(("repeat", line))
                elif value == "end":
                    if not blocks or blocks[-1][0] == "repeat":
                        errors.append(f"第 {line} 行：多了一個 end")
                    else:
                        blocks.pop()
                elif value == "until":
                    if not blocks or blocks[-1][0] != "repeat":
                        errors.append(f"第 {line} 行：until 沒有對應的 repeat")
                    else:
                        blocks.pop()
        elif kind == "sym":
            if value in "([{":
                brackets.append((value, line))
            elif value in ")]}":
                if not brackets or brackets[-1][0] != PAIRS[value]:
                    errors.append(f"第 {line} 行：多了一個 {value}")
                else:
                    brackets.pop()
        prev = (kind, value)

    # while/for 的 do 已經算在 do 裡；但 while/for 本身不能再算一次 —— 它們不在 OPENERS 裡，所以正確。
    for keyword, line in blocks:
        errors.append(f"第 {line} 行的 {keyword} 沒有對應的 end/until")
    for symbol, line in brackets:
        errors.append(f"第 {line} 行的 {symbol} 沒有關上")

    # require 檢查
    for m in re.finditer(r'require\(script\.Parent:WaitForChild\("(\w+)"\)\)|require\(script\.Parent\.(\w+)\)', text):
        name = m.group(1) or m.group(2)
        if not any((path.parent / f"{name}{ext}").exists() for ext in (".luau",)):
            errors.append(f"require 的模組 {name} 在 {path.parent.relative_to(ROOT)} 裡找不到")
    for m in re.finditer(r'Shared:WaitForChild\("(\w+)"\)\)', text):
        name = m.group(1)
        if not (SRC / "Shared" / f"{name}.luau").exists():
            errors.append(f"Shared 裡找不到模組 {name}")

    return errors


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    files = sorted(SRC.rglob("*.luau"))
    total = 0
    for path in files:
        errors = check_file(path)
        rel = path.relative_to(ROOT)
        if errors:
            total += len(errors)
            print(f"✗ {rel}")
            for e in errors:
                print(f"    {e}")
        else:
            print(f"✓ {rel}")
    print()
    if total:
        print(f"發現 {total} 個問題")
        return 1
    print(f"{len(files)} 個檔案都通過結構檢查")
    return 0


if __name__ == "__main__":
    sys.exit(main())
