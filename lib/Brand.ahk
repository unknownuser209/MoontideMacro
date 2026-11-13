#Requires AutoHotkey v2.0
; User-visible product name. Internals (files, classes, data paths, Vesper.ahk)
; keep their original "Vesper" names on purpose; only text shown to the user
; (window titles, tray, webhook embeds, log lines) goes through Brand.Name.
class Brand {
    static Name := "Moontide Macro"
    static Version := "0.8"
    static DiscordUrl := "https://discord.gg/TPuxESDxe7"
    ; stored credits check value (see lib\Credits.ahk); one line, rewritten by tools\update_credits.ahk
    static _ck := [17, 115, 85, 180, 196, 244, 212, 156, 127, 12, 57, 26, 168, 129, 232, 206, 36, 84, 49, 66, 247, 134, 229, 222, 58, 76, 47, 89, 186, 152, 171, 131, 53, 68, 39, 87, 180, 153, 246, 238, 207, 121, 93, 61, 25, 161, 221, 230, 194, 116, 81, 54, 66, 247, 132, 251, 214, 57, 24, 127, 94, 236, 206, 243]
    ; "Moontide Macro v1.0": embed footer
    static Footer => Brand.Name " v" Brand.Version
}

; Emoji for Discord embeds, built from code points so the .ahk sources stay
; plain ASCII (no file-encoding surprises). VS = variation selector-16.
class Emoji {
    static VS := Chr(0xFE0F)
    static Moon := Chr(0x1F319)
    static Globe := Chr(0x1F30D)
    static Siren := Chr(0x1F6A8)
    static Stop := Chr(0x1F6D1)
    static Warn := Chr(0x26A0) Chr(0xFE0F)
    static Potion := Chr(0x1F9EA)
    static Cart := Chr(0x1F6D2)
    static Scroll := Chr(0x1F4DC)
    static Alembic := Chr(0x2697) Chr(0xFE0F)
    static Clapper := Chr(0x1F3AC)
    static Check := Chr(0x2705)
    static Cross := Chr(0x274C)
    static Fish := Chr(0x1F3A3)
    static Money := Chr(0x1F4B0)
    static Megaphone := Chr(0x1F4E3)
    static Repeat := Chr(0x1F501)
    static Compass := Chr(0x1F9ED)
    static Chat := Chr(0x1F4AC)
    static Shield := Chr(0x1F6E1) Chr(0xFE0F)
    static Clock := Chr(0x1F552)
    static Link := Chr(0x1F517)
    static Timer := Chr(0x23F1) Chr(0xFE0F)
    static Cycle := Chr(0x1F504)
}
