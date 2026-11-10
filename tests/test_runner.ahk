#Requires AutoHotkey v2.0
; Tests for the assert helpers / runner itself.

Test_AssertEq_pass() {
    AssertEq(3, 3, "ints")
    AssertEq("a", "a", "strings")
}

Test_AssertTrue_pass() {
    AssertTrue(1 = 1, "true cond")
}

Test_AssertEq_throws_on_mismatch() {
    threw := false
    try AssertEq(1, 2, "mismatch")
    catch
        threw := true
    AssertTrue(threw, "AssertEq should throw")
}

Test_AssertEq_type_strict() {
    threw := false
    try AssertEq(1, "1", "type")
    catch
        threw := true
    AssertTrue(threw, "AssertEq should differ on type")
}

Test_AssertEq_case_sensitive() {
    threw := false
    try AssertEq("ABC", "abc", "case")
    catch
        threw := true
    AssertTrue(threw, "AssertEq should be case-sensitive")
}

Test_AssertEq_object_message_safe() {
    msg := ""
    try AssertEq(Map(), [], "objs")
    catch as e
        msg := e.Message
    AssertTrue(InStr(msg, "Map") && InStr(msg, "Array"), "message should name object types, got: " msg)
}

Test_AssertEq_same_object_passes() {
    m := Map()
    AssertEq(m, m, "same ref")
}
