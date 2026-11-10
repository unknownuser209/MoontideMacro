#Requires AutoHotkey v2.0
; Tests for lib\ui\UiLogic.ahk (pure helpers behind the dashboard/overlay).
; No windows are created here. See test_ui_dash.ahk for the hidden-GUI
; round-trip test.
#Include ..\lib\ui\UiLogic.ahk

; ---- secret masking ----------------------------------------------------------

Test_Ui_MaskSecret_LastFourAtMost() {
    dot := Chr(0x2022)
    url := "https://discord.com/api/webhooks/123456789012345678/AbCdEfGhIjKlMnOpQrStUvWxYz_wxyz"
    m := UiLogic.MaskSecret(url)
    AssertEq(m, dot dot dot dot "wxyz", "mask long url")
    ; never contains any 5-char run of the secret
    leak := false
    Loop StrLen(url) - 4 {
        if InStr(m, SubStr(url, A_Index, 5), true)
            leak := true
    }
    AssertTrue(!leak, "mask reveals at most 4 chars")
    AssertEq(UiLogic.MaskSecret(""), "", "empty -> empty")
    AssertEq(UiLogic.MaskSecret("   "), "", "blank -> empty")
    ; short values reveal nothing at all
    AssertEq(UiLogic.MaskSecret("abcd"), dot dot dot dot, "4 chars -> dots only")
    AssertEq(UiLogic.MaskSecret("abcdefghijk"), dot dot dot dot, "11 chars -> dots only")
    AssertEq(UiLogic.MaskSecret("abcdefghijkl"), dot dot dot dot "ijkl", "12 chars -> last 4")
}

Test_Ui_SecretEdit_KeepsOldWhenBlank() {
    AssertEq(UiLogic.NewSecret("old-value", ""), "old-value", "blank keeps old")
    AssertEq(UiLogic.NewSecret("old-value", "   "), "old-value", "spaces keep old")
    AssertEq(UiLogic.NewSecret("old-value", " new "), "new", "typed replaces (trimmed)")
    AssertEq(UiLogic.NewSecret("", ""), "", "nothing stays nothing")
}

; ---- log scrub -----------------------------------------------------------------

Test_Ui_Scrub_RemovesWebhookUrls() {
    hook := "https://discord.com/api/webhooks/123456789012345678/AbCdEf-GhIj_KlMn"
    s := UiLogic.Scrub("send to " hook " failed")
    AssertTrue(!InStr(s, "webhooks/123"), "webhook path gone")
    AssertTrue(!InStr(s, "AbCdEf"), "token gone")
    AssertTrue(InStr(s, "send to ") = 1 && InStr(s, " failed"), "rest kept")
    for variant in ["http://discordapp.com/api/webhooks/1/xyzTOKEN"
            , "https://ptb.discord.com/api/v10/webhooks/1/xyzTOKEN"
            , "discord.com/api/webhooks/1/xyzTOKEN"
            , "HTTPS://CANARY.DISCORD.COM/API/WEBHOOKS/1/xyzTOKEN"] {
        AssertTrue(!InStr(UiLogic.Scrub("x " variant " y"), "xyzTOKEN"), "variant scrubbed: " A_Index)
    }
}

Test_Ui_Scrub_RemovesRobloxLinks() {
    for link in ["https://www.roblox.com/share?code=abc123SECRET&type=Server"
            , "https://www.roblox.com/games/15532962292/Sols-RNG?privateServerLinkCode=abc123SECRET"
            , "roblox.com/share?code=abc123SECRET"
            , "roblox://placeId=1&linkCode=abc123SECRET"
            , "https://ro.blox.com/Ebh5?af_dp=abc123SECRET"] {
        s := UiLogic.Scrub("joining " link " now")
        AssertTrue(!InStr(s, "abc123SECRET"), "roblox link scrubbed: " A_Index)
        AssertTrue(InStr(s, "joining ") = 1 && InStr(s, " now"), "rest kept: " A_Index)
    }
    s := UiLogic.Scrub("privateServerLinkCode=abc123SECRET")
    AssertTrue(!InStr(s, "abc123SECRET"), "bare link code scrubbed")
}

Test_Ui_Scrub_KnownSecretsAndNewlines() {
    s := UiLogic.Scrub("value=tiger7secret here`r`nnext", ["tiger7secret", ""])
    AssertTrue(!InStr(s, "tiger7secret"), "exact secret scrubbed")
    AssertTrue(!InStr(s, "`n") && !InStr(s, "`r"), "single line")
    AssertEq(UiLogic.Scrub("biome GLITCHED"), "biome GLITCHED", "plain text untouched")
}

; ---- log buffer ----------------------------------------------------------------

Test_Ui_LogBuffer_CapsAt200() {
    b := UiLogBuffer()
    Loop 250
        b.Push("line " A_Index)
    AssertEq(b.Count(), 200, "capped")
    lines := StrSplit(b.Text(), "`r`n")
    AssertEq(lines.Length, 200, "text has 200 lines")
    AssertEq(lines[1], "line 51", "oldest dropped")
    AssertEq(lines[200], "line 250", "newest last")
    t := b.Tail(3)
    AssertEq(t, "line 248`r`nline 249`r`nline 250", "tail")
    b.Clear()
    AssertEq(b.Count(), 0, "clear")
    AssertEq(b.Text(), "", "empty text")
    small := UiLogBuffer(2)
    small.Push("a"), small.Push("b"), small.Push("c")
    AssertEq(small.Text(), "b`r`nc", "custom cap")
}

Test_Ui_LogLine_ScrubsAndStamps() {
    line := UiLogic.LogLine("posted https://discord.com/api/webhooks/1/TOKENxyz ok", [], "20261024133705")
    AssertEq(SubStr(line, 1, 10), "13:37:05  ", "time stamp")
    AssertTrue(!InStr(line, "TOKENxyz"), "scrubbed")
}

; ---- unlock dialog logic ---------------------------------------------------------

UiTestPotion() {
    return Map("name", "Heavenly Potion", "locked", 1, "perBiome", 1, "perDay", 2, "perRun", 5)
}

Test_Ui_UnlockText_NamesPotionAndCaps() {
    p := UiTestPotion()
    t := UiLogic.UnlockText(p)
    AssertTrue(InStr(t, "Heavenly Potion"), "names potion")
    AssertTrue(RegExMatch(t, "1\D+per rare biome"), "per-biome cap")
    AssertTrue(RegExMatch(t, "2\D+per day"), "per-day cap")
    AssertTrue(RegExMatch(t, "5\D+per run"), "per-run cap")
    AssertEq(UiLogic.UnlockTitle(p), "Unlock Heavenly Potion?", "title")
}

Test_Ui_ApplyUnlock_CancelKeepsLocked() {
    p := UiTestPotion()
    AssertEq(UiLogic.ApplyUnlock(p, false), false, "cancel returns false")
    AssertEq(p["locked"], 1, "cancel leaves locked")
    AssertEq(UiLogic.ApplyUnlock(p, true), true, "confirm returns true")
    AssertEq(p["locked"], 0, "confirm unlocks")
    UiLogic.Relock(p)
    AssertEq(p["locked"], 1, "relock")
    ; the dialog runner: a confirm function that says no never unlocks
    p2 := UiTestPotion()
    asked := ""
    res := UiLogic.RequestUnlock(p2, (title, text) => (asked := title, false))
    AssertEq(res, false, "declined")
    AssertEq(p2["locked"], 1, "declined leaves locked")
    AssertEq(asked, "Unlock Heavenly Potion?", "dialog asked with potion title")
    res := UiLogic.RequestUnlock(p2, (title, text) => true)
    AssertEq(res, true, "accepted")
    AssertEq(p2["locked"], 0, "accepted unlocks")
    ; already unlocked: no dialog, no change
    called := false
    res := UiLogic.RequestUnlock(p2, (title, text) => (called := true, true))
    AssertEq(called, false, "no dialog when unlocked")
}

; ---- small formatters --------------------------------------------------------------

Test_Ui_Formatters() {
    AssertEq(UiLogic.Uptime(0), "0:00:00", "zero")
    AssertEq(UiLogic.Uptime(3723000), "1:02:03", "h:mm:ss")
    AssertEq(UiLogic.Uptime(100 * 3600000 + 59000), "100:00:59", "long run")
    AssertEq(UiLogic.Uptime(-5), "0:00:00", "negative clamps")
    AssertEq(UiLogic.UInt("12", 5), 12, "uint ok")
    AssertEq(UiLogic.UInt(" 7 ", 5), 7, "uint trims")
    AssertEq(UiLogic.UInt("-1", 5), 5, "negative -> default")
    AssertEq(UiLogic.UInt("abc", 5), 5, "junk -> default")
    AssertEq(UiLogic.UInt("", 5), 5, "blank -> default")
    arr := UiLogic.CsvToArray(" Lucky Potion, ,Speed Potion,lucky potion ")
    AssertEq(arr.Length, 2, "csv dedupe + blanks")
    AssertEq(arr[2], "Speed Potion", "csv order")
    AssertEq(UiLogic.ArrayToCsv(["a", "b"]), "a,b", "join")
}

; ---- data helpers ----------------------------------------------------------------

Test_Ui_CloneAndMergeByKey() {
    live := [Map("name", "Lucky Potion", "locked", 0, "perDay", 3), Map("name", "Warp Potion", "locked", 1, "perDay", 3)]
    keep := live[2]
    work := UiLogic.Copy(live)
    AssertTrue(work[2] !== keep, "clone is deep")
    work[2]["perDay"] := 9
    work[2]["locked"] := 0
    AssertEq(keep["perDay"], 3, "clone does not touch live")
    n := UiLogic.MergeByKey(live, work, ["perDay"])
    AssertEq(n, 2, "merged count")
    AssertTrue(live[2] == keep, "live Map identity kept")
    AssertEq(keep["perDay"], 9, "field merged")
    AssertEq(keep["locked"], 1, "unlisted field untouched")
}

Test_Ui_MergeByKey_IdBeatsDuplicateNames() {
    live := [Map("id", "godly_a", "name", "Godly Potion", "perDay", 1, "desc", "x")
        , Map("id", "godly_b", "name", "Godly Potion", "perDay", 1)
        , Map("name", "Lucky Potion", "perDay", 1)]
    work := UiLogic.Copy(live)
    work[2]["perDay"] := 7
    work[3]["perDay"] := 5
    AssertEq(UiLogic.MergeByKey(live, work, ["perDay"]), 3, "all matched")
    AssertEq(live[1]["perDay"], 1, "same name, other id untouched")
    AssertEq(live[2]["perDay"], 7, "matched by id")
    AssertEq(live[3]["perDay"], 5, "no id -> matched by name")
    AssertEq(live[1]["desc"], "x", "extra fields kept")
    AssertEq(UiLogic.KeyOf(live[1]), "id:godly_a", "key id")
    AssertEq(UiLogic.KeyOf(live[3]), "name:Lucky Potion", "key name")
}

Test_Ui_Scrub_LeavesPlainRobloxWords() {
    AssertEq(UiLogic.Scrub("Roblox: window lost"), "Roblox: window lost", "colon + space untouched")
    AssertEq(UiLogic.Scrub("Roblox window found"), "Roblox window found", "plain word untouched")
    AssertTrue(!InStr(UiLogic.Scrub("open roblox-player:1+launchmode:play+SECRETx"), "SECRETx"), "protocol link scrubbed")
}

Test_Ui_NormStateAndWebhookUrl() {
    AssertEq(UiLogic.NormState("running"), "Running", "running")
    AssertEq(UiLogic.NormState("PAUSED"), "Paused", "paused")
    AssertEq(UiLogic.NormState(""), "Stopped", "blank -> stopped")
    AssertTrue(UiLogic.IsWebhookUrl("https://discord.com/api/webhooks/1/abc"), "discord ok")
    AssertTrue(UiLogic.IsWebhookUrl("https://ptb.discordapp.com/api/webhooks/1/abc"), "ptb ok")
    AssertTrue(!UiLogic.IsWebhookUrl("http://discord.com/api/webhooks/1/abc"), "http refused")
    AssertTrue(!UiLogic.IsWebhookUrl("https://evil.example/api/webhooks/1/abc"), "other host refused")
}

Test_Ui_TitleCase() {
    AssertEq(UiLogic.TitleCase("gear b"), "Gear B", "gear b")
    AssertEq(UiLogic.TitleCase("mixed potion"), "Mixed Potion", "mixed potion")
    AssertEq(UiLogic.TitleCase("Fortune Spoid II"), "Fortune Spoid II", "already title case, rest kept")
    AssertEq(UiLogic.TitleCase(""), "", "empty")
    AssertEq(UiLogic.TitleCase("fortune spoid ii"), "Fortune Spoid II", "roman ii")
    AssertEq(UiLogic.TitleCase("haste potion iii"), "Haste Potion III", "roman iii")
    AssertEq(UiLogic.TitleCase("speed potion xl"), "Speed Potion XL", "size XL")
    AssertEq(UiLogic.TitleCase("mix"), "Mix", "a word that only starts like a numeral")
}
