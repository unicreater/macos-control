#!/usr/bin/env python3
"""Parse every Swift file in the repo and report syntax errors.

This is not a compiler. It has no type checker, no name resolution and no
semantic analysis, so it will happily accept a call with the wrong argument
labels or a reference to something that doesn't exist. What it does catch is the
class of mistake that is otherwise invisible in an environment with no Swift
toolchain: unbalanced delimiters, malformed declarations, a brace closed one
level too early.

It exists because this repo is written on Linux with no `swiftc` available
(see docs/VERIFY.md), and a syntax smoke test is much better than nothing.

    python3 -m venv .venv
    .venv/bin/pip install tree-sitter tree-sitter-language-pack
    .venv/bin/python scripts/swift-syntax-check.py .

Exit status is 1 if anything is reported, so it can gate a commit.
"""

import sys
import pathlib

try:
    from tree_sitter_language_pack import get_parser
except ImportError:
    sys.exit("pip install tree-sitter tree-sitter-language-pack first")

PARSER = get_parser("swift")

# The grammar cannot parse the empty tuple `()` used as a value, so every
# `return .success(())` — the idiomatic way to produce a Result<Void, _> — comes
# back as a false positive. Verified in isolation: `let v: Void = ()` alone is
# enough to trip it. Suppressed by the source text of the offending line rather
# than by file and line number, so the allowlist doesn't rot as code moves.
KNOWN_GRAMMAR_GAPS = (".success(())",)

SKIP_DIRS = {".build", ".git", "DerivedData", ".venv", "venv"}


def problems(source: bytes):
    """Yield (line, kind, snippet) for each error or missing node."""
    tree = PARSER.parse(source)
    found, stack = [], [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            kind = f"missing {node.type}" if node.is_missing else "syntax error"
            text = source[node.start_byte:node.end_byte][:70]
            found.append((node.start_point[0] + 1, kind,
                          text.decode("utf8", "replace").replace("\n", " ")))
            continue  # an error subtree's children are noise
        stack.extend(node.children)
    return sorted(found)


def main(root: pathlib.Path) -> int:
    # A parser that flags nothing would make a clean run meaningless, so prove it
    # still detects a deliberate error before trusting the result.
    if not problems(b"struct A {\n  func f( -> Int { return 1 }\n"):
        sys.exit("self-test failed: the parser is not detecting errors")

    files = sorted(
        p for p in root.rglob("*.swift")
        if not SKIP_DIRS.intersection(p.parts)
    )

    reported = suppressed = 0
    for path in files:
        source = path.read_bytes()
        lines = source.decode("utf8", "replace").splitlines()
        for line, kind, snippet in problems(source):
            text = lines[line - 1] if line <= len(lines) else ""
            if any(gap in text for gap in KNOWN_GRAMMAR_GAPS):
                suppressed += 1
                continue
            reported += 1
            print(f"{path.relative_to(root)}:{line}: {kind}: {snippet}")

    print(f"\n{len(files)} files parsed, {reported} problems"
          f" ({suppressed} suppressed as known grammar gaps)")
    return 1 if reported else 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()))
