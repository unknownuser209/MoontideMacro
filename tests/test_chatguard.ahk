#Requires AutoHotkey v2.0
#Include ..\lib\Screen.ahk
#Include ..\lib\Input.ahk
#Include ..\lib\ChatGuard.ahk
#Include ..\lib\MatchVision.ahk
; ---------------------------------------------------------------------------
; ChatGuard: Roblox's chat (fixed pixel size at every resolution) hidden
; right before a click it covers below 1440p, shown again after the task.
; The chat button's state is read on REAL frames (tests\screens: open =
; filled bubble, closed = outline). Fakes: RsChatIO (test_reset_checks),
; AppTestMake / TdTask (test_app / test_tidy). Every test puts Screen back
; to identity and forgets ChatGuard's state.
; ---------------------------------------------------------------------------

; The chat button's pixels from a real 2560x1440 frame (client px).
CgIcon(file, x, y, w, h) {
    static grabs := Map()
    if !grabs.Has(file)
        grabs[file] := MatchFileGrab(A_ScriptDir "\screens\" file)
    ys := []
    Loop h
        ys.Push(y + A_Index - 1)
    out := []
    for row in grabs[file].Call(x, x + w - 1, ys)
        for c in row
            out.Push(c)
    return out
}

; RsChatIO with Roblox's chat: GrabScreen shows the button from a real frame
; (open: world_day, closed: mm_end, with its unread badge); a click on the
; button (fixed client px, any mapping) toggles it.
class CgIO extends RsChatIO {
    __New(chatOpen := true) {
        super.__New()
        this.chatOpen := chatOpen
        this.toggles := 0
        this.toggleDead := false     ; clicks on the button do nothing
        this.grabs := 0
        this.openFile := "world_day.jpg"
        this.closedFile := "mm_end.jpg"
    }
    GrabScreen(sx, sy, w, h) {
        this.grabs++
        return CgIcon(this.chatOpen ? this.openFile : this.closedFile, sx - Screen.cx, sy - Screen.cy, w, h)
    }
    ClickHere() {
        p := Screen.Pt(this.x, this.y)
        t := ChatGuard.Toggle
        if (Abs(p.x - Screen.cx - t[1]) <= 3 && Abs(p.y - Screen.cy - t[2]) <= 3) {
            this.log.Push("chat-toggle")
            this.toggles++
            if !this.toggleDead
                this.chatOpen := !this.chatOpen
            return
        }
        super.ClickHere()
    }
}

; fn() with the client at x, y, w, h and a fresh ChatGuard; identity after.
CgAt(x, y, w, h, fn) {
    ChatGuard.Reset()
    Screen.SetClient(x, y, w, h)
    try
        return fn()
    finally {
        Screen.Reset()
        ChatGuard.Reset()
    }
}

CgIdx(log, entry) {
    for i, e in log
        if (e = entry)
            return i
    return 0
}

Test_ChatGuard_CoversAtEachSize() {
    close := Input.ResetCoords["menuClose"], open := Input.ResetCoords["menuOpen"]
    CgAt(0, 0, 2560, 1440, () => (
        AssertTrue(!ChatGuard.Covers(close), "1440p: Collections close (525,158) is right of the chat (x 8..483)"),
        AssertTrue(!ChatGuard.Covers(open), "1440p: its open button is below it"),
        AssertTrue(!ChatGuard.Covers({x: 35, y: 534}), "1440p: the Aura Storage button is below it"),
        AssertTrue(ChatGuard.Covers(100, 100), "1440p: a point inside it"),
        AssertTrue(!ChatGuard.Covers(484, 100) && !ChatGuard.Covers(100, 421) && !ChatGuard.Covers(100, 63), "1440p: just outside its edges")
    ))
    CgAt(0, 0, 1920, 1080, () => (
        AssertTrue(ChatGuard.Covers(close), "1080p: Collections close -> 394,119, under the chat"),
        AssertTrue(ChatGuard.Covers(close[1], close[2]), "1080p: as x, y"),
        AssertTrue(!ChatGuard.Covers(open), "1080p: its open button -> 39,466, below the chat"),
        AssertTrue(ChatGuard.Covers({x: 35, y: 534}), "1080p: the Aura Storage button -> 26,400, under it"),
        AssertTrue(!ChatGuard.Covers({x: 840, y: 843}), "1080p: the Equip button is clear"),
        AssertTrue(ChatGuard.Covers({x: 600, y: 500, w: 100, h: 80}), "1080p: a rect reaching into it (450..525 x 375..435)"),
        AssertTrue(!ChatGuard.Covers({x: 700, y: 500, w: 100, h: 80}), "1080p: a rect right of it")
    ))
    CgAt(0, 0, 1366, 768, () => (
        AssertTrue(ChatGuard.Covers(close), "768p: Collections close under the chat"),
        AssertTrue(ChatGuard.Covers(open), "768p: even its open button (28,331)")
    ))
    ; a windowed client: fixed px from the client origin, not the screen's
    CgAt(300, 200, 1920, 1080, () => (
        AssertTrue(ChatGuard.Covers(close), "windowed 1080p: close under the chat"),
        AssertTrue(!ChatGuard.Covers({x: 35, y: 600}), "windowed 1080p: below it (client y 450)")
    ))
}

; the button read on real frames (all 2560x1440; the button has the same
; pixels at every size)
Test_ChatGuard_RealFramesButtonState() {
    rd := (f) => ChatGuard.State({GrabScreen: (self, x, y, w, h) => CgIcon(f, x, y, w, h)})
    for f in ["world_day.jpg", "collections_chat_052142.jpg", "aura_selected_dutchman.jpg", "death_red_snowy_clip.jpg"
        , "inventory_open_day.jpg", "mari_day_buttons.jpg", "jester_shop.jpg"]
        AssertEq(rd(f), 1, f ": open (filled bubble)")
    for f in ["mm_end.jpg", "mm_board_start.jpg", "aura_search_sailor.jpg", "nodeath_graveyard_prompt.jpg", "mari_night_buttons.jpg"]
        AssertEq(rd(f), 0, f ": closed (outline bubble, the badge or not)")
    AssertEq(rd("title_play_windy.jpg"), -1, "the title screen: no chat button there (its mic is): unknown")
    AssertEq(ChatGuard.State(RsChatIO()), -1, "an io without GrabScreen: unknown")
    AssertEq(ChatGuard.IsOpen(CgIO(true)), true, "IsOpen")
}

; the brief's case: below 1440p the Collections close is under the chat
Test_ChatGuard_ReAimHidesThenRestores() {
    for sz in [[0, 0, 1920, 1080], [0, 0, 1366, 768], [300, 200, 1920, 1080]] {
        name := sz[3] "x" sz[4] " at " sz[1] "," sz[2]
        CgAt(sz[1], sz[2], sz[3], sz[4], () => (
            io := CgIO(true),
            AssertEq(Input.ReAim(SchedCtx(), io), true, name ": re-aimed"),
            iT := CgIdx(io.log, "chat-toggle"),
            iC := CgIdx(io.log, "click@525,158"),
            AssertTrue(iT > 0 && iC > iT, name ": the chat button clicked before the close"),
            AssertEq(io.toggles, 1, name ": once"),
            AssertEq(io.chatOpen, false, name ": hidden"),
            AssertEq(ChatGuard.Hidden(), true, name ": remembered"),
            AssertEq(io.collUp, false, name ": Collections closed"),
            AssertEq(ChatGuard.Restore(SchedCtx()), 1, name ": restored"),
            AssertEq(io.toggles, 2, name ": clicked again after"),
            AssertEq(io.chatOpen, true, name ": the chat is back"),
            AssertEq(ChatGuard.Hidden(), false, name ": nothing left to restore"),
            AssertEq(ChatGuard.Restore(SchedCtx()), 0, name ": a second restore does nothing"),
            AssertEq(io.toggles, 2, name ": no third click")
        ))
    }
}

; 2560x1440: nothing extra at all, the same io calls as an io with no chat
Test_ChatGuard_IdentityUnchanged() {
    CgAt(0, 0, 2560, 1440, () => (
        io := CgIO(true),
        plain := RsChatIO(),
        AssertEq(Input.ReAim(SchedCtx(), io), true, "re-aimed"),
        AssertEq(Input.ReAim(SchedCtx(), plain), true, "re-aimed (no chat)"),
        AssertEq(io.grabs, 0, "the button never read"),
        AssertEq(io.toggles, 0, "never clicked"),
        AssertEq(AssertShow(io.log), AssertShow(plain.log), "the same calls, in order"),
        Input.Click(35, 534, io),
        AssertEq(io.grabs, 0, "a click on the storage button: nothing read"),
        AssertEq(ChatGuard.Hidden(), false, "nothing hidden")
    ))
}

Test_ChatGuard_AlreadyClosedNoToggle() {
    CgAt(0, 0, 1920, 1080, () => (
        io := CgIO(false),
        AssertEq(Input.ReAim(SchedCtx(), io), true, "re-aimed"),
        AssertTrue(io.grabs > 0, "the button was read"),
        AssertEq(io.toggles, 0, "closed already: not clicked"),
        AssertEq(ChatGuard.Hidden(), false, "not ours to restore"),
        AssertEq(ChatGuard.Restore(SchedCtx(), io), 0, "restore: nothing"),
        AssertEq(io.toggles, 0, "still not clicked"),
        AssertEq(io.chatOpen, false, "the player's closed chat stays closed")
    ))
}

Test_ChatGuard_RestoreOnlyWhatWeHid() {
    CgAt(0, 0, 1920, 1080, () => (
        ; hidden by us, then the player opened it himself: no click
        io := CgIO(true),
        AssertEq(ChatGuard.Hide(io, SchedCtx()), 1, "hidden"),
        io.chatOpen := true,
        AssertEq(ChatGuard.Restore(SchedCtx()), 0, "open already: nothing"),
        AssertEq(io.toggles, 1, "no click on it"),
        ; the button does nothing: two tries, then reported; restore has nothing to undo
        io2 := CgIO(true),
        io2.toggleDead := true,
        AssertEq(ChatGuard.Hide(io2, SchedCtx()), 2, "still open"),
        AssertEq(io2.toggles, ChatGuard.Tries, "tried " ChatGuard.Tries " times"),
        AssertEq(ChatGuard.Restore(SchedCtx()), 0, "open: nothing to restore"),
        AssertEq(io2.toggles, ChatGuard.Tries, "no click"),
        ; nothing readable there (title screen): never clicked
        io3 := CgIO(true),
        io3.openFile := "title_play_windy.jpg",
        AssertEq(ChatGuard.Hide(io3, SchedCtx()), 0, "unknown: nothing done"),
        AssertEq(io3.toggles, 0, "not clicked")
    ))
}

; env.Click / Input.Click under the chat (the Aura Storage button at 1080p)
Test_ChatGuard_ClickUnderTheChat() {
    CgAt(0, 0, 1920, 1080, () => (
        io := CgIO(true),
        Input.Click(35, 534, io),
        iT := CgIdx(io.log, "chat-toggle"),
        iC := CgIdx(io.log, "click@35,534"),
        AssertTrue(iT > 0 && iC > iT, "the chat hidden before the click"),
        Input.Click(1146, 490, io),
        AssertEq(io.toggles, 1, "a clear click: nothing more"),
        Input.Click(45, 520, io),
        AssertEq(io.toggles, 1, "hidden already: not clicked again")
    ))
}

; the App's after-task tidy shows it again (ChatWatch needs it)
Test_App_TidyShowsTheChatAgain() {
    ChatGuard.Reset()
    io := CgIO(true)
    q := TdTask("quests", 5, true, (self, ctx) => Input.ReAim(ctx, io))
    t := AppTestMake(Map("tasks", Map("quests", q)))
    t.app.Start()
    Screen.SetClient(0, 0, 1920, 1080)
    try {
        t.app._RunTask(q)
        AssertEq(io.toggles, 2, "hidden for the close, shown after the task")
        AssertEq(io.chatOpen, true, "open for ChatWatch")
        AssertEq(ChatGuard.Hidden(), false, "nothing left hidden")
        iE := TdLogIdx(t.ui.logs, "task: quests end")
        iShown := TdLogIdx(t.ui.logs, "chat: shown again")
        AssertTrue(iE > 0 && iShown > iE, "shown again after the end line")
        ; Roblox not in front: the tidy sends nothing, the next chat read's turn does
        t.rb.activeOk := false
        t.app._RunTask(q)
        AssertEq(io.chatOpen, false, "hidden, the tidy skipped")
        AssertEq(ChatGuard.Hidden(), true, "remembered")
        t.rb.activeOk := true
        t.app.chat := {reads: 0, open: "", Check: (self) => (self.reads++, self.open := io.chatOpen, [])}
        t.app._CheckChat()
        AssertEq(t.app.chat.reads, 1, "the chat read")
        AssertEq(t.app.chat.open, true, "shown again before it")
    } finally {
        Screen.Reset()
        ChatGuard.Reset()
    }
}

; a run stopped (F3) or closed while the chat was hidden left it hidden for
; good: the next run did not know (live 2026-11-11). The flag file carries it.
Test_ChatGuard_HiddenChatSurvivesARestart() {
    f := A_Temp "\vesper_chatflag_" A_TickCount ".flag"
    old := ChatGuard.FlagPath
    ChatGuard.FlagPath := f
    try CgAt(0, 0, 1920, 1080, () => (
        io := CgIO(true),
        AssertEq(ChatGuard.Hide(io, SchedCtx()), 1, "hidden"),
        AssertTrue(FileExist(f), "flag written"),
        ; a new run: nothing in memory, the chat still closed
        ChatGuard._hidden := false, ChatGuard._io := "",
        AssertEq(ChatGuard.Restore(SchedCtx(), io), 1, "the next run opens it again"),
        AssertEq(io.chatOpen, true, "open"),
        AssertTrue(!FileExist(f), "flag gone"),
        ; no flag, chat closed by the player: left alone
        io2 := CgIO(false),
        AssertEq(ChatGuard.Restore(SchedCtx(), io2), 0, "not ours"),
        AssertEq(io2.toggles, 0, "not clicked")
    ))
    finally {
        ChatGuard.FlagPath := old
        try FileDelete(f)
    }
}
