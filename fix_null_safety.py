from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_ROOTS = [
    "dependencies/Flare-Flutter/flare_dart/lib",
    "dependencies/Flare-Flutter/flare_flutter/lib",
    "dependencies/Nima-Flutter/lib",
]

EXCLUDE_DIR_NAMES = {
    ".dart_tool",
    "build",
    ".git",
    ".idea",
    ".vscode",
}


@dataclass
class FixStats:
    files_changed: int = 0
    replacements: int = 0

    late_return_lines: int = 0
    list_empty_ctor: int = 0
    list_len_ctor: int = 0
    required_annotation: int = 0
    read_param_nullable: int = 0
    stream_reader_block_nullable: int = 0


_RE_LATE_RETURN_LINE = re.compile(r"^(?P<indent>\s*)late\s+return\s+(?P<expr>.+?);\s*$", re.MULTILINE)

# Old-style list constructors:
# - List<T>() / new List<T>()  -> <T>[]
_RE_LIST_EMPTY_CTOR = re.compile(r"\b(?:new\s+)?List<(?P<t>[^>]+)>\(\)")

# - List<T>(n) / new List<T>(n) -> List<T?>.filled(n, null)
# NOTE: This is intentionally conservative: we make element type nullable.
_RE_LIST_LEN_CTOR = re.compile(r"\b(?:new\s+)?List<(?P<t>[^>]+)>\((?P<n>[^)]+)\)")

_RE_REQUIRED = re.compile(r"\B@required\b")

# StreamReader block; while ((block = ...) != null)  -> StreamReader? block;
_RE_STREAMREADER_DECL = re.compile(r"^(?P<indent>\s*)StreamReader\s+(?P<name>[A-Za-z_]\w*)\s*;\s*$", re.MULTILINE)

# if (x == null) { x = Type();  (typical read(...) pattern)
_RE_IF_NULL_ASSIGN = re.compile(
    r"if\s*\(\s*(?P<name>[A-Za-z_]\w*)\s*==\s*null\s*\)\s*\{\s*(?P=name)\s*=\s*(?P<type>[A-Za-z_]\w*)\s*\(\s*\)\s*;",
    re.DOTALL,
)


def _make_nullable_type(t: str) -> str:
    t2 = t.strip()
    if t2.endswith("?"):
        return t2
    return f"{t2}?"


def _fix_late_return_lines(text: str, stats: FixStats) -> str:
    def repl(m: re.Match[str]) -> str:
        stats.late_return_lines += 1
        stats.replacements += 1
        return f"{m.group('indent')}return {m.group('expr')};"

    return _RE_LATE_RETURN_LINE.sub(repl, text)


def _fix_required_annotation(text: str, stats: FixStats) -> str:
    (text2, n) = _RE_REQUIRED.subn("required", text)
    if n:
        stats.required_annotation += n
        stats.replacements += n
    return text2


def _fix_list_empty_ctor(text: str, stats: FixStats) -> str:
    def repl(m: re.Match[str]) -> str:
        stats.list_empty_ctor += 1
        stats.replacements += 1
        t = m.group("t").strip()
        return f"<{t}>[]"

    return _RE_LIST_EMPTY_CTOR.sub(repl, text)


def _fix_list_len_ctor(text: str, stats: FixStats) -> str:
    # Avoid touching List<T>.filled / List<T>.generate etc.
    # This regex only matches the legacy constructor-style `List<T>(n)` so it's safe.
    def repl(m: re.Match[str]) -> str:
        stats.list_len_ctor += 1
        stats.replacements += 1
        t = m.group("t").strip()
        n = m.group("n").strip()
        return f"List<{_make_nullable_type(t)}>.filled({n}, null)"

    return _RE_LIST_LEN_CTOR.sub(repl, text)


def _fix_stream_reader_block_nullable(text: str, stats: FixStats) -> str:
    # If a variable is declared `StreamReader name;` AND we later do
    # `while ((name = reader.readNextBlock(...)) != null)` then it must be nullable.
    decls = {m.group("name") for m in _RE_STREAMREADER_DECL.finditer(text)}
    if not decls:
        return text

    needed = set()
    for name in decls:
        if re.search(rf"while\s*\(\s*\(\s*{re.escape(name)}\s*=\s*[^)]+\)\s*!=\s*null\s*\)", text):
            needed.add(name)

    if not needed:
        return text

    def repl(m: re.Match[str]) -> str:
        name = m.group("name")
        if name not in needed:
            return m.group(0)
        stats.stream_reader_block_nullable += 1
        stats.replacements += 1
        return f"{m.group('indent')}StreamReader? {name};"

    return _RE_STREAMREADER_DECL.sub(repl, text)


def _find_matching(text: str, start: int, open_ch: str, close_ch: str) -> int | None:
    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
    return None


def _fix_nullable_params_in_static_read_functions(text: str, stats: FixStats) -> str:
    """
    For patterns like:
      static Foo read(..., Foo node) {
        if (node == null) node = Foo();
      }
    we change the parameter to `Foo? node`.

    This is intentionally scoped to functions whose name contains `read(` and that are `static`,
    because that's the common pattern in Flare/Nima importers.
    """
    out = []
    i = 0
    changed_any = False

    while True:
        idx = text.find("read(", i)
        if idx == -1:
            out.append(text[i:])
            break

        # Heuristic: only touch if there is a "static" nearby before the read(
        sig_start = text.rfind("\n", 0, idx)
        sig_start = 0 if sig_start == -1 else sig_start + 1
        if "static" not in text[sig_start:idx]:
            i = idx + 5
            continue

        paren_open = idx + len("read")
        if paren_open >= len(text) or text[paren_open] != "(":
            i = idx + 5
            continue

        paren_close = _find_matching(text, paren_open, "(", ")")
        if paren_close is None:
            i = idx + 5
            continue

        # Find body open brace
        body_open = text.find("{", paren_close)
        if body_open == -1:
            i = idx + 5
            continue

        body_close = _find_matching(text, body_open, "{", "}")
        if body_close is None:
            i = idx + 5
            continue

        before = text[i:sig_start]
        signature_head = text[sig_start:paren_open]  # includes '... read'
        paramlist = text[paren_open + 1 : paren_close]
        body = text[body_open : body_close + 1]
        after = text[body_close + 1 :]

        # Detect null-assign patterns in body
        fixes = []
        for m in _RE_IF_NULL_ASSIGN.finditer(body):
            name = m.group("name")
            typ = m.group("type")
            fixes.append((typ, name))

        if not fixes:
            i = body_close + 1
            continue

        new_paramlist = paramlist
        did_change = False
        for typ, name in fixes:
            # Replace only in parameter list
            # We look for "... Type name ..." and turn it into "... Type? name ..."
            # (unless already nullable)
            pat = re.compile(rf"\b{re.escape(typ)}\s+\b{re.escape(name)}\b")

            def _repl(mm: re.Match[str]) -> str:
                nonlocal did_change
                did_change = True
                return f"{typ}? {name}"

            # Only if not already `Type? name`
            if re.search(rf"\b{re.escape(typ)}\?\s+\b{re.escape(name)}\b", new_paramlist):
                continue
            (new_paramlist, n) = pat.subn(_repl, new_paramlist, count=1)
            if n:
                stats.read_param_nullable += 1
                stats.replacements += 1

        if not did_change:
            i = body_close + 1
            continue

        changed_any = True
        out.append(before)
        out.append(signature_head)
        out.append("(")
        out.append(new_paramlist)
        out.append(")")
        out.append(text[paren_close + 1 : body_open])  # whitespace/newlines between ) and {
        out.append(body)

        # Move cursor
        text = "".join(out) + after
        out = []
        i = body_close + 1  # best effort; text has changed but still monotonic

    return text


def fix_text(text: str, stats: FixStats) -> str:
    text2 = text
    text2 = _fix_late_return_lines(text2, stats)
    text2 = _fix_required_annotation(text2, stats)
    text2 = _fix_stream_reader_block_nullable(text2, stats)
    text2 = _fix_nullable_params_in_static_read_functions(text2, stats)
    text2 = _fix_list_empty_ctor(text2, stats)
    text2 = _fix_list_len_ctor(text2, stats)
    return text2


def iter_dart_files(roots: Iterable[Path]) -> Iterable[Path]:
    for root in roots:
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            # prune excluded dirs
            dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIR_NAMES]
            for fn in filenames:
                if fn.endswith(".dart"):
                    yield Path(dirpath) / fn


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Batch-fix obvious Dart null-safety migration issues (mechanical, conservative)."
    )
    parser.add_argument(
        "--roots",
        nargs="*",
        default=DEFAULT_ROOTS,
        help="Root directories to scan (default: Flare/Nima libs).",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Dry-run: show which files would change without writing.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent
    roots = [repo_root / r for r in args.roots]

    stats = FixStats()
    changed_paths: list[Path] = []

    for path in iter_dart_files(roots):
        try:
            old = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        file_stats_before = stats.replacements
        new = fix_text(old, stats)
        if new != old:
            changed_paths.append(path)
            stats.files_changed += 1

            if not args.check:
                path.write_text(new, encoding="utf-8")

        # If a file had no changes, do nothing; stats already counts replacements.
        _ = file_stats_before

    for p in changed_paths:
        print(f"would-fix: {p.relative_to(repo_root)}" if args.check else f"fixed: {p.relative_to(repo_root)}")

    print(
        "\n".join(
            [
                "",
                "summary:",
                f"  files_changed={stats.files_changed}",
                f"  replacements={stats.replacements}",
                f"  late_return_lines={stats.late_return_lines}",
                f"  required_annotation={stats.required_annotation}",
                f"  stream_reader_block_nullable={stats.stream_reader_block_nullable}",
                f"  read_param_nullable={stats.read_param_nullable}",
                f"  list_empty_ctor={stats.list_empty_ctor}",
                f"  list_len_ctor={stats.list_len_ctor}",
            ]
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
