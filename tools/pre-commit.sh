#!/bin/sh
# Pre-commit hook: runs the whole test suite on exactly what is being
# committed (the staged index, copied to a temp folder) and blocks the
# commit when anything fails, so a new feature can never quietly break an
# old one. Includes the real-frame OCR tests (tests/test_screens.ahk).
#
# Install (once per checkout):  cp tools/pre-commit.sh .git/hooks/pre-commit
# Skip in an emergency:          git commit --no-verify
#
# Test_StripGrab_MatchesPixelGetColor reads the live screen and can flake:
# when it is the only failure the suite is run once more.

AHK="/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
if [ ! -x "$AHK" ]; then
    echo "pre-commit: AutoHotkey v2 not found at $AHK - tests not run, commit blocked" >&2
    exit 1
fi

TMP="${TEMP:-/tmp}/vesper_precommit_$$"
rm -rf "$TMP"
git checkout-index -a --prefix="$TMP/" || { echo "pre-commit: could not copy the staged files" >&2; exit 1; }

run_suite() {
    ( cd "$TMP" && "$AHK" //ErrorStdOut "tests\\run.ahk" > "$TMP/out.txt" 2> "$TMP/err.txt" )
    SUMMARY=$(grep -E '^[0-9]+ passed, [0-9]+ failed' "$TMP/out.txt" | tail -1)
    FAILS=$(grep '^FAIL' "$TMP/out.txt")
}

echo "pre-commit: running the test suite on the staged files..."
run_suite
if [ -n "$FAILS" ] && [ -z "$(echo "$FAILS" | grep -v 'Test_StripGrab_MatchesPixelGetColor')" ]; then
    echo "pre-commit: only the live-screen pixel test failed - running once more"
    run_suite
fi

if [ -z "$SUMMARY" ]; then
    echo "pre-commit: the test run did not finish - commit blocked" >&2
    cat "$TMP/err.txt" >&2
    rm -rf "$TMP"
    exit 1
fi
echo "pre-commit: $SUMMARY"
case "$SUMMARY" in
    *" 0 failed")
        rm -rf "$TMP"
        exit 0 ;;
esac
echo "$FAILS" >&2
echo "pre-commit: tests failed - commit blocked (fix them, or git commit --no-verify)" >&2
rm -rf "$TMP"
exit 1
