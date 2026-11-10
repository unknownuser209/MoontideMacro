#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; UiLogic: pure helpers behind the dashboard and overlay (no windows, no I/O).
;
;   UiLogic.MaskSecret(s)          "" | "••••" | "••••" + last 4 chars.
;                                  Values shorter than 12 chars reveal nothing.
;   UiLogic.NewSecret(old, typed)  blank typed -> old (unchanged), else typed.
;   UiLogic.Scrub(text, secrets)   one line; Discord webhook URLs -> [webhook],
;                                  roblox.com / ro.blox.com / roblox:// links
;                                  and privateServerLinkCode=... -> [link],
;                                  every non-empty exact secret -> [secret].
;   UiLogic.LogLine(text, secrets, now := A_Now)  "HH:mm:ss  " Scrub(text)
;   UiLogic.UnlockTitle(p) / UnlockText(p)   confirm dialog strings for a
;                                  potion Map {name, perBiome, perDay, perRun}.
;   UiLogic.RequestUnlock(p, confirmFn)  confirmFn(title, text) -> true/false.
;                                  Only true sets p["locked"] := 0.
;   UiLogic.ApplyUnlock(p, confirmed) / Relock(p)
;   UiLogic.Uptime(ms)             "H:MM:SS"
;   UiLogic.UInt(text, default)    non-negative Integer or default.
;   UiLogic.CsvToArray(s) / ArrayToCsv(arr)
;   UiLogic.NormState(s)           "running" -> "Running", "" -> "Stopped"
;   UiLogic.TitleCase(s)           first letter of each space-separated word
;                                  upper-cased, the rest kept ("gear b" -> "Gear B");
;                                  a Roman numeral or XL word is all upper case
;                                  ("fortune spoid ii" -> "Fortune Spoid II")
;   UiLogic.IsWebhookUrl(s)        https://(ptb.|canary.)discord(app).com/api/webhooks/...
;   UiLogic.Copy(v)                deep copy of Map/Array/scalar
;   UiLogic.KeyOf(e)               "id:<id>" if it has an id, else "name:<name>"
;   UiLogic.MergeByKey(live, work, fields)  copy fields into live items with
;                                  the same KeyOf, in place.
;
;   UiLogBuffer(cap := 200)        Push(line) Count() Text() Tail(n) Clear()
; ---------------------------------------------------------------------------

class UiLogic {
    static Dots := Chr(0x2022) Chr(0x2022) Chr(0x2022) Chr(0x2022)

    static MaskSecret(s) {
        s := Trim(String(s))
        if (s = "")
            return ""
        if (StrLen(s) < 12)
            return UiLogic.Dots
        return UiLogic.Dots SubStr(s, -4)
    }

    static NewSecret(old, typed) {
        typed := Trim(String(typed))
        return (typed = "") ? old : typed
    }

    static Scrub(text, secrets := "", keepLines := false) {
        s := keepLines ? String(text) : RegExReplace(String(text), "[\r\n]+", " ")   ; keepLines: Discord embeds keep line breaks
        s := RegExReplace(s, "i)(?:https?://)?(?:[\w-]+\.)*discord(?:app)?\.com/api/(?:v\d+/)?webhooks/\S*", "[webhook]")
        s := RegExReplace(s, "i)(?:https?://)?(?:[\w-]+\.)*roblox\.com/\S*", "[link]")
        s := RegExReplace(s, "i)(?:https?://)?ro\.blox\.com/\S*", "[link]")
        s := RegExReplace(s, "i)\broblox(?:-player)?:(?://|(?=\S))\S*", "[link]")
        s := RegExReplace(s, "i)(privateServerLinkCode|linkCode|share\?code)=\S*", "$1=[hidden]")
        if IsObject(secrets) {
            for sec in secrets {
                sec := Trim(String(sec))
                if (StrLen(sec) >= 4)
                    s := StrReplace(s, sec, "[secret]")
            }
        }
        return s
    }

    static LogLine(text, secrets := "", now := "") {
        if (now = "")
            now := A_Now
        return FormatTime(now, "HH:mm:ss") "  " UiLogic.Scrub(text, secrets)
    }

    ; ---- potion unlock ---------------------------------------------------------

    static _Cap(p, k) => p.Has(k) ? p[k] : "?"

    static UnlockTitle(p) => "Unlock " p["name"] "?"

    static UnlockText(p) {
        return p["name"] " is a locked top-tier potion.`n`n"
            . "If you unlock it, the macro may use it during rare biomes, up to:`n"
            . "    " UiLogic._Cap(p, "perBiome") " per rare biome`n"
            . "    " UiLogic._Cap(p, "perDay") " per day`n"
            . "    " UiLogic._Cap(p, "perRun") " per run`n`n"
            . "Every use still passes the safety checks. Dry run (if on) only logs."
    }

    static ApplyUnlock(p, confirmed) {
        if !confirmed
            return false
        p["locked"] := 0
        return true
    }

    static Relock(p) {
        p["locked"] := 1
    }

    static RequestUnlock(p, confirmFn) {
        if !(p.Has("locked") && p["locked"])
            return false
        ok := confirmFn.Call(UiLogic.UnlockTitle(p), UiLogic.UnlockText(p))
        return UiLogic.ApplyUnlock(p, ok = true)
    }

    ; ---- formatters ------------------------------------------------------------

    static Uptime(ms) {
        s := Max(0, Integer(ms // 1000))
        return (s // 3600) ":" Format("{:02}", Mod(s // 60, 60)) ":" Format("{:02}", Mod(s, 60))
    }

    static UInt(text, default) {
        t := Trim(String(text))
        return (t != "" && RegExMatch(t, "^\d{1,9}$")) ? Integer(t) : default
    }

    static CsvToArray(s) {
        out := []
        seen := Map()
        for part in StrSplit(String(s), ",") {
            n := Trim(part)
            if (n = "" || seen.Has(StrLower(n)))
                continue
            seen[StrLower(n)] := true
            out.Push(n)
        }
        return out
    }

    static ArrayToCsv(arr) {
        s := ""
        for v in arr
            s .= (s = "" ? "" : ",") v
        return s
    }

    ; First letter of each space-separated word upper-cased, the rest kept;
    ; roman numerals (II, III, XL ...) fully upper-cased.
    static TitleCase(s) {
        out := ""
        for i, w in StrSplit(String(s), " ") {
            if RegExMatch(w, "i)^(?:i{1,3}|iv|vi{0,3}|ix|x|xl)$")
                w := StrUpper(w)
            else
                w := StrUpper(SubStr(w, 1, 1)) SubStr(w, 2)
            out .= (i > 1 ? " " : "") w
        }
        return out
    }

    ; "running" -> "Running"; blank -> "Stopped".
    static NormState(s) {
        s := Trim(String(s))
        return (s = "") ? "Stopped" : StrUpper(SubStr(s, 1, 1)) StrLower(SubStr(s, 2))
    }

    static IsWebhookUrl(s) {
        return RegExMatch(Trim(String(s)), "i)^https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/(?:v\d+/)?webhooks/\S+$") ? true : false
    }

    ; ---- data helpers ------------------------------------------------------------

    ; Deep copy of Map / Array / scalar (Maps keep CaseSense).
    static Copy(v) {
        if (v is Map) {
            m := Map()
            m.CaseSense := v.CaseSense
            for k, x in v
                m[k] := UiLogic.Copy(x)
            return m
        }
        if (v is Array) {
            a := []
            for x in v
                a.Push(UiLogic.Copy(x))
            return a
        }
        return v
    }

    ; Identity of a data entry: "id:<id>" when it has a non-empty id, else
    ; "name:<name>" ("" when it has neither).
    static KeyOf(e) {
        if !(e is Map)
            return ""
        if (e.Has("id") && Trim(String(e["id"])) != "")
            return "id:" Trim(String(e["id"]))
        return e.Has("name") ? "name:" String(e["name"]) : ""
    }

    ; Copy `fields` from work items into the live items with the same KeyOf,
    ; in place (the live Map objects stay the same; other fields untouched).
    ; -> number of live items updated.
    static MergeByKey(liveArr, workArr, fields) {
        byKey := Map()
        for w in workArr {
            k := UiLogic.KeyOf(w)
            if (k != "")
                byKey[k] := w
        }
        n := 0
        for l in liveArr {
            k := UiLogic.KeyOf(l)
            if (k = "" || !byKey.Has(k))
                continue
            w := byKey[k]
            for f in fields {
                if w.Has(f)
                    l[f] := UiLogic.Copy(w[f])
            }
            n++
        }
        return n
    }
}

class UiLogBuffer {
    __New(cap := 200) {
        this._cap := Max(1, Integer(cap))
        this._lines := []
    }

    Push(line) {
        this._lines.Push(line)
        while (this._lines.Length > this._cap)
            this._lines.RemoveAt(1)
    }

    Count() => this._lines.Length

    Clear() {
        this._lines := []
    }

    Text() => this.Tail(this._lines.Length)

    Tail(n) {
        s := ""
        start := Max(1, this._lines.Length - n + 1)
        Loop this._lines.Length - start + 1
            s .= (A_Index = 1 ? "" : "`r`n") this._lines[start + A_Index - 1]
        return s
    }
}
