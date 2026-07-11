#!/usr/bin/env bash
# huo/mayhem/build.sh — build the huo interpreter as the fuzz target.
#
# huo is a small Lisp-ish C-implemented interpreter: main() (src/huo.c) reads a source file from a CLI
# path argument, tokenizes it (src/tokenizer.c), parses it into an AST (src/parser.c), then executes
# (src/execute.c + src/execution_functions/*). The natural fuzz surface is the interpreter itself on a
# source file — so the Mayhem target is FILE-INPUT (CLI): `/mayhem/huo @@` runs huo on the fuzz bytes as
# a .huo program (tokenize + parse + execute). No libFuzzer harness, and therefore no per-harness
# standalone reproducer — the interpreter binary IS the reproducer (run it on the crashing file).
#
# We compile the WHOLE interpreter with $SANITIZER_FLAGS (ASan+UBSan, halting, by default) so the fuzzed
# code — tokenizer, parser, evaluator — is instrumented, not just an entry shim. The target lands at
# /mayhem/huo. (Mayhem chdir's into /mayhem to run it, so huo's `import`/`core/` relative paths resolve.)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty value
# (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the interpreter's natural crash). huo
# links only -lpthread (see below), which is independent of the sanitizer runtime, so the empty-sanitizer
# build links cleanly with no extra flags.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# Bake ASan/LSan defaults (detect_leaks=0) into the target via a weak __asan_default_options symbol.
# huo never frees its arena, so LeakSanitizer would flag a "leak crash" on EVERY input; we disable ONLY
# leak detection while keeping ASan's memory-safety checks + all of UBSan ON and HALTING. This is the
# spec-sanctioned alternative to ASAN_OPTIONS in the Mayhemfile (which is forbidden). The object is
# linked into huo via the Makefile's LIBS hook (appended to the final link line). Compiled WITH
# $SANITIZER_FLAGS for consistency; the symbol is weak so it's inert when sanitizers are off.
ASAN_OPTS_OBJ=/tmp/huo_asan_default_options.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O2 -c "$SRC/mayhem/asan_default_options.c" -o "$ASAN_OPTS_OBJ"

# huo's Makefile drives the whole object list and links `-lpthread` (huo's `parallel` uses pthreads).
# It reads CC/CFLAGS/LDFLAGS/LIBS from the environment, so we feed $SANITIZER_FLAGS through both compile
# and link, and append our ASan-options object via LIBS (Makefile: `$(CC) $(LDFLAGS) -o huo $(objs)
# $(LIBS)`). We keep huo's own -std=c11 dialect and -O2; we drop the project's strict warnings to
# noise-level (-w) so the clean build stays quiet (these warnings — e.g. realpath's implicit decl on the
# unused no-arg REPL path — don't affect the fuzzed tokenize/parse/execute path). -rdynamic is preserved
# (huo's ERROR() prints a backtrace via dladdr).
make clean >/dev/null 2>&1 || true
make -j"$MAYHEM_JOBS" \
  CC="$CC" \
  CFLAGS="-std=c11 -O2 -w $SANITIZER_FLAGS $DEBUG_FLAGS" \
  LDFLAGS="-rdynamic $SANITIZER_FLAGS $DEBUG_FLAGS" \
  LIBS="-lpthread $ASAN_OPTS_OBJ"

# huo's Makefile builds the binary at $SRC/huo; expose it as the Mayhem target at /mayhem/huo. In the
# commit image $SRC IS /mayhem (so $SRC/huo already == /mayhem/huo — skip the self-copy); guard for any
# build where $SRC differs.
test -x "$SRC/huo" || { echo "build.sh: huo binary not produced" >&2; exit 1; }
[ "$SRC/huo" -ef /mayhem/huo ] || cp -f "$SRC/huo" /mayhem/huo

echo "build.sh: built /mayhem/huo (sanitized file-input fuzz target)"
ls -l /mayhem/huo
