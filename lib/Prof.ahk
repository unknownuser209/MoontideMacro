#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Prof: where a task's time goes (speed work, 2026-11-17). Off by default
; ([General] timing=1 turns it on); off, every call returns at once.
;
;   Prof.Start(task)      a task starts: clears the counters
;   Prof.Begin(cat) / Prof.End()
;                         time between them goes to cat ("walk", "respawn",
;                         "wait", "ocr", "pixel"). Exclusive: a nested Begin
;                         takes the time from its parent, except inside
;                         "walk" / "respawn", which keep everything they do.
;   Prof.Text()           "time: obby 63.1 s = walk 40.2, wait 9.0, ocr 6.3
;                         (21 reads), respawn 4.1, pixel 0.3, other 3.2"
; ---------------------------------------------------------------------------
class Prof {
    static on := false
    static Containers := Map("walk", 1, "respawn", 1)
    static _task := "", _t0 := 0, _ms := Map(), _n := Map(), _stack := []

    static Now() {
        static freq := 0
        if !freq
            DllCall("QueryPerformanceFrequency", "Int64*", &freq)
        DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
        return c * 1000 / freq
    }

    static Start(task) {
        if !Prof.on
            return
        Prof._task := task, Prof._t0 := Prof.Now(), Prof._ms := Map(), Prof._n := Map(), Prof._stack := []
    }

    static Begin(cat) {
        if (!Prof.on || Prof._task = "")
            return
        now := Prof.Now()
        st := Prof._stack
        if (st.Length && (st[st.Length].cat = "" || Prof.Containers.Has(st[st.Length].cat))) {
            st.Push({cat: "", t: now})                  ; inside a walk: the walk keeps it
            return
        }
        if st.Length
            Prof._Add(st[st.Length].cat, now - st[st.Length].t, false)
        st.Push({cat: cat, t: now})
        Prof._n[cat] := (Prof._n.Has(cat) ? Prof._n[cat] : 0) + 1
    }

    static End() {
        if (!Prof.on || Prof._task = "" || !Prof._stack.Length)
            return
        now := Prof.Now()
        f := Prof._stack.Pop()
        if (f.cat != "")
            Prof._Add(f.cat, now - f.t, false)
        if (f.cat != "" && Prof._stack.Length)
            Prof._stack[Prof._stack.Length].t := now   ; the parent runs on from here
    }

    static _Add(cat, ms, count) {
        Prof._ms[cat] := (Prof._ms.Has(cat) ? Prof._ms[cat] : 0) + ms
    }

    ; the task's line, "" when off or no task
    static Text() {
        if (!Prof.on || Prof._task = "")
            return ""
        total := Prof.Now() - Prof._t0
        rest := total
        parts := []
        for cat, ms in Prof._ms
            parts.Push({cat: cat, ms: ms}), rest -= ms
        ; biggest first
        Loop parts.Length - 1 {
            i := A_Index
            Loop parts.Length - i {
                j := A_Index
                if (parts[j].ms < parts[j + 1].ms)
                    t := parts[j], parts[j] := parts[j + 1], parts[j + 1] := t
            }
        }
        s := ""
        for p in parts
            s .= ", " p.cat " " Format("{:.1f}", p.ms / 1000) (p.cat = "ocr" ? " (" Prof._n["ocr"] " reads)" : "")
        s .= ", other " Format("{:.1f}", Max(0, rest) / 1000)
        return "time: " Prof._task " " Format("{:.1f}", total / 1000) " s =" SubStr(s, 2)
    }

    static Stop() {
        Prof._task := "", Prof._stack := []
    }
}
