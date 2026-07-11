/*
 * asan_default_options.c — bake ASan/LSan defaults into the huo fuzz target.
 *
 * huo is an arena-style interpreter: it allocates tokens/AST/values as it runs and NEVER frees them
 * (it relies on process exit to reclaim). Under ASan's default LeakSanitizer, EVERY input — including
 * valid programs and the empty seed — reports "detected memory leaks" at exit and aborts, which Mayhem
 * would record as a crash on every single input, burying any real memory-safety defect.
 *
 * We disable ONLY leak detection (detect_leaks=0); ASan's heap/stack/global overflow + use-after-free
 * checks and ALL of UBSan stay ON and HALTING — those still crash the fuzzer on a genuine bug. This is
 * the SPEC-sanctioned way to set ASan options for a target: a weak __asan_default_options symbol baked
 * into the binary, NOT ASAN_OPTIONS in the Mayhemfile (which the spec forbids).
 *
 * The symbol is defined STRONG (not weak): the ASan runtime ships its OWN weak __asan_default_options
 * returning "", so a second WEAK definition here would tie and the linker could pick the runtime's empty
 * one (observed: leaks still fired). A strong definition reliably overrides the runtime's weak default.
 * When the target is built with sanitizers OFF (--build-arg SANITIZER_FLAGS=), nothing references this
 * function and no ASan runtime is linked, so it's harmless dead code.
 */
const char *__asan_default_options(void) {
    return "detect_leaks=0";
}
