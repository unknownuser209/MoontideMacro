#Requires AutoHotkey v2.0
; Run after changing lib\Credits.ahk or assets\credits\avatar.png on purpose:
; recomputes the credits fingerprint and rewrites the `static _ck := [...]`
; line (one line each) in lib\Brand.ahk and lib\ui\Splash.ahk.
;   AutoHotkey64.exe tools\update_credits.ahk
#Include %A_LineFile%\..\..\lib\Credits.ahk

; Writes the encoded fingerprint of root into both stored-value lines.
UpdateCredits(root) {
    fp := Credits.Fingerprint(root)
    if fp = ""
        throw Error("lib\Credits.ahk or assets\credits\avatar.png is missing under " root)
    line := "static _ck := [" JoinCodes(Credits.Encode(fp)) "]"
    for rel in ["\lib\Brand.ahk", "\lib\ui\Splash.ahk"] {
        path := root rel
        txt := FileRead(path, "UTF-8")
        if !RegExMatch(txt, "static _ck := \[[^\]]*\]")
            throw Error("no stored value line in " path)
        txt := RegExReplace(txt, "static _ck := \[[^\]]*\]", line, , 1)
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(txt)
        f.Close()
    }
}

JoinCodes(arr) {
    s := ""
    for n in arr
        s .= (A_Index > 1 ? ", " : "") n
    return s
}

; Only when this file is the script that was run (not when a test includes it).
if (A_LineFile = A_ScriptFullPath) {
    UpdateCredits(Credits.Root())
    MsgBox("Credits check values updated.", "update_credits", "T3")
    ExitApp
}
