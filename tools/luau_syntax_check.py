#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
luau_syntax_check.py — офлайн-проверка синтаксиса .luau без Roblox Studio.

Идея: Luau = Lua 5.1 + типы. Если аккуратно снять типы, файл обязан парситься
обычным Lua-парсером. Так ловятся опечатки, незакрытые end/скобки и битые
таблицы ещё до открытия Studio.

Установка (один раз):
    python3 -m venv .venv && .venv/bin/pip install luaparser

Запуск:
    python3 tools/luau_syntax_check.py                 # все src/ и tests/
    python3 tools/luau_syntax_check.py src/shared/FrameData.luau
    python3 tools/luau_syntax_check.py --dump src/server/MatchServer.luau
    python3 tools/luau_syntax_check.py --no-parse      # только эвристика по end

Если luaparser не установлен, скрипт не падает: он проверяет баланс блоков
и сообщает, что проверка неполная.
"""

import argparse
import glob
import os
import re
import subprocess
import sys

OPEN_BRACKETS = {"(": ")", "[": "]", "{": "}"}
CLOSE_BRACKETS = {")", "]", "}"}
TYPE_STOP_OPS = {",", ";", "=", ")", "]", "}"}
TYPE_STOP_WORDS = {"then", "do", "end", "in", "elseif", "else", "return", "until"}
PARAM_END_OPS = {",", ")", "=", ";"}


# ---------------------------------------------------------------- токенизация

def tokenize(src):
    """Список токенов (kind, text, start, end).
    kind: str | comment | name | num | op | ws
    Строки и комментарии не разбираются — иначе '::' внутри текста сломает парсинг.
    """
    tokens = []
    i, n = 0, len(src)
    while i < n:
        # длинный комментарий --[[ .. ]] / --[==[ .. ]==]
        if src.startswith("--[", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + m.end())
                j = n if j < 0 else j + len(close)
                tokens.append(("comment", src[i:j], i, j))
                i = j
                continue
        # однострочный комментарий
        if src.startswith("--", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            tokens.append(("comment", src[i:j], i, j))
            i = j
            continue
        # длинная строка [[ .. ]]
        if src[i] == "[":
            m = re.match(r"\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + m.end())
                j = n if j < 0 else j + len(close)
                tokens.append(("str", src[i:j], i, j))
                i = j
                continue
        # обычная строка
        if src[i] in "\"'":
            quote = src[i]
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == quote:
                    j += 1
                    break
                j += 1
            tokens.append(("str", src[i:j], i, j))
            i = j
            continue
        # имя / ключевое слово
        if src[i].isalpha() or src[i] == "_":
            j = i
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            tokens.append(("name", src[i:j], i, j))
            i = j
            continue
        # число (включая 0x1F, 1e-5, 1.5)
        if src[i].isdigit() or (src[i] == "." and i + 1 < n and src[i + 1].isdigit()):
            j = i
            while j < n:
                c = src[j]
                if c.isalnum() or c == ".":
                    j += 1
                elif c in "+-" and j > i and src[j - 1] in "eE":
                    j += 1
                else:
                    break
            tokens.append(("num", src[i:j], i, j))
            i = j
            continue
        # пробельные
        if src[i] in " \t\r\n":
            j = i
            while j < n and src[j] in " \t\r\n":
                j += 1
            tokens.append(("ws", src[i:j], i, j))
            i = j
            continue
        # многосимвольные операторы
        for op in ("...", "::", "==", "~=", "<=", ">=", ".."):
            if src.startswith(op, i):
                tokens.append(("op", op, i, i + len(op)))
                i += len(op)
                break
        else:
            tokens.append(("op", src[i], i, i + 1))
            i += 1
    return tokens


def significant(tokens):
    """Только значимые токены: [(позиция_в_списке, токен), ...]"""
    return [(idx, t) for idx, t in enumerate(tokens) if t[0] not in ("ws", "comment")]


# ---------------------------------------------------------------- снятие типов

def strip_type_aliases(src):
    """Удаляет 'export type X = {...}' / 'type X = ...' вместе с телом."""
    pattern = re.compile(r"(?m)^[ \t]*(export[ \t]+)?type[ \t]+[A-Za-z_]\w*[ \t]*(<[^>\n]*>)?[ \t]*=")
    while True:
        m = pattern.search(src)
        if not m:
            break
        j = m.end()
        while j < len(src) and src[j] in " \t\r\n":
            j += 1
        if j < len(src) and src[j] == "{":
            depth, k, quote = 0, j, None
            while k < len(src):
                c = src[k]
                if quote:
                    if c == "\\":
                        k += 2
                        continue
                    if c == quote:
                        quote = None
                elif c in "\"'":
                    quote = c
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        k += 1
                        break
                k += 1
            j = k
        else:
            nl = src.find("\n", j)
            j = len(src) if nl < 0 else nl
        src = src[: m.start()] + src[j:]
    return src


def _line_of(src, offset):
    return src.count("\n", 0, offset)


def _matching_brace(sig, pos):
    """Для токена '{' в позиции pos возвращает позицию парного '}' или None."""
    depth = 0
    k = pos
    while k < len(sig):
        kind, text = sig[k][1][0], sig[k][1][1]
        if kind == "op" and text in OPEN_BRACKETS:
            depth += 1
        elif kind == "op" and text in CLOSE_BRACKETS:
            depth -= 1
            if depth == 0:
                return k
        k += 1
    return None


def _scan_type_end(src, sig, pos, allow_newline):
    """Конец выражения типа, начиная с pos. Возвращает offset конца (не включительно).

    Правила (тип в Luau однострочный, кроме таблиц {...}):
      * стоп на глубине 0: ',' ')' ']' '}' '=' ';' и ключевые слова then/do/end/...
      * перевод строки на глубине 0 — стоп, если allow_newline
      * '<...>' считается дженериком, только если закрывается на той же строке
      * '{...}' поглощается целиком (таблица-тип может быть многострочной)
    """
    depth = 0
    k = pos
    start_line = _line_of(src, sig[pos][1][2]) if pos < len(sig) else 0
    last_end = sig[pos - 1][1][3] if pos > 0 else 0

    while k < len(sig):
        kind, text = sig[k][1][0], sig[k][1][1]
        tok_start, tok_end = sig[k][1][2], sig[k][1][3]

        # перевод строки на нулевой глубине
        if depth == 0 and _line_of(src, tok_start) > start_line:
            if allow_newline:
                return last_end
            # иначе продолжаем, но только если это '{' (начало таблицы-типа)
            if not (kind == "op" and text == "{"):
                return last_end

        if kind == "op" and text == "{":
            close = _matching_brace(sig, k)
            if close is None:
                return tok_end
            k = close + 1
            last_end = sig[close][1][3]
            continue

        if kind == "op" and text in OPEN_BRACKETS:
            depth += 1
            last_end = tok_end
            k += 1
            continue

        if kind == "op" and text in CLOSE_BRACKETS:
            if depth == 0:
                return last_end
            depth -= 1
            last_end = tok_end
            k += 1
            continue

        if kind == "op" and text == "<":
            # дженерик только если '>' на той же строке
            j = k + 1
            inner = 1
            found = None
            line = _line_of(src, tok_start)
            while j < len(sig):
                jk, jt = sig[j][1][0], sig[j][1][1]
                if _line_of(src, sig[j][1][2]) > line:
                    break
                if jk == "op" and jt == "<":
                    inner += 1
                elif jk == "op" and jt == ">":
                    inner -= 1
                    if inner == 0:
                        found = j
                        break
                j += 1
            if found is not None:
                k = found + 1
                last_end = sig[found][1][3]
                continue
            # иначе это сравнение — тип закончился
            return last_end

        if depth == 0:
            if kind == "op" and text in TYPE_STOP_OPS:
                return last_end
            if kind == "name" and text in TYPE_STOP_WORDS:
                return last_end

        last_end = tok_end
        k += 1

    return last_end


def _annotation_kind(src, sig, pos):
    """Определяет вид ':' в позиции pos: 'param' | 'return' | 'local' | None.

    Главное отличие от наивной версии: смотрим, находимся ли мы внутри списка
    параметров (незакрытая '(' слева) — тогда это параметр, даже если слева имя.
    """
    kind, text = sig[pos][1][0], sig[pos][1][1]
    if kind != "op" or text != ":":
        return None
    if pos == 0 or pos + 1 >= len(sig):
        return None

    prev_kind, prev_text = sig[pos - 1][1][0], sig[pos - 1][1][1]
    next_kind, next_text = sig[pos + 1][1][0], sig[pos + 1][1][1]

    # метод: obj:method( и определение function T:name(
    if next_kind == "name" and pos + 2 < len(sig):
        after = sig[pos + 2][1]
        if after[0] == "op" and after[1] == "(":
            return None
    if next_kind == "str":
        return None

    # аннотация возвращаемого типа: сразу после ')'
    if prev_kind == "op" and prev_text == ")":
        return "return"

    # параметр: после '(' или ','
    if prev_kind == "op" and prev_text in ("(", ","):
        return "param"

    # имя слева: параметр, если мы внутри незакрытой '('
    if prev_kind == "name":
        depth = 0
        k = pos - 1
        while k >= 0:
            kk, kt = sig[k][1][0], sig[k][1][1]
            if kk == "op" and kt in CLOSE_BRACKETS:
                depth += 1
            elif kk == "op" and kt in OPEN_BRACKETS:
                if depth == 0:
                    if kt == "(":
                        return "param"
                    return None
                depth -= 1
            elif depth == 0 and kk == "name" and kt in ("local", "for"):
                return "local"
            k -= 1
        return "local"

    return None


def _brace_depth_map(sig):
    depths = []
    depth = 0
    for _, tok in sig:
        if tok[0] == "op" and tok[1] == "{":
            depths.append(depth)
            depth += 1
            continue
        if tok[0] == "op" and tok[1] == "}":
            depth = max(0, depth - 1)
            depths.append(depth)
            continue
        depths.append(depth)
    return depths


def clean(src):
    """Luau -> Lua 5.1: снимаем типы, сохраняя структуру блоков."""
    # 1) директивы --!strict
    src = re.sub(r"(?m)^--!.*$", "", src)
    # 2) алиасы типов
    src = strip_type_aliases(src)

    tokens = tokenize(src)
    sig = significant(tokens)

    removals = []       # (start, end)
    consumed = set()    # позиции sig, уже поглощённые таблицами-типов

    for pos in range(len(sig)):
        if pos in consumed:
            continue
        kind, text = sig[pos][1][0], sig[pos][1][1]

        is_cast = kind == "op" and text == "::"
        annot = None if is_cast else _annotation_kind(src, sig, pos)
        if not is_cast and not annot:
            continue

        type_start = pos + 1
        if type_start >= len(sig):
            break

        allow_newline = annot == "return"
        end_offset = _scan_type_end(src, sig, type_start, allow_newline)
        start_offset = sig[pos][1][2]
        if end_offset <= start_offset:
            continue

        # помечаем поглощённые токены (внутри таблиц-типов), чтобы их ':' не
        # обрабатывался повторно
        close = None
        if sig[type_start][1][0] == "op" and sig[type_start][1][1] == "{":
            close = _matching_brace(sig, type_start)
        if close is not None:
            for k in range(type_start, close + 1):
                consumed.add(k)
        else:
            k = type_start
            while k < len(sig) and sig[k][1][3] <= end_offset:
                consumed.add(k)
                k += 1

        removals.append((start_offset, end_offset))

    # применяем справа налево, пропуская пересечения
    removals.sort(key=lambda r: r[0], reverse=True)
    out = src
    boundary = None
    for start, end in removals:
        if end <= start:
            continue
        if boundary is not None and end > boundary:
            continue
        out = out[:start] + out[end:]
        boundary = start

    # 3) одиночные '?' опциональных типов
    out = _strip_question_marks(out)

    # 4) составные присваивания Luau -> обычные Lua
    out = re.sub(
        r"(?m)^([ \t]*)([\w\.\)\]\}:]+)[ \t]*(\+|-|\*|/|%|//)=[ \t]*(.+?)([ \t]*)$",
        lambda m: f"{m.group(1)}{m.group(2)} = {m.group(2)} {m.group(3)} ({m.group(4)}){m.group(5)}",
        out,
    )

    # 5) continue -> do end
    out = re.sub(r"(?<![\w.])continue(?![\w.])", "do end", out)

    # 6) интерполированные строки `..` -> обычные
    out = re.sub(
        r"`([^`]*)`",
        lambda m: '"' + m.group(1).replace("{", "(").replace("}", ")").replace('"', "'") + '"',
        out,
    )

    return out


def _strip_question_marks(src):
    """Убирает '?' опциональных типов вне строк и комментариев.
    Работает по токенам, чтобы не трогать текст в строках.
    """
    tokens = tokenize(src)
    out = []
    for kind, text, _, _ in tokens:
        if kind == "op" and text == "?":
            continue
        out.append(text)
    return "".join(out)


# ---------------------------------------------------------------- проверка

def find_python_with_luaparser():
    candidates = [
        os.path.join(".venv", "bin", "python"),
        os.path.join(".venv", "Scripts", "python.exe"),
        sys.executable,
    ]
    for c in candidates:
        if not c:
            continue
        if c != sys.executable and not os.path.exists(c):
            continue
        try:
            r = subprocess.run([c, "-c", "import luaparser"], capture_output=True, timeout=60)
            if r.returncode == 0:
                return c
        except Exception:
            continue
    return None


def parse_with(python_exe, lua_src):
    # Собственный раннер: luaparser по умолчанию прячет позицию ошибки
    # ("syntax errors: None"), поэтому слушаем antlr напрямую.
    runner = r"""
import sys
from antlr4 import InputStream, CommonTokenStream
from antlr4.error.ErrorListener import ErrorListener
from luaparser.parser.LuaLexer import LuaLexer
from luaparser.parser.LuaParser import LuaParser

class Listener(ErrorListener):
    def __init__(self):
        self.msgs = []
    def syntaxError(self, recognizer, offendingSymbol, line, column, msg, e):
        self.msgs.append("line %s:%s: %s" % (line, column, msg))
    def reportAmbiguity(self, *a): pass
    def reportAttemptingFullContext(self, *a): pass
    def reportContextSensitivity(self, *a): pass

src = sys.stdin.read()
lexer = LuaLexer(InputStream(src))
lexer.removeErrorListeners()
listener = Listener()
lexer.addErrorListener(listener)
stream = CommonTokenStream(lexer)
parser = LuaParser(stream)
parser.removeErrorListeners()
parser.addErrorListener(listener)
parser.start_()

errors = parser.getNumberOfSyntaxErrors() + len(listener.msgs)
if errors:
    lines = src.split("\n")
    out = []
    for m in listener.msgs[:4]:
        out.append(m)
        try:
            ln = int(m.split("line ")[1].split(":")[0]) - 1
            if 0 <= ln < len(lines):
                out.append("    | " + lines[ln].strip()[:160])
        except Exception:
            pass
    print("ERR: " + " ;; ".join(out))
    sys.exit(1)
print("OK")
"""
    r = subprocess.run(
        [python_exe, "-c", runner],
        input=lua_src.encode("utf-8"),
        capture_output=True,
        timeout=180,
    )
    msg = r.stdout.decode("utf-8", "replace").strip() or r.stderr.decode("utf-8", "replace").strip()
    return r.returncode == 0, msg


def heuristic_check(cleaned):
    """Грубая проверка баланса блоков, если парсер недоступен."""
    text = re.sub(r"(?m)--.*$", "", cleaned)
    text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)
    text = re.sub(r"'(?:[^'\\]|\\.)*'", "''", text)
    opens = len(re.findall(r"\b(?:function|then|do)\b", text))
    # 'for ... do' и 'while ... do' дают один do; 'repeat' закрывается 'until'
    closes = len(re.findall(r"\bend\b", text))
    parens = text.count("(") - text.count(")")
    braces = text.count("{") - text.count("}")
    brackets = text.count("[") - text.count("]")
    problems = []
    if abs(opens - closes) > 0:
        problems.append(f"блоки: function/then/do={opens}, end={closes}")
    if parens:
        problems.append(f"скобки () не сбалансированы: {parens:+d}")
    if braces:
        problems.append(f"фигурные {{}} не сбалансированы: {braces:+d}")
    if brackets:
        problems.append(f"квадратные [] не сбалансированы: {brackets:+d}")
    return problems


def iter_files(args):
    if args.files:
        return args.files
    out = []
    for pat in ("src/**/*.luau", "tests/**/*.luau"):
        out.extend(sorted(glob.glob(pat, recursive=True)))
    return out


def main():
    ap = argparse.ArgumentParser(description="Офлайн-проверка синтаксиса .luau")
    ap.add_argument("files", nargs="*", help="файлы (по умолчанию все src/ и tests/)")
    ap.add_argument("--dump", action="store_true", help="напечатать очищенный Lua")
    ap.add_argument("--no-parse", action="store_true", help="только эвристика, без парсера")
    args = ap.parse_args()

    files = iter_files(args)
    if not files:
        print("нет файлов для проверки")
        return 1

    pyexe = None
    if not args.dump and not args.no_parse:
        pyexe = find_python_with_luaparser()
        if not pyexe:
            print("⚠ luaparser не найден — будет только эвристика по блокам.")
            print("  Установи: python3 -m venv .venv && .venv/bin/pip install luaparser")
            print()

    failed = []
    for path in files:
        try:
            src = open(path, encoding="utf-8").read()
        except OSError as e:
            failed.append((path, str(e)))
            print(f"{path}: FAIL — {e}")
            continue

        try:
            cleaned = clean(src)
        except Exception as e:
            failed.append((path, f"конвертер упал: {e}"))
            print(f"{path}: FAIL — конвертер упал: {e}")
            continue

        if args.dump:
            print(f"===== {path} =====")
            print(cleaned)
            continue

        if pyexe:
            ok, msg = parse_with(pyexe, cleaned)
            if ok:
                print(f"{path}: OK")
            else:
                print(f"{path}: FAIL — {msg[:400]}")
                failed.append((path, msg))
        else:
            problems = heuristic_check(cleaned)
            if problems:
                print(f"{path}: SUSPECT — " + "; ".join(problems))
                failed.append((path, "; ".join(problems)))
            else:
                print(f"{path}: OK (эвристика)")

    if args.dump:
        return 0

    print()
    if failed:
        print(f"❌ проблемных файлов: {len(failed)} из {len(files)}")
        return 1
    mode = "полный парсинг" if pyexe else "эвристика"
    print(f"✅ синтаксис чистый ({mode}): {len(files)} файлов")
    return 0


if __name__ == "__main__":
    sys.exit(main())
