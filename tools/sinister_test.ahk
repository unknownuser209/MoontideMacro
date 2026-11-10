#Requires AutoHotkey v2.0
#SingleInstance Off
#Include %A_LineFile%\..\..\lib\Config.ahk
#Include %A_LineFile%\..\..\lib\Webhook.ahk
#Include %A_LineFile%\..\..\lib\tasks\Sinister.ahk
; ---------------------------------------------------------------------------
; Test send of the GRAVEYARD boss message to ONE webhook entry (dev only).
; SENDS FOR REAL to Discord.
;
;   & "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut tools\sinister_test.ahk "<webhook name>" [seconds] | Out-Host
;
; Through SinisterReport + Webhook.PostText / EditText, the code path of the
; macro: posts "<private server link> sinister s natrual spawn" to the named
; webhook entry of settings.ini (name not case sensitive; its enabled flag
; and event boxes ignored, never a ping), waits [seconds] (default 30), then
; edits that message to "<private server link> dead". No ghost-server check
; (the user runs it on purpose). Prints only scrubbed lines: never a webhook
; URL or the link. Exit 0 = posted and edited.
; ---------------------------------------------------------------------------

Out(s) => FileAppend(Webhook.ScrubText(s) "`n", "*")

if (A_Args.Length < 1) {
    Out('usage: tools\sinister_test.ahk "<webhook name>" [seconds]')
    ExitApp(2)
}
name := Trim(A_Args[1])
secs := (A_Args.Length > 1 && IsInteger(A_Args[2])) ? Integer(A_Args[2]) : 30
root := RegExReplace(A_LineFile, "\\tools\\[^\\]+$", "")
cfg := Config(root)
hook := ""
names := []
for w in cfg.Webhooks() {
    names.Push(w["name"])
    if (StrLower(Trim(w["name"])) = StrLower(name))
        hook := w
}
if !IsObject(hook) {
    list := ""
    for n in names
        list .= (list = "" ? "" : ", ") '"' n '"'
    Out('no webhook named "' name '" in settings.ini (have: ' (list = "" ? "none" : list) ")")
    ExitApp(2)
}
wh := Webhook(cfg, (t) => Out(t))
rep := SinisterReport({webhook: wh, cfg: cfg, ghost: () => false, log: (t) => Out(t), hook: hook})
if !rep.Spawn("test " A_TickCount) {
    Out("nothing sent (see the line above)")
    ExitApp(1)
}
; the post: until Discord answered with the message
end := A_TickCount + 30000
while (rep.msg.Waiting() && A_TickCount < end) {
    wh.Flush()
    Sleep(100)
}
part := rep.msg.parts[1]
if (part.state != "ok") {
    wh.Drain(5000)
    Out('post to "' hook["name"] '" failed (' part.state ")")
    ExitApp(1)
}
Out('posted to "' hook["name"] '" (message id ' part.id "), editing in " secs " s")
end := A_TickCount + secs * 1000
while (A_TickCount < end) {
    wh.Flush()
    Sleep(200)
}
rep.Killed("test")
end := A_TickCount + 30000
while (part.edited = "" && A_TickCount < end) {
    wh.Flush()
    Sleep(100)
}
wh.Drain(5000)
Out(part.edited = 1 ? "edited to dead" : "edit failed")
ExitApp(part.edited = 1 ? 0 : 1)
