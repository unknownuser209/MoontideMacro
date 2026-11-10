#Requires AutoHotkey v2.0
; Assertion helpers. A failed assertion throws; the runner reports it as FAIL.

AssertEq(actual, expected, name) {
    ; Case-sensitive, type-aware. Objects compare by identity (!== on refs).
    if (Type(actual) != Type(expected) || actual !== expected)
        throw Error(name ": expected <" AssertShow(expected) "> (" Type(expected) ") got <" AssertShow(actual) "> (" Type(actual) ")")
}

AssertTrue(cond, name) {
    if !cond
        throw Error(name ": expected truthy value")
}

; String(x) throws for Objects; show their type instead.
AssertShow(x) {
    return IsObject(x) ? Type(x) : String(x)
}
