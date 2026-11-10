#Requires AutoHotkey v2.0
; The creator's credit, kept as encoded number arrays (never as plain text in
; this file) and decoded on demand. Credits.Verify() checks that this file and
; the avatar picture are the shipped ones: a SHA-256 over both, compared with
; the values stored (encoded the same way) in lib\Brand.ahk and
; lib\ui\Splash.ahk. A mismatch never stops the macro, it only shows a banner.
; tools\update_credits.ahk rewrites the stored values after an intended edit.
#Include %A_LineFile%\..\Brand.ahk
#Include %A_LineFile%\..\ui\Splash.ahk

class Credits {
    static _name := [112, 32, 23, 243, 199, 179]
    static _discord := [8, 48, 10, 226, 212, 160, 137, 147, 127, 95, 48, 30, 239, 202, 189, 133, 56]
    static _message := [82, 45, 5, 237, 201, 178, 192, 153, 113, 79, 124, 14, 233, 208, 182, 144, 54, 65, 60, 26, 225, 157, 240, 135, 97, 93, 41, 13, 255, 197, 164, 158, 38, 76, 48, 67, 234, 196, 172, 175, 155, 121, 28, 34, 21, 236, 152, 182, 133, 53, 89, 38, 17, 249, 144, 174, 157, 45, 69, 63, 74, 225, 205, 171, 150, 96, 64, 99, 15, 228, 128, 222, 178, 142, 115, 27, 62, 22, 253, 196, 246, 148, 122, 74, 61, 31, 245, 143, 188, 136, 97, 78, 39, 11, 237, 213, 230, 129, 107, 79, 50, 9, 243, 240, 210, 226]

    static Name() => Credits.Decode(Credits._name)
    static Discord() => Credits.Decode(Credits._discord)
    static Message() => Credits.Decode(Credits._message)
    static Server() => Brand.DiscordUrl
    static MadeBy() => "made by " Credits.Name()
    static ByLine() => "by " Credits.Name()
    static Banner() => "Modified copy " Chr(0xB7) " original " Credits.ByLine()

    ; code[i] = Ord(ch) ^ ((i * 31 + 7) & 0xFF), i counted from 1.
    static Decode(arr) {
        s := ""
        for i, code in arr
            s .= Chr(code ^ ((i * 31 + 7) & 0xFF))
        return s
    }

    static Encode(s) {
        arr := []
        Loop Parse, s
            arr.Push(Ord(A_LoopField) ^ ((A_Index * 31 + 7) & 0xFF))
        return arr
    }

    ; Lower-case hex SHA-256 of a Buffer (Windows CNG).
    static Sha256(buf) {
        hAlg := 0
        if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "WStr", "SHA256", "Ptr", 0, "UInt", 0, "UInt") != 0
            throw Error("SHA-256 is not available")
        out := Buffer(32, 0)
        st := DllCall("bcrypt\BCryptHash", "Ptr", hAlg, "Ptr", 0, "UInt", 0, "Ptr", buf, "UInt", buf.Size, "Ptr", out, "UInt", 32, "UInt")
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        if st != 0
            throw Error("SHA-256 failed")
        hex := ""
        Loop 32
            hex .= Format("{:02x}", NumGet(out, A_Index - 1, "UChar"))
        return hex
    }

    ; The repo root: the parent of the lib folder this file lives in.
    static Root() {
        SplitPath(A_LineFile, , &libDir)
        SplitPath(libDir, , &root)
        return root
    }

    ; SHA-256 over lib\Credits.ahk then assets\credits\avatar.png under root;
    ; "" when either file is missing or unreadable.
    static Fingerprint(root) {
        files := [root "\lib\Credits.ahk", root "\assets\credits\avatar.png"]
        parts := []
        total := 0
        for path in files {
            if !FileExist(path)
                return ""
            try b := FileRead(path, "RAW")
            catch
                return ""
            parts.Push(b)
            total += b.Size
        }
        all := Buffer(total, 0)
        pos := 0
        for b in parts {
            if b.Size
                DllCall("RtlMoveMemory", "Ptr", all.Ptr + pos, "Ptr", b, "UPtr", b.Size)
            pos += b.Size
        }
        return Credits.Sha256(all)
    }

    ; {ok, why}. With no root the stored values are the ones compiled in
    ; (Brand._ck, Splash._ck); with a root they are read from that root's files.
    static Verify(root := "") {
        explicit := (root != "")
        if !explicit
            root := Credits.Root()
        try fp := Credits.Fingerprint(root)
        catch
            return {ok: false, why: "hash unavailable"}
        if fp = ""
            return {ok: false, why: "credits file or avatar missing"}
        if explicit {
            a := Credits.ReadStored(root "\lib\Brand.ahk")
            b := Credits.ReadStored(root "\lib\ui\Splash.ahk")
        } else {
            a := Brand._ck
            b := Splash._ck
        }
        try {
            if Credits.Decode(a) != fp
                return {ok: false, why: "fingerprint differs from the first stored value"}
            if Credits.Decode(b) != fp
                return {ok: false, why: "fingerprint differs from the second stored value"}
        } catch
            return {ok: false, why: "stored value unreadable"}
        return {ok: true, why: ""}
    }

    ; The numbers of the `static _ck := [...]` line in a source file; [] if absent.
    static ReadStored(path) {
        arr := []
        try txt := FileRead(path, "UTF-8")
        catch
            return arr
        if !RegExMatch(txt, "static _ck := \[([^\]]*)\]", &m)
            return arr
        Loop Parse, m[1], ","
        {
            n := Trim(A_LoopField)
            if n = ""
                continue
            if !IsInteger(n)
                return []
            arr.Push(Integer(n))
        }
        return arr
    }
}
