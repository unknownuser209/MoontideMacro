#Requires AutoHotkey v2.0
; Screen-checked ResetToSpawn (respawn prompt, Aura Collections camera
; re-aim) and the sell run's Captain Flarg check + re-walk.

; FsIO with a scripted screen read through Ocr(). Each fail count is how many
; attempts at that step do nothing on screen before it starts working.
class RsIO extends FsIO {
    __New(promptFail := 0, openFail := 0, closeFail := 0, stopAtWait := 0) {
        super.__New(stopAtWait)
        this.promptFail := promptFail
        this.openFail := openFail
        this.closeFail := closeFail
        this.rTries := 0
        this.opens := 0
        this.closes := 0
        this.promptUp := false
        this.collUp := false
        this.fisher := (io) => ""
        this.ocrCalls := 0
        this.shopFail := false      ; the shop never opens
        this.popupFail := false     ; Sell All never shows the confirm popup
        this.confirmLost := 0       ; Sell presses on the popup that do nothing
        this.confirms := 0
        this.shopUp := false
        this.popupUp := false
        this.popupText := "Sell Confirm / Do you really want to sell all of / your Emberfin?"
        this.popupText2 := ""       ; the popup read at scale 2 ("" = as at 1x)
        this.menuUp := false       ; the Roblox menu (Esc toggles it)
        this.menuTrack := false     ; model the menu toggling
    }
    Down(k) {
        super.Down(k)
        if (this.menuTrack && k = "Esc")
            this.menuUp := !this.menuUp
        if (k = "r") {
            this.rTries++
            this.promptUp := this.rTries > this.promptFail
        } else if (k = "Enter") {
            this.promptUp := false
        }
    }
    ClickHere() {
        super.ClickHere()
        if (this.x = 52 && this.y = 621) {
            this.opens++
            if (this.opens > this.openFail)
                this.collUp := true
        } else if (this.x = 525 && this.y = 158) {
            this.closes++
            if (this.closes > this.closeFail)
                this.collUp := false
        } else if (this.x = 1289 && this.y = 1264) {
            this.shopUp := !this.shopFail
        } else if ((this.x = 904 && this.y = 1080) || (this.x = 700 && this.y = 1078)) {
            this.popupUp := this.shopUp && !this.popupFail
        } else if (this.x = 1002 && this.y = 831) {
            this.confirms++
            if (this.confirms > this.confirmLost)
                this.popupUp := false
        } else if (this.x = 1492 && this.y = 830) {
            this.popupUp := false                       ; the popup's Cancel
        } else if (this.x = 1958 && this.y = 361) {
            this.shopUp := false
        }
    }
    Ocr(x, y, w, h, scale := 1) {
        this.ocrCalls++
        if (x = 900)
            return this.promptUp ? "Are you sure you want to respawn your character?" : ""
        if (x = 60)
            return this.collUp ? ":raft better [Exit]" : "Mari has arrived on the island..."
        if (x = 960)
            return this.fisher.Call(this)
        if (x = 570)
            return this.shopUp ? "Fishing Shop" : ""
        if (x = 970)
            return this.popupUp ? ((scale = 2 && this.popupText2 != "") ? this.popupText2 : this.popupText) : ""
        if (x = 1342)                                   ; the popup's Cancel button (game font)
            return this.popupUp ? "Concel" : ""
        if (x = 400)
            return this.menuUp ? "Players  Settings  Leave  Reset Character  Resume" : ""
        return ""
    }
}

; RsIO with shift lock (live 2026-11-03 18:28). lock: on. modal: a game page
; over the screen frees the cursor, so the probe reads off and clicks land;
; Collections takes its place. Without it a click with the lock on goes to
; the screen centre (pinned) and does nothing. works = false: Left Shift
; does nothing.
class RsLockIO extends RsIO {
    lock := true
    modal := false
    works := true
    pinned := 0
    taps := 0
    pos := {x: 0, y: 0}
    MouseAt(x, y) {
        this.pos := {x: x, y: y}
    }
    MousePos() => (this.lock && !this.modal) ? {x: 1280, y: 720} : this.pos
    KeyEvent(keys) {
        if (keys = "{sc02A up}" && this.works) {
            this.taps++
            this.lock := !this.lock
        }
    }
    ClickHere() {
        if (this.lock && !this.modal) {
            this.pinned++
            return
        }
        super.ClickHere()
        if this.collUp
            this.modal := false
    }
}

; what Input logged while fn ran
RsGuardLogs(fn) {
    logs := "", old := Input.LogFn
    Input.LogFn := (m) => (logs .= m "`n")
    try fn()
    finally Input.LogFn := old
    return logs
}

; the page hid the lock from the hunt's off check; the open click landed,
; Collections pinned the cursor: the close click must find that
Test_Reset_LockHiddenByAGamePageIsFoundBeforeTheCloseClick() {
    io := RsLockIO()
    io.modal := true
    AssertEq(Input.ShiftLockOn(io), 0, "the page frees the cursor: reads off with the lock on")
    r := ""
    logs := RsGuardLogs(() => r := Input.ResetToSpawn(SchedCtx(), io))
    AssertEq(r, true, "respawned, Collections closed")
    AssertEq(io.collUp, false, "not left open")
    AssertEq(io.pinned, 0, "no click at the centre")
    AssertEq(io.Count("click@525,158"), 1, "one close click, it landed")
    AssertEq(io.taps, 1, "one tap")
    AssertTrue(!io.lock, "off")
    AssertTrue(InStr(logs, "shift lock was on before the menuClose click - turned it off"), "logged: " logs)
}

Test_Reset_PinnedCursorSpendsNoCloseTry() {
    io := RsLockIO(0, 0, Input.ResetTries - 1)
    io.collUp := true
    AssertEq(Input.CloseCollections(SchedCtx(), io), 1, "every try was a real click")
    AssertEq(io.pinned, 0, "none at the centre")
    AssertEq(io.Count("click@525,158"), Input.ResetTries, "ResetTries real clicks")
}

Test_Reset_ShiftLockStuckOnRefusesTheClick() {
    io := RsLockIO()
    io.works := false, io.collUp := true
    r := ""
    logs := RsGuardLogs(() => r := Input.CloseCollections(SchedCtx(), io))
    AssertEq(r, 2, "still up")
    AssertEq(io.pinned + io.Count("click@525,158"), 0, "no click")
    AssertTrue(InStr(logs, "would not turn off before the menuClose click - not clicked"), "reported: " logs)
    for blind in [false, true] {
        io := RsLockIO()
        io.works := false
        AssertEq(Input.ReAim(SchedCtx(), io, blind), false, "refused")
        AssertEq(io.pinned + io.Count("click@52,621"), 0, "no click")
        AssertTrue(InStr(Input.LastResetError, "shift lock"), "the error says why: " Input.LastResetError)
    }
}

Test_Reset_GuardLeavesAFreeCursorAlone() {
    io := RsLockIO()
    io.lock := false
    logs := RsGuardLogs(() => Input.ReAim(SchedCtx(), io))
    AssertEq(io.taps, 0, "no tap")
    AssertEq(logs, "", "nothing to log")
    AssertEq(io.Count("click@52,621") " " io.Count("click@525,158"), "1 1", "both clicks")
    ctx := SchedCtx()
    ctx.Stop()
    io := RsLockIO()
    AssertEq(Input._ClickPoint(io, ctx, "menuClose"), -1, "stopped")
    AssertEq(io.pinned + io.Count("click@525,158"), 0, "no click")
}

Test_Reset_OpenMenuIsNotToggledShut() {
    ; the first Esc + R fails (reset cooldown) and leaves the menu open: the
    ; retry sees the menu and presses only R, so it does not close it again
    io := RsIO(1)
    io.menuTrack := true
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), true, "second try works")
    AssertEq(io.Count("down Esc"), 1, "Esc once: the menu was already open on the retry")
    AssertEq(io.Count("down r"), 2, "R twice")
}

Test_Reset_GivingUpClosesTheMenu() {
    io := RsIO(99)
    io.menuTrack := true
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), false, "gives up")
    AssertEq(io.menuUp, false, "the Roblox menu is not left open")
    AssertEq(io.Count("down Esc"), 2, "Esc to open it, Esc to close it when giving up")
}

Test_Reset_ChecksHappyPath() {
    io := RsIO()
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), true, "reset ok")
    AssertEq(Input.LastResetError, "", "no error")
    AssertEq(io.Count("down Esc"), 1, "one Esc")
    AssertEq(io.Count("down Enter"), 1, "one Enter")
    AssertEq(io.Count("click@52,621"), 1, "Collections opened once")
    AssertEq(io.Count("click@525,158"), 1, "Collections closed once")
    AssertTrue(io.IndexOf("down Enter") < io.IndexOf("click@52,621"), "Enter before the camera clicks")
    AssertEq(io.collUp, false, "Collections left closed")
}

Test_Reset_PromptRetried() {
    io := RsIO(1)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), true, "second Esc + R works")
    AssertEq(io.Count("down Esc"), 2, "Esc twice")
    AssertEq(io.Count("down r"), 2, "R twice")
    AssertEq(io.Count("down Enter"), 1, "Enter only once the prompt is up")
}

Test_Reset_PromptNeverShows() {
    io := RsIO(99)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), false, "gives up")
    AssertEq(io.Count("down Esc"), Input.ResetTries, "Esc + R tried ResetTries times")
    AssertEq(io.Count("down Enter"), 0, "never confirms blind")
    AssertEq(io.Count("click@52,621"), 0, "no camera clicks")
    AssertTrue(InStr(Input.LastResetError, "respawn prompt"), "error names the prompt")
}

Test_Reset_CollectionClickRetried() {
    io := RsIO(0, 1)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), true, "second open click works")
    AssertEq(io.Count("click@52,621"), 2, "open clicked twice")
    AssertEq(io.Count("click@525,158"), 1, "closed once")
}

Test_Reset_CollectionNeverOpens() {
    io := RsIO(0, 99)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), false, "gives up")
    AssertEq(io.Count("click@52,621"), Input.ResetTries, "open tried ResetTries times")
    AssertEq(io.Count("click@525,158"), 0, "no close click")
    AssertTrue(InStr(Input.LastResetError, "did not open"), "error names Collections")
}

Test_Reset_CollectionCloseRetried() {
    io := RsIO(0, 0, 1)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), true, "second close click works")
    AssertEq(io.Count("click@525,158"), 2, "close clicked twice")
    io2 := RsIO(0, 0, 99)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io2), false, "never closes -> false")
    AssertTrue(InStr(Input.LastResetError, "did not close"), "error names the close")
}

Test_Reset_CloseCollectionsLeftOpen() {
    io := RsIO()
    AssertEq(Input.CloseCollections(SchedCtx(), io), 0, "not open -> 0")
    AssertEq(io.Count("click@525,158"), 0, "no click")
    io.collUp := true
    AssertEq(Input.CloseCollections(SchedCtx(), io), 1, "open -> closed")
    AssertEq(io.Count("click@525,158"), 1, "ResetToSpawn's close click")
    AssertTrue(!io.collUp, "screen gone")
    io2 := RsIO(0, 0, 99)
    io2.collUp := true
    AssertEq(Input.CloseCollections(SchedCtx(), io2), 2, "never closes -> 2")
    AssertEq(io2.Count("click@525,158"), Input.ResetTries, "close tried ResetTries times")
    ; read through a task's OCR function (the task io has no Ocr)
    io3 := RsIO()
    io3.collUp := true
    AssertEq(Input.CloseCollections(SchedCtx(), io3, (x, y, w, h, scale := 1) => io3.Ocr(x, y, w, h)), 1, "ocr fn -> closed")
}

Test_Reset_StopDuringCheckIsNotAnError() {
    io := RsIO(99, 0, 0, 4)      ; stops on the 4th wait (inside the prompt poll)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), false, "stopped")
    AssertEq(Input.LastResetError, "", "stop is not a check failure")
    AssertEq(io.Count("down Enter"), 0, "no Enter after stop")
}

RsFisherAfterWalks(n) => (io) => io.Count("up e") >= n ? "Captain Florg / Avvvvvv... / Click to skip." : ""

Test_Sell_RewalksWhenFisherMissing() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsFisherAfterWalks(2 + SellTask.Nudges)    ; walk 1 + its nudges miss
        FsSellScreen(io, 1)
        logs := []
        task := SellTask(t.cfg, st, FsDeps(io, "", true, logs))
        task.Run(SchedCtx())
        AssertEq(io.Count("down Esc"), 2, "reset twice: first walk and its nudges missed")
        AssertEq(io.Count("up e"), 2 + SellTask.Nudges, "E: walk 1, its nudges, walk 2")
        AssertEq(io.Count("click@1308,1073"), 2, "shop dialog once")
        AssertEq(st.needRepath, false, "sell finished")
        AssertTrue(FsHasLog(logs, "sell: Captain Flarg's dialog did not open, the walk missed the shop (read: '')"), "miss logged")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_NudgeReachesFisher() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsFisherAfterWalks(2)                  ; the first hop gets there
        FsSellScreen(io, 1)
        logs := []
        task := SellTask(t.cfg, st, FsDeps(io, "", true, logs))
        task.Run(SchedCtx())
        AssertEq(io.Count("down Esc"), 1, "no re-walk")
        AssertEq(io.Count("up e"), 2, "route E + one hop E")
        AssertTrue(FsHasLog(logs, "sell: not at the fisher yet - hopping forward (1/" SellTask.Nudges ")"), "hop logged")
        AssertEq(io.Count("click@1308,1073"), 2, "shop dialog")
        AssertEq(st.needRepath, false, "sold")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_LastWalkTriesTheShopAnyway() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        FsSellScreen(io, 1)
        logs := []
        task := SellTask(t.cfg, st, FsDeps(io, "", true, logs))
        task.Run(SchedCtx())
        AssertEq(io.Count("down Esc"), SellTask.WalkTries, "one reset per walk")
        AssertEq(io.Count("up e"), SellTask.WalkTries * (1 + SellTask.Nudges), "every walk and nudge pressed E")
        AssertEq(io.Count("click@1308,1073"), 2, "after the last walk the shop dialog is tried once (2 skip clicks)")
        AssertEq(st.needRepath, false, "sell run finished like the old blind flow")
        AssertTrue(FsHasLog(logs, "sell: Captain Flarg's dialog not seen after 3 walks (read: '') - trying the shop anyway"), "logged")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_FailedChecksLastResetGoesBlind() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.needRepath := true
        io := RsIO(99)
        io.fisher := (io) => "Captain Flarg Click to skip."
        FsSellScreen(io, 1)
        logs := []
        task := SellTask(t.cfg, st, FsDeps(io, "", true, logs))
        task.Run(SchedCtx())
        AssertEq(io.Count("up e"), 1, "no route walked after the failed checked resets; one after the blind reset")
        AssertEq(io.Count("down Enter"), 1, "only the blind reset confirms")
        AssertEq(io.Count("down Esc"), SellTask.WalkTries * Input.ResetTries + 1, "checked tries then one blind Esc")
        AssertTrue(FsHasLog(logs, "sell: reset failed: respawn prompt never showed after Esc + R"), "reason logged")
        AssertTrue(FsHasLog(logs, "sell: last try - resetting without screen checks"), "fallback logged")
        AssertEq(st.needRepath, false, "sell finished")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

RsAtFisher(io) => "Captain Flarg / Click to skip."

Test_Sell_ShopChecksSellEachTypeFast() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsAtFisher
        FsSellScreen(io, 3)                     ; 3 fish types
        logs := []
        SellTask(t.cfg, st, FsDeps(io, "", true, logs)).Run(SchedCtx())
        AssertEq(io.Count("click@1117,550"), 3, "selects a fish per round")
        AssertEq(io.Count("click@904,1080"), 3, "Sell All per round")
        AssertEq(io.Count("click@1002,831"), 3, "confirms per round")
        span := io.lastClick["click@1002,831"] - io.firstClick["click@1117,550"]
        AssertTrue(span < 3 * 2000, "3 rounds well under the old ~10 s each (span " span " ms)")
        AssertTrue(FsHasLog(logs, "sell: sold 3 fish types"), "logged")
        AssertEq(io.Count("click@1945,355"), 0, "no rescue close click")
        AssertEq(st.needRepath, false, "done")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_ShopNeverOpensNoClicksInside() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsAtFisher
        io.shopFail := true
        FsSellScreen(io, 3)
        logs := []
        SellTask(t.cfg, st, FsDeps(io, "", true, logs)).Run(SchedCtx())
        AssertEq(io.Count("click@1117,550"), 0, "no item click")
        AssertEq(io.Count("click@1002,831"), 0, "no confirm")
        AssertTrue(FsHasLog(logs, "sell: the Fishing Shop did not open"), "logged")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_NoPopupStopsSelling() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsAtFisher
        io.popupFail := true
        FsSellScreen(io, 3)
        logs := []
        SellTask(t.cfg, st, FsDeps(io, "", true, logs)).Run(SchedCtx())
        AssertEq(io.Count("click@904,1080"), 1, "one Sell All click")
        AssertEq(io.Count("click@1002,831"), 0, "never confirms without the popup")
        AssertTrue(FsHasLog(logs, "sell: no Sell Confirm popup after the sell click - stopping"), "logged")
        AssertEq(io.Count("click@1958,361"), 1, "shop closed")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_LostConfirmPressIsRetried() {
    ; clip 2026-10-26 22:42: a press on the popup's Sell was lost and the
    ; popup stayed open under everything that came after
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsAtFisher
        io.confirmLost := 1
        FsSellScreen(io, 1)
        logs := []
        SellTask(t.cfg, st, FsDeps(io, "", true, logs)).Run(SchedCtx())
        AssertEq(io.Count("click@1002,831"), 2, "Sell pressed again")
        AssertTrue(FsHasLog(logs, "sell: the Sell Confirm popup is still open - pressing Sell again"), "logged")
        AssertEq(io.Count("click@1492,830"), 0, "no Cancel needed")
        AssertEq(io.popupUp, false, "popup closed")
        AssertTrue(FsHasLog(logs, "sell: sold 1 fish type"), "counted as sold")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; live 2026-10-27: the popup read "you reo y wont to sell oll your Pironho?",
; the old word check missed it and the macro walked off with it open
Test_Sell_PopupInTheGameFontIsPressed() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsAtFisher
        io.popupText := 'you reo y wont to sell oll your Pironho?"'
        FsSellScreen(io, 1)
        logs := []
        SellTask(t.cfg, st, FsDeps(io, "", true, logs)).Run(SchedCtx())
        AssertEq(io.Count("click@1002,831"), 1, "Sell pressed on the popup")
        AssertEq(io.popupUp, false, "popup closed")
        AssertTrue(FsHasLog(logs, "sell: sold 1 fish type"), "counted as sold")
        AssertTrue(!FsHasLog(logs, "sell: no Sell Confirm popup after the sell click - stopping"), "not mistaken for no popup")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_PopupThatNeverClosesIsCancelled() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.needRepath := true
        io := RsIO()
        io.fisher := RsAtFisher
        io.confirmLost := 99
        FsSellScreen(io, 3)
        logs := []
        SellTask(t.cfg, st, FsDeps(io, "", true, logs)).Run(SchedCtx())
        AssertEq(io.Count("click@1002,831"), SellTask.ShopChecks.confirmTries, "Sell pressed confirmTries times")
        AssertEq(io.Count("click@1492,830"), 1, "then Cancel")
        AssertEq(io.popupUp, false, "never left open")
        AssertEq(io.Count("click@904,1080"), 1, "selling stopped after that round")
        AssertEq(io.Count("click@1958,361"), 1, "shop closed")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; RsIO with Captain Flarg's dialog as the game keeps it: up once the route's
; E is released, still up after the shop's X (only the shop closes), gone
; after his Leave (1700,1150). xLost: shop X clicks that do nothing. A key
; pressed after the first X click while the shop, the popup or his dialog
; is up sets walkedOpen (the walk back started with it open). preempt
; ("sellall"): the Sell All click preempts ctx (halt: stops it instead).
; Wait() honours ctx like the real io.
class RsFlargIO extends RsIO {
    __New() {
        super.__New()
        this.dialogUp := false
        this.xLost := 0
        this.xClicks := 0
        this.walkedOpen := ""
        this.ctx := ""
        this.preempt := ""
        this.halt := false
        this.fisher := (io) => io.dialogUp ? "Captain Flarg / Avvvvvv... What do you want??" : ""
    }
    Down(k) {
        if (this.xClicks > 0 && this.walkedOpen = "" && (this.shopUp || this.popupUp || this.dialogUp))
            this.walkedOpen := k
        super.Down(k)
    }
    Up(k) {
        super.Up(k)
        if (k = "e")
            this.dialogUp := true
    }
    ClickHere() {
        lost := (this.x = 1958 && this.y = 361 && ++this.xClicks <= this.xLost)
        was := this.shopUp
        super.ClickHere()
        if lost
            this.shopUp := was
        if (this.x = 1700 && this.y = 1150)
            this.dialogUp := false
        if (this.preempt = "sellall" && this.x = 904 && this.y = 1080 && IsObject(this.ctx)) {
            if this.halt
                this.ctx.Stop()
            else
                this.ctx.RequestPreempt()
        }
    }
    Wait(ms, ctx := "") {
        if (IsObject(ctx) && ctx.ShouldStop())
            return false
        return super.Wait(ms, ctx)
    }
}

; Calibration with Captain Flarg's Leave button.
class RsCal {
    __New(points := "") {
        this.p := (points is Map) ? points : Map("fisher_leave", {x: 1700, y: 1150, color: 0})
    }
    Point(id) => this.p.Has(id) ? this.p[id] : ""
}

RsFlargRun(io, st, ctx := "", logs := "") {
    d := FsDeps(io, "", true, IsObject(logs) ? logs : [])
    d.cal := RsCal()
    t := FsMakeCfg()
    try {
        task := SellTask(t.cfg, st, d)
        task.Run(IsObject(ctx) ? ctx : SchedCtx())
        return task
    } finally {
        FsClean(t.dir)
    }
}

Test_Sell_LeavesFlargsDialogBeforeWalkingBack() {
    ; 2026-10-27 review: his buttons stay up after the shop's X; the walk
    ; back started with them open, they covered the fishing panel and every
    ; catch re-pathed until the stuck pause
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 15
        io := RsFlargIO()
        FsSellScreen(io, 1)
        RsFlargRun(io, st)
        AssertEq(io.Count("click@1700,1150"), 1, "Leave clicked")
        AssertTrue(io.IndexOf("click@1700,1150") > io.IndexOf("click@1958,361"), "after the shop's X")
        AssertEq(io.walkedOpen, "", "the walk back started with nothing open")
        AssertEq(io.dialogUp, false, "his dialog closed")
        AssertEq(st.fishLoops, 0, "sold")
        ; the first X click is lost: clicked again until the shop is gone
        st2 := SchedState()
        st2.fishLoops := 15
        io2 := RsFlargIO()
        io2.xLost := 1
        FsSellScreen(io2, 1)
        logs := []
        RsFlargRun(io2, st2, , logs)
        AssertEq(io2.Count("click@1958,361"), 2, "the shop's X clicked again")
        AssertEq(io2.shopUp, false, "the shop closed")
        AssertEq(io2.walkedOpen, "", "nothing open on the walk back")
        AssertTrue(FsHasLog(logs, "sell: the Fishing Shop is still open after its X (try 1/3)"), "logged")
    } finally {
        FsScreen.Restore()
    }
}

Test_Sell_ShopNeverOpenedIsNotASell() {
    ; nothing was sold: fishLoops / needRepath stay, no X click on nothing,
    ; his dialog is left; three such visits in a row pause the macro
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 5   ; fish caught: the shop is visited
        st.fishLoops := 15
        io := RsFlargIO()
        io.shopFail := true
        FsSellScreen(io, 1)
        RsFlargRun(io, st)
        AssertEq(st.fishLoops, 15, "not counted as a sell: fishLoops kept")
        AssertEq(st.stats.Has("sells"), false, "no sell counted")
        AssertEq(io.Count("click@1958,361"), 0, "no X click on a shop that is not there")
        AssertEq(io.dialogUp, false, "his dialog left")
        st2 := SchedState()
        st2.fishLoops := 5   ; fish caught: the shop is visited
        st2.needRepath := true
        io2 := RsFlargIO()
        io2.shopFail := true
        FsSellScreen(io2, 1)
        RsFlargRun(io2, st2)
        AssertEq(st2.needRepath, true, "a re-path stays due")
        ; the same task three times: paused instead of walking forever
        t := FsMakeCfg()
        try {
            told := []
            io3 := RsFlargIO()
            io3.shopFail := true
            FsSellScreen(io3, 1)
            d := FsDeps(io3, "", true, [])
            d.cal := RsCal()
            d.stuck := (msg) => told.Push(msg)
            st3 := SchedState()
            st3.fishLoops := 5   ; fish caught: the shop is visited
            st3.fishLoops := 15
            task := SellTask(t.cfg, st3, d)
            ctx := SchedCtx()
            Loop SellTask.MaxShopMisses
                task.Run(ctx)
            AssertEq(ctx.IsPaused(), true, "paused after " SellTask.MaxShopMisses " misses")
            AssertEq(told.Length, 1, "reported once")
            AssertTrue(InStr(told[1], "PAUSED") && InStr(told[1], "F2"), "says it paused and how to go on")
        } finally {
            FsClean(t.dir)
        }
    } finally {
        FsScreen.Restore()
    }
}

Test_Sell_PopupMissedAt1xGetsASecondLook() {
    ; 2026-10-27 review: a 1x read that misses the popup walked off with it
    ; open. Read again at 2x, then by its Cancel label ("Concel")
    for c in [["Pironho Silverfin", "Sell Confirm / Do you really want to sell all of your Pironho?"], ["Pironho Silverfin", ""]] {
        t := FsMakeCfg()
        FsScreen.Install()
        try {
            st := SchedState()
            st.fishLoops := 5   ; fish caught: the shop is visited
            st.needRepath := true
            io := RsIO()
            io.fisher := RsAtFisher
            io.popupText := c[1]
            io.popupText2 := c[2]
            FsSellScreen(io, 1)
            logs := []
            SellTask(t.cfg, st, FsDeps(io, "", true, logs)).Run(SchedCtx())
            what := c[2] = "" ? "by its Cancel label" : "at 2x"
            AssertEq(io.Count("click@1002,831"), 1, what ": Sell pressed on the popup")
            AssertEq(io.popupUp, false, what ": popup closed")
            AssertTrue(FsHasLog(logs, "sell: the Sell Confirm popup is up after all (second look) - pressing Sell"), what ": logged")
            AssertTrue(FsHasLog(logs, "sell: sold 1 fish type"), what ": counted as sold")
        } finally {
            FsScreen.Restore()
            FsClean(t.dir)
        }
    }
}

Test_Sell_PreemptClosesPopupShopAndDialog() {
    ; preempted right after Sell All (the popup up over the shop, his dialog
    ; behind): Cancel, the shop's X, Leave, before the next task starts
    ; (2026-10-27 review)
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 15
        io := RsFlargIO()
        ctx := SchedCtx()
        io.ctx := ctx
        io.preempt := "sellall"
        FsSellScreen(io, 3)
        RsFlargRun(io, st, ctx)
        AssertEq(io.Count("click@1002,831"), 0, "never confirmed after the preempt")
        AssertEq(io.Count("click@1492,830"), 1, "the popup's Cancel")
        AssertEq(io.popupUp, false, "popup closed")
        AssertEq(io.shopUp, false, "shop closed")
        AssertEq(io.dialogUp, false, "his dialog left")
        AssertTrue(io.IndexOf("click@1492,830") < io.IndexOf("click@1958,361") && io.IndexOf("click@1958,361") < io.IndexOf("click@1700,1150"), "Cancel, X, Leave")
        AssertEq(st.fishLoops, 15, "not a finished sell")
        ; F3 / pause instead: nothing more is sent
        st2 := SchedState()
        st2.fishLoops := 15
        io2 := RsFlargIO()
        ctx2 := SchedCtx()
        io2.ctx := ctx2
        io2.preempt := "sellall"
        io2.halt := true
        FsSellScreen(io2, 3)
        RsFlargRun(io2, st2, ctx2)
        AssertEq(io2.Count("click@1492,830") + io2.Count("click@1958,361") + io2.Count("click@1700,1150"), 0, "halted: no clicks")
        AssertEq(io2.popupUp, true, "halted: left as it is")
    } finally {
        FsScreen.Restore()
    }
}

Test_Sell_StuckRewalksPauseInsteadOfLooping() {
    ; re-paths with no catch in between: the next one pauses the macro and
    ; reports it instead of resetting + walking again (reset, menu, reset...)
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.needRepath := true
        st.repathStreak := SellTask.MaxRepathStreak
        io := RsIO()
        logs := [], told := []
        d := FsDeps(io, "", true, logs)
        d.stuck := (msg) => told.Push(msg)
        ctx := SchedCtx()
        SellTask(t.cfg, st, d).Run(ctx)
        AssertEq(ctx.IsPaused(), true, "macro paused")
        AssertEq(io.Count("down Esc") + io.Count("down r"), 0, "no reset attempted")
        AssertEq(told.Length, 1, "reported once")
        AssertTrue(InStr(told[1], "PAUSED") && InStr(told[1], "F2"), "says it paused and how to go on")
        AssertEq(st.repathStreak, 0, "F2 gives fresh tries")
        AssertEq(st.needRepath, true, "the re-path is still due after F2")
        ; one below the limit: walks as usual
        st2 := SchedState()
        st2.needRepath := true
        st2.repathStreak := SellTask.MaxRepathStreak - 1
        io2 := RsIO()
        FsSellScreen(io2, 1)
        io2.fisher := (io) => "Captain Flarg / Click to skip."
        ctx2 := SchedCtx()
        SellTask(t.cfg, st2, FsDeps(io2, "", true, [])).Run(ctx2)
        AssertEq(ctx2.IsPaused(), false, "not paused below the limit")
        AssertTrue(io2.Count("down Esc") >= 1, "reset + walk as usual")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; loop L19 2026-11-03: Eden's big title behind the prompt garbled the
; question ("Are you sure ou want spaw o r character?") on 9 respawns; its
; buttons ("Respawn" / "Don't Respawn") read on every frame
class RsGarbledIO extends RsIO {
    Ocr(x, y, w, h, scale := 1) {
        if (x = 900)
            return this.promptUp ? "Are you sure ou want`nspaw`no r character?" : ""
        if (x = 1050)
            return this.promptUp ? "Respawn`nDon't Respawn" : ""
        return super.Ocr(x, y, w, h, scale)
    }
}

Test_Reset_PromptReadOnItsButtons() {
    io := RsGarbledIO()
    AssertEq(Input.ResetToSpawn(SchedCtx(), io), true, "the buttons read: the reset goes on")
    AssertEq(io.Count("down Enter"), 1, "confirmed once")
    AssertEq(io.promptUp, false, "the prompt is not left open")
}

; loop L19 05:19 / 05:21: the chat (back after the respawn) over the
; Collections title, the wide read lost "[Exit]"; the other marks and the
; tight "[Exit]" box read. chatOver: the wide box reads only chat
class RsChatIO extends RsIO {
    __New(openFail := 0, closeFail := 0) {
        super.__New(0, openFail, closeFail)
        this.exitHidden := false     ; the tight "[Exit]" box unreadable too
    }
    Ocr(x, y, w, h, scale := 1) {
        if (x = 60)
            return "[Rainy]: Strong winds and showers sweep through the world.."
        if (x = 455)
            return (this.collUp && !this.exitHidden) ? "; [Exit]" : ""
        if (x = 560)
            return this.collUp ? "Reploy Cutscene" : ""
        if (x = 2140)
            return this.collUp ? "nefoult`nHide IJI" : ""
        return super.Ocr(x, y, w, h, scale)
    }
}

Test_Reset_CollectionsSeenUnderTheChat() {
    io := RsChatIO()
    AssertEq(Input.ReAim(SchedCtx(), io), true, "opened and closed, the title under the chat")
    AssertEq(io.Count("click@52,621"), 1, "one open click (was 3: the last 2 into the open screen)")
    AssertEq(io.Count("click@525,158"), 1, "closed on its [Exit]")
    AssertEq(io.collUp, false, "not left open")
    ; left open (loop start 05:19:33): seen, closed
    io2 := RsChatIO()
    io2.collUp := true
    AssertTrue(Input.CollectionsUp(io2), "seen by its other marks")
    AssertEq(Input.CloseCollections(SchedCtx(), io2), 1, "closed")
    ; already open when the camera re-aim starts: no click on its open button (inside it)
    io3 := RsChatIO()
    io3.collUp := true
    AssertEq(Input.ReAim(SchedCtx(), io3), true, "re-aimed")
    AssertEq(io3.Count("click@52,621"), 0, "nothing clicked inside the screen")
    AssertEq(io3.collUp, false, "closed")
}

Test_Reset_CollectionsCloseOnlyOnItsExit() {
    ; up (its other marks) but "[Exit]" nowhere readable: no click at all
    io := RsChatIO()
    io.collUp := true
    io.exitHidden := true
    AssertEq(Input.CloseCollections(SchedCtx(), io), 2, "would not close: reported (the hunt stops)")
    clicks := 0
    for e in io.log
        clicks += InStr(e, "click@") = 1 ? 1 : 0
    AssertEq(clicks, 0, "no click without its [Exit] seen")
}

; real frames (full 2560x1440: the live failure shot 05:21:42, the clip
; GRAVEYARD 051955 at 720p scaled 2x; both with the chat over the title)
Test_Reset_RealCollectionsUnderTheChat() {
    for f in ["collections_chat_052142.jpg", "collections_chat_clip.jpg"] {
        p := A_ScriptDir "\screens\" f
        AssertTrue(FileExist(p), f " exists")
        rd := (x, y, w, h) => Ocr.ReadFile(p, x, y, w, h)
        AssertTrue(Input.CollectionsUp("", rd), f ": the Collections screen reads")
        AssertTrue(Input._ExitSeen("", rd), f ": its [Exit] reads")
        n := 0
        for m in Input.ResetChecks["collection"].marks
            n += InStr(StrLower(rd(m.x, m.y, m.w, m.h)), m.text) ? 1 : 0
        AssertEq(n, Input.ResetChecks["collection"].marks.Length, f ": every mark on its own")
    }
    p := A_ScriptDir "\screens\world_day.jpg"
    rd := (x, y, w, h) => Ocr.ReadFile(p, x, y, w, h)
    AssertTrue(!Input.CollectionsUp("", rd), "the world: no Collections screen")
    AssertTrue(!Input._ExitSeen("", rd), "nor its [Exit]")
}

; real frames (crops x 880.., y 470..; live 2560x1440 and the PUMPKIN MOON
; clip, 720p scaled 2x): the prompt reads through its buttons
Test_Reset_RealPromptReads() {
    for f in ["respawn_prompt_022801", "respawn_prompt_024404", "respawn_prompt_033945", "respawn_prompt_035339"
        , "respawn_prompt_041038", "respawn_prompt_pumpkin_clip"] {
        p := A_ScriptDir "\screens\" f ".png"
        AssertTrue(FileExist(p), f " exists")
        rd := (x, y, w, h) => Ocr.ReadFile(p, x - 880, y - 470, w, h)
        AssertTrue(Input._Has("", "prompt", rd), f ": the respawn prompt reads")
    }
    ; Eden's title alone (no question, no buttons) is no prompt
    AssertTrue(!Input._Has("", "prompt", (x, y, w, h) => "Eden`nThe Void Contractor"), "the title alone is no prompt")
}

; Roblox's own respawn prompt does not scale like the game's UI: at
; 1366x768 it sat out of both boxes and every respawn failed (live
; 2026-11-11). Below 1440p a wide box right of the chat is read too.
class RcWideIO {
    __New(hit) => (this.hit := hit, this.reads := [])
    Ocr(x, y, w, h, scale := 1) {
        this.reads.Push(x "," y)
        return (x = this.hit.x && y = this.hit.y) ? "Are you sure you want to respawn your character? Respawn Don't Respawn" : ""
    }
}
Test_Reset_PromptWideBoxBelow1440() {
    w := Input.ResetChecks["prompt"].wide
    io := RcWideIO(w)
    AssertEq(Input._Has(io, "prompt"), false, "2560x1440: the wide box is not read")
    try {
        Screen.SetClient(0, 0, 1366, 768)
        AssertEq(Input._Has(io, "prompt"), true, "1366x768: the prompt reads in the wide box")
        ; it starts right of the chat (client x >= 483 at 768p): the chat's
        ; "[Respawn]: You can reset after 2s." line is never in it
        AssertTrue(Screen.X(w.x) - Screen.cx > 483, "the wide box starts right of the chat")
    } finally Screen.Reset()
}

; Below 1440p the Collections screen's [Exit] is looked for by its text and
; clicked there (1366x768: 24 px under the scaled point, live 2026-11-11)
class RcExitIO {
    __New() => (this.calls := 0)
    FindWord(x, y, w, h, re, wordRe, scale := 1) {
        this.calls++
        return {x: 513, y: 203, text: "Aura Collections [Exit]"}
    }
}
Test_Reset_ExitFoundByItsTextBelow1440() {
    io := RcExitIO()
    AssertEq(Input._ExitAt(io), "", "2560x1440: the calibrated point (no text search)")
    AssertEq(io.calls, 0, "no search at 2560x1440")
    try {
        Screen.SetClient(0, 0, 1366, 768)
        p := Input._ExitAt(io)
        AssertTrue(IsObject(p) && p.x = 513 && p.y = 203, "1366x768: where [Exit] reads (design px)")
        AssertEq(Input._ExitAt({}), "", "an io that cannot find text: none")
    } finally Screen.Reset()
}

; 5:4 (live 1280x1024): "[Exit]" squeezed into the title, only "Aura" reads:
; placed a fixed design offset right of the "Common" row (the list keeps its shape)
class RcSqueezeIO {
    FindWord(x, y, w, h, re, wordRe, scale := 1) {
        if InStr(re, "exit")
            return ""
        if InStr(re, "aur")
            return {x: 140, y: 177, text: "Aura"}
        if InStr(re, "common")
            return {x: 300, y: 300, text: "Common"}
        return ""
    }
}
Test_Reset_ExitPlacedFromTheTitleWhenSqueezed() {
    try {
        Screen.SetClient(0, 0, 1280, 1024)
        p := Input._ExitAt(RcSqueezeIO())
        AssertTrue(IsObject(p) && p.x = 300 + Input.ExitFromCommon && p.y = 177, "right of Common by the list's fixed offset, on the title's row: " (IsObject(p) ? p.x "," p.y : "none"))
    } finally Screen.Reset()
}
