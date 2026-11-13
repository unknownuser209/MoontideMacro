#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
; ---------------------------------------------------------------------------
; I18n: translations of the dashboard, the setup wizard and the overlay.
;
;   I18n.Use(lang)   "en" (default), "es" Spanish, "pt" Brazilian Portuguese,
;                    "fil" Filipino, "fr" French, "de" German (any case; an
;                    unknown code, a missing or broken file -> English).
;                    Call before any window is built (App.Boot, next to
;                    Theme.Use): texts are translated when controls are made.
;                    -> the code used.
;   I18n.T(text)     the translation of an English UI string, or text itself
;                    when there is none (always text itself in English). An
;                    ALL CAPS text is also found through its normal-case key
;                    ("STATUS" -> the translation of "Status", in capitals).
;   I18n.F(text, args*)  Format(I18n.T(text), args*): "Step {1} of {2}".
;   I18n.Codes / I18n.Names   the languages in Settings > Look order.
;
; Dictionaries: lang\<code>.json (program files, shipped and replaced by the
; updater like lib\), each a flat JSON object {"English text": "translation"}
; in UTF-8. Empty or non-text values are ignored. Game terms (Sol's RNG,
; Eden, Mari, Jester, biome and aura names) are left in English.
;
; Hooked in centrally: Theme.Window / Label / Panel / Help / Button / Check /
; Segmented / ListHeader / Confirm translate what they are given, so most
; call sites need nothing. Dropdown items are data (theme, potion names) and
; are never translated. Texts set later with Theme.SetText stay English
; unless the caller wraps them in I18n.T (the most visible ones do).
; ---------------------------------------------------------------------------

class I18n {
    static Codes := ["en", "es", "pt", "fil", "fr", "de"]
    static Names := ["English", "Español", "Português (BR)", "Filipino", "Français", "Deutsch"]
    static Lang := "en"
    static Raw := false        ; true while building controls that must stay English (tiny column codes)
    static Folder := RegExReplace(A_LineFile, "\\lib\\[^\\]+$", "") "\lang"
    static _dict := Map()
    static _caps := Map()

    ; Code as listed for `lang` (a code or a listed name, any case), "en" when unknown.
    static CodeOf(lang) {
        l := Trim(String(lang))
        for i, c in I18n.Codes
            if (c = l || I18n.Names[i] = l)
                return c
        return "en"
    }

    ; Index of `lang` in I18n.Codes (1 = English when unknown).
    static IndexOf(lang) {
        c := I18n.CodeOf(lang)
        for i, k in I18n.Codes
            if (k = c)
                return i
        return 1
    }

    ; Path of the dictionary file of `code`.
    static PathOf(code) => I18n.Folder "\" code ".json"

    ; The parsed dictionary of `code` (throws when missing or not a JSON object).
    static LoadFile(code) {
        m := Json.Parse(FileRead(I18n.PathOf(code), "UTF-8"))
        if !(m is Map)
            throw ValueError("I18n: " code ".json is not a JSON object")
        return m
    }

    static Use(lang) {
        code := I18n.CodeOf(lang)
        dict := Map(), caps := Map()
        if (code != "en") {
            try {
                for k, v in I18n.LoadFile(code) {
                    if !(k is String && v is String) || Trim(v) = "" || k = ""
                        continue
                    dict[k] := v
                    ku := StrUpper(k)
                    if (ku !== k && !caps.Has(ku))
                        caps[ku] := StrUpper(v)
                }
            } catch {
                dict := Map(), caps := Map()
            }
            if !dict.Count
                code := "en"
        }
        I18n._dict := dict
        I18n._caps := caps
        I18n.Lang := code
        return code
    }

    static T(text) {
        if (I18n.Raw || !I18n._dict.Count)
            return text
        s := String(text)
        if I18n._dict.Has(s)
            return I18n._dict[s]
        if I18n._caps.Has(s)
            return I18n._caps[s]
        return text
    }

    static F(text, args*) => Format(I18n.T(text), args*)

    ; Number of translations in use (0 in English).
    static Count => I18n._dict.Count
}
