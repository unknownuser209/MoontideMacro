#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Minimal JSON parse/stringify (original code, no third-party source).
;
; Mapping (documented deviations, AHK has no native bool/null):
;   JSON object -> Map (case-sensitive keys)      Map  -> JSON object
;   JSON array  -> Array                          Array-> JSON array
;   JSON string -> String                         String -> JSON string
;   JSON number -> Integer (no . or exponent) or Float
;   true / false -> 1 / 0   (Integer; they stringify back as 1 / 0)
;   null        -> ""       (empty string)
;
; Notes:
;   - Map enumeration in AHK is key-sorted, so Stringify emits object keys
;     sorted. Array order is preserved.
;   - Stringify throws TypeError for anything but Map/Array/String/Integer/
;     Float, and ValueError for NaN/Infinity.
;   - Parse throws ValueError("JSON: <reason> at position N"). Error text
;     never contains the input text.
;   - A leading UTF-8 BOM (U+FEFF) is ignored. Nesting depth limit: 200.
; ---------------------------------------------------------------------------

class Json {
    static Parse(str) {
        return Json._Parser(str).Run()
    }

    ; Pre-rendered JSON literal for Stringify (e.g. Json.Raw("true")): AHK has
    ; no boolean type, and Discord rejects 1/0 where it wants true/false.
    class Raw {
        __New(text) {
            if !(text is String) || !RegExMatch(text, "^(true|false|null)$")
                throw ValueError("Json.Raw: only true, false or null")
            this.text := text
        }
    }

    static Stringify(obj, indent := 2) {
        return Json._Write(obj, Max(0, Integer(indent)), 0)
    }

    ; ---- writer ------------------------------------------------------------

    static _Spaces(n) {
        s := ""
        Loop n
            s .= " "
        return s
    }

    static _Write(v, indent, level) {
        if (v is Map) {
            if (v.Count = 0)
                return "{}"
            nl1 := indent > 0 ? "`n" Json._Spaces(indent * (level + 1)) : ""
            nl0 := indent > 0 ? "`n" Json._Spaces(indent * level) : ""
            sep := indent > 0 ? ": " : ":"
            out := ""
            first := true
            for k, val in v {
                out .= (first ? "" : ",") nl1 Json._Quote(String(k)) sep Json._Write(val, indent, level + 1)
                first := false
            }
            return "{" out nl0 "}"
        }
        if (v is Array) {
            if (v.Length = 0)
                return "[]"
            nl1 := indent > 0 ? "`n" Json._Spaces(indent * (level + 1)) : ""
            nl0 := indent > 0 ? "`n" Json._Spaces(indent * level) : ""
            out := ""
            first := true
            for val in v {
                out .= (first ? "" : ",") nl1 Json._Write(val, indent, level + 1)
                first := false
            }
            return "[" out nl0 "]"
        }
        if (v is Json.Raw)
            return v.text
        t := Type(v)
        if (t = "String")
            return Json._Quote(v)
        if (t = "Integer")
            return String(v)
        if (t = "Float") {
            s := String(v)
            if !RegExMatch(s, "^-?\d+(\.\d+)?([eE][+-]?\d+)?$")
                throw ValueError("JSON: cannot stringify non-finite number")
            return s
        }
        throw TypeError("JSON: cannot stringify value of type " t)
    }

    static _Quote(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        if RegExMatch(s, "[\x00-\x1F]") {
            s := StrReplace(s, "`n", "\n")
            s := StrReplace(s, "`r", "\r")
            s := StrReplace(s, "`t", "\t")
            s := StrReplace(s, "`b", "\b")
            s := StrReplace(s, "`f", "\f")
            Loop 32 {
                c := A_Index - 1
                if InStr(s, Chr(c))
                    s := StrReplace(s, Chr(c), Format("\u{:04x}", c))
            }
        }
        return '"' s '"'
    }

    ; ---- parser ------------------------------------------------------------

    class _Parser {
        static Esc := Map('"', '"', "\", "\", "/", "/", "b", "`b", "f", "`f", "n", "`n", "r", "`r", "t", "`t")

        __New(text) {
            this.s := String(text)
            this.n := StrLen(this.s)
            this.i := 1
        }

        Run() {
            if (this.n >= 1 && Ord(this.s) = 0xFEFF)
                this.i := 2
            this.Ws()
            v := this.Value(0)
            this.Ws()
            if (this.i <= this.n)
                this.Fail("unexpected trailing characters")
            return v
        }

        Fail(msg) {
            throw ValueError("JSON: " msg " at position " this.i)
        }

        Ws() {
            while (this.i <= this.n) {
                c := SubStr(this.s, this.i, 1)
                if (c == " " || c == "`t" || c == "`n" || c == "`r")
                    this.i++
                else
                    break
            }
        }

        Expect(ch) {
            if (SubStr(this.s, this.i, 1) !== ch)
                this.Fail("expected '" ch "'")
            this.i++
        }

        Value(depth) {
            if (depth > 200)
                this.Fail("nesting too deep")
            if (this.i > this.n)
                this.Fail("unexpected end of input")
            c := SubStr(this.s, this.i, 1)
            if (c == "{")
                return this.Obj(depth)
            if (c == "[")
                return this.Arr(depth)
            if (c == '"')
                return this.Str()
            if (SubStr(this.s, this.i, 4) == "true") {
                this.i += 4
                return 1
            }
            if (SubStr(this.s, this.i, 5) == "false") {
                this.i += 5
                return 0
            }
            if (SubStr(this.s, this.i, 4) == "null") {
                this.i += 4
                return ""
            }
            return this.Num()
        }

        Num() {
            if !RegExMatch(this.s, "A)-?(?:0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?", &m, this.i)
                this.Fail("unexpected character")
            this.i += m.Len
            if (m[1] == "" && m[2] == "") {
                if (StrLen(m[0]) <= 18)
                    return Integer(m[0])
                return Float(m[0])
            }
            return Float(m[0])
        }

        Str() {
            this.i++    ; opening quote
            out := ""
            Loop {
                if !RegExMatch(this.s, '["\\\x00-\x1F]', &m, this.i)
                    this.Fail("unterminated string")
                j := m.Pos
                out .= SubStr(this.s, this.i, j - this.i)
                ch := m[0]
                if (ch == '"') {
                    this.i := j + 1
                    return out
                }
                if (ch != "\") {
                    this.i := j
                    this.Fail("control character in string")
                }
                esc := SubStr(this.s, j + 1, 1)
                if (esc == "u") {
                    hex := SubStr(this.s, j + 2, 4)
                    if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$") {
                        this.i := j
                        this.Fail("bad \u escape")
                    }
                    out .= Chr(Integer("0x" hex))
                    this.i := j + 6
                } else if (esc != "" && Json._Parser.Esc.Has(esc)) {
                    out .= Json._Parser.Esc[esc]
                    this.i := j + 2
                } else {
                    this.i := j
                    this.Fail("bad escape")
                }
            }
        }

        Obj(depth) {
            this.i++    ; {
            m := Map()
            this.Ws()
            if (SubStr(this.s, this.i, 1) == "}") {
                this.i++
                return m
            }
            Loop {
                this.Ws()
                if (SubStr(this.s, this.i, 1) !== '"')
                    this.Fail("expected string key")
                k := this.Str()
                this.Ws()
                this.Expect(":")
                this.Ws()
                m[k] := this.Value(depth + 1)
                this.Ws()
                c := SubStr(this.s, this.i, 1)
                this.i++
                if (c == "}")
                    return m
                if (c !== ",") {
                    this.i--
                    this.Fail("expected ',' or '}'")
                }
            }
        }

        Arr(depth) {
            this.i++    ; [
            a := []
            this.Ws()
            if (SubStr(this.s, this.i, 1) == "]") {
                this.i++
                return a
            }
            Loop {
                this.Ws()
                a.Push(this.Value(depth + 1))
                this.Ws()
                c := SubStr(this.s, this.i, 1)
                this.i++
                if (c == "]")
                    return a
                if (c !== ",") {
                    this.i--
                    this.Fail("expected ',' or ']'")
                }
            }
        }
    }
}
