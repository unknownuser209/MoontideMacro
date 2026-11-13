#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
; ---------------------------------------------------------------------------
; DiscordRemote: control the macro from one Discord channel through the
; user's OWN bot. REST polling only (https://discord.com/api/v10), no
; gateway / websocket, and never a blocking request inside Tick().
;
;   r := DiscordRemote(deps)   deps Map (all optional):
;     token      the bot token ("Bot " in front is stripped)
;     channelId  the one channel read and answered (digits)
;     allowedIds csv of Discord user ids (digits) allowed to give commands
;     prefix     command prefix (default "!")
;     pollSec    seconds between polls (default 5, at least 3)
;     handlers   Map cmd -> callable(args, msg) returning the reply: a String,
;                or an object / Map {text, file} (file = a PNG path uploaded
;                with the reply). "" = no reply. msg is {id, authorId, cmd,
;                args}. Only the whitelist (DiscordRemote.Commands) is kept;
;                "help" is built in and lists the commands that have one.
;     log        (text) -> logs; text NEVER holds the token or message text
;     now        () -> ms (default A_TickCount)
;     http       () -> a WinHttp.WinHttpRequest.5.1-like object (test seam;
;                default: the real COM object, 5/5/8/8 s timeouts)
;   r.Enabled    true when token, channelId and one allowed id are set (and
;                look valid).
;   r.Tick()     call every ~250 ms (app timer). Non-blocking: finishes the
;                request in flight (WaitForResponse(0)), else sends the next
;                queued reply, else starts a poll once pollSec has passed.
;                ONE request in flight at a time; one is dropped after 8 s.
;   r.Test()     BLOCKING (dashboard button only): GET /users/@me, the channel
;                and one message -> {ok, msg}, e.g. "Connected as MyBot, can
;                read #macro". A good test also clears a stop (see Reset).
;   r.Reset()    clears a stop after 401/403/404 and learns the newest
;                message again (old commands are never run).
;   r.State      "off" | "starting" | "listening" | "retrying" | "stopped"
;   r.LastError  the last problem logged ("" when fine), token-free
;   DiscordRemote.Parse(content, prefix) -> {cmd (lower case), args} or "".
;
; Polling: the first poll only learns the newest message id (GET ?limit=1).
; Then GET /channels/{id}/messages?after={lastId}&limit=10, handled oldest
; first; a full page polls again at once. Each command is answered with POST
; /channels/{id}/messages {content, message_reference, allowed_mentions none};
; a file reply is multipart/form-data (payload_json + files[0]), the same
; shape lib\Webhook.ahk uses for screenshots.
;
; Ignored silently: bots and webhooks (our own replies too), messages without
; the prefix, users not in allowedIds (logged ONCE per user id, never the
; text). Unknown commands get "Unknown command. Try !help".
;
; Errors: HTTP 429 waits Discord's retry_after; 401 (token rejected) and 403
; (no access) stop the remote until Reset/Test; 404 on the channel stops it
; too. Network errors, timeouts and 5xx back off 5, 10, 20, 40, 60, 60... s.
; An allowed user's message arriving with empty content means the bot has no
; Message Content intent: a hint is logged once.
;
; Security: the token is only ever put in the Authorization header. Every
; logged / returned text goes through Scrub(), which removes the token and
; anything shaped like one. Message contents are never logged.
;
; How to set up the bot (one time):
;   1. https://discord.com/developers/applications -> New Application, name
;      it (the name is what replies show).
;   2. Bot page -> Reset Token -> copy the token into the macro. It is a
;      password for the bot: never share it.
;   3. Same page, Privileged Gateway Intents: turn ON "Message Content
;      Intent" and save (without it the bot sees every message as empty).
;   4. OAuth2 -> URL Generator: scope "bot"; permissions View Channels (Read
;      Messages), Send Messages, Attach Files, Read Message History. Open the
;      generated link and add the bot to your server.
;   5. Discord Settings -> Advanced -> Developer Mode ON. Right click the
;      channel -> Copy Channel ID; right click your own name -> Copy User ID.
;      Put both in the macro, then press Test.
; ---------------------------------------------------------------------------

class DiscordRemote {
    static Api := "https://discord.com/api/v10"
    static UserAgent := "DiscordBot (MoontideMacro, 1.0)"
    static Commands := ["help", "status", "stats", "start", "stop", "pause", "resume", "screenshot", "log"]
    static Describe := Map("help", "this list", "status", "what the macro is doing", "stats", "session stats"
        , "start", "start the macro", "stop", "stop the macro", "pause", "pause the macro"
        , "resume", "resume after a pause", "screenshot", "a picture of the game", "log", "the last log lines")
    static TimeoutMs := 8000
    static PageSize := 10
    static MaxFileBytes := 8 * 1024 * 1024
    static MaxRateLimited := 5

    __New(deps := "") {
        d := (deps is Map) ? deps : Map()
        g := (k, def) => d.Has(k) ? d[k] : def
        tok := Trim(String(g("token", "")))
        if (SubStr(tok, 1, 4) = "Bot ")
            tok := Trim(SubStr(tok, 5))
        this.token := tok
        this.channelId := Trim(String(g("channelId", "")))
        this.allowed := Map()
        for part in StrSplit(String(g("allowedIds", "")), [",", ";", " ", "`t", "`n", "`r"]) {
            id := Trim(part)
            if RegExMatch(id, "^\d{5,25}$")
                this.allowed[id] := true
        }
        p := Trim(String(g("prefix", "!")))
        this.prefix := (p = "") ? "!" : p
        try
            ps := Integer(g("pollSec", 5))
        catch
            ps := 5
        this.pollSec := Max(3, ps)
        this._logFn := g("log", "")
        this._clock := g("now", "")
        this._httpFn := g("http", "")
        this.handlers := Map()
        h := g("handlers", "")
        if (h is Map) {
            for k, fn in h {
                k := StrLower(Trim(String(k)))
                if (k != "help" && DiscordRemote._IsCommand(k) && HasMethod(fn, "Call"))
                    this.handlers[k] := fn
            }
        }
        this.LastError := ""
        this._queue := []           ; replies {text, file, refId, attempts, limited}
        this._inflight := ""        ; {kind: learn|poll|reply, req, started, item}
        this._unknownLogged := Map()
        this._emptyHint := false
        this._listeningLogged := false
        this.Reset()
    }

    Enabled => (DiscordRemote._ValidToken(this.token) && RegExMatch(this.channelId, "^\d{5,25}$")
        && this.allowed.Count > 0) ? true : false

    State {
        get {
            if !this.Enabled
                return "off"
            if this._halted
                return "stopped"
            if (this._backoff > 0)
                return "retrying"
            return this._learned ? "listening" : "starting"
        }
    }

    Reset() {
        this._halted := false
        this._learned := false
        this._lastId := ""
        this._nextPollAt := 0
        this._holdUntil := 0
        this._backoff := 0
        this._netLogged := false
    }

    ; ---- parsing -----------------------------------------------------------

    static Parse(content, prefix := "!") {
        prefix := String(prefix) = "" ? "!" : String(prefix)
        s := LTrim(String(content), " `t`r`n")
        if (StrLen(s) <= StrLen(prefix) || SubStr(s, 1, StrLen(prefix)) != prefix)
            return ""
        if !RegExMatch(SubStr(s, StrLen(prefix) + 1), "s)^([A-Za-z][A-Za-z0-9_]{0,31})(?:\s+(.*))?$", &m)
            return ""
        return {cmd: StrLower(m[1]), args: Trim(m[2], " `t`r`n")}
    }

    ; ---- the timer ---------------------------------------------------------

    Tick() {
        if (!this.Enabled || this._halted)
            return
        now := this._Now()
        if IsObject(this._inflight) {
            this._Finish(this._inflight, now)
            if IsObject(this._inflight)
                return
        }
        if (this._halted || now < this._holdUntil)
            return
        if (this._queue.Length > 0) {
            this._SendReply(this._queue.RemoveAt(1))
            return
        }
        if (now >= this._nextPollAt) {
            this._nextPollAt := now + this.pollSec * 1000
            path := "/channels/" this.channelId "/messages?"
            if this._learned
                this._Start("poll", "GET", path "after=" this._lastId "&limit=" DiscordRemote.PageSize)
            else
                this._Start("learn", "GET", path "limit=1")
        }
    }

    _Start(kind, method, path, body := "", ctype := "", item := "") {
        try {
            req := this._NewRequest()
            req.Open(method, DiscordRemote.Api path, true)
            req.SetRequestHeader("Authorization", "Bot " this.token)
            req.SetRequestHeader("User-Agent", DiscordRemote.UserAgent)
            if (ctype != "")
                req.SetRequestHeader("Content-Type", ctype)
            if IsObject(body)
                req.Send(body)
            else
                req.Send()
            this._inflight := {kind: kind, req: req, started: this._Now(), item: item}
        } catch Any as e {
            this._inflight := ""
            this._NetFail({kind: kind, item: item}, e is Error ? e.Message : "error")
        }
    }

    _Finish(rec, now) {
        try {
            if !rec.req.WaitForResponse(0) {
                if (now - rec.started > DiscordRemote.TimeoutMs) {
                    try rec.req.Abort()
                    rec.req := ""
                    this._inflight := ""
                    this._NetFail(rec, "timed out")
                }
                return
            }
            status := Integer(rec.req.Status)
            body := ""
            try body := String(rec.req.ResponseText)
            wait := (status = 429) ? DiscordRemote._RetryAfterMs(body, rec.req) : 0
        } catch Any as e {
            rec.req := ""
            this._inflight := ""
            this._NetFail(rec, e is Error ? e.Message : "error")
            return
        }
        rec.req := ""
        this._inflight := ""
        if (status >= 200 && status < 300) {
            this._Ok()
            if (rec.kind = "reply")
                return
            try
                msgs := Json.Parse(body)
            catch
                msgs := ""
            if !(msgs is Array) {
                this._NetFail(rec, "unexpected reply from Discord")
                return
            }
            if (rec.kind = "learn")
                this._Learn(msgs)
            else
                this._Handle(msgs)
            return
        }
        if (status = 429) {
            this._holdUntil := now + wait
            this._Log("Remote: Discord rate limit, waiting " Round(wait / 1000, 1) " s")
            if (rec.kind = "reply") {
                rec.item.limited++
                if (rec.item.limited <= DiscordRemote.MaxRateLimited)
                    this._queue.InsertAt(1, rec.item)
                else
                    this._Log("Remote: gave up on a reply (rate limited " DiscordRemote.MaxRateLimited " times)")
            }
            return
        }
        if (status = 401)
            return this._Halt("Remote: bot token rejected - copy the token again from the Bot page. Remote control stopped.")
        if (status = 403) {
            if (rec.kind = "reply")
                return this._Halt("Remote: the bot cannot send messages in that channel - give it Send Messages and Attach Files. Remote control stopped.")
            return this._Halt("Remote: the bot cannot read that channel - check its permissions and the Message Content intent. Remote control stopped.")
        }
        if (status = 404 && rec.kind != "reply")
            return this._Halt("Remote: channel not found - check the channel id. Remote control stopped.")
        if (status >= 500 || status = 0) {
            this._NetFail(rec, "HTTP " status)
            return
        }
        if (rec.kind = "reply")
            this._Log("Remote: Discord refused a reply (HTTP " status ")")
        else
            this._NetFail(rec, "HTTP " status)
    }

    _Ok() {
        if this._netLogged
            this._Log("Remote: connected to Discord again")
        this._backoff := 0
        this._netLogged := false
        if (this.LastError != "" && !this._halted)
            this.LastError := ""
    }

    ; Network error / timeout / 5xx: back off 5, 10, 20 ... 60 s. A reply is
    ; tried up to 3 times.
    _NetFail(rec, why) {
        this._backoff := this._backoff ? Min(60, this._backoff * 2) : 5
        this._holdUntil := this._Now() + this._backoff * 1000
        if !this._netLogged {
            this._Problem("Remote: cannot reach Discord (" why "), retrying in " this._backoff " s")
            this._netLogged := true
        }
        if (rec.kind = "reply" && IsObject(rec.item)) {
            rec.item.attempts++
            if (rec.item.attempts < 3)
                this._queue.InsertAt(1, rec.item)
            else
                this._Log("Remote: gave up on a reply after 3 tries")
        }
    }

    _Halt(text) {
        this._halted := true
        this._Problem(text)
    }

    ; ---- messages ----------------------------------------------------------

    _Learn(msgs) {
        newest := ""
        for m in msgs {
            id := DiscordRemote._Get(m, "id")
            if (RegExMatch(id, "^\d{1,25}$") && (newest = "" || DiscordRemote.IdLess(newest, id)))
                newest := id
        }
        this._lastId := newest != "" ? newest : "0"
        this._learned := true
        if !this._listeningLogged {
            this._Log("Remote: listening for commands (prefix " this.prefix ")")
            this._listeningLogged := true
        }
    }

    _Handle(msgs) {
        list := []
        for m in msgs {
            if !(m is Map)
                continue
            id := DiscordRemote._Get(m, "id")
            if !RegExMatch(id, "^\d{1,25}$")
                continue
            ; insertion sort, oldest first
            i := list.Length
            while (i >= 1 && DiscordRemote.IdLess(id, DiscordRemote._Get(list[i], "id")))
                i--
            list.InsertAt(i + 1, m)
        }
        for m in list {
            id := DiscordRemote._Get(m, "id")
            if !DiscordRemote.IdLess(this._lastId, id)
                continue
            this._lastId := id
            this._OnMessage(m)
        }
        if (msgs.Length >= DiscordRemote.PageSize)
            this._nextPollAt := 0               ; more waiting: poll again at once
    }

    _OnMessage(m) {
        author := m.Has("author") ? m["author"] : ""
        if !(author is Map)
            return
        if (DiscordRemote._Get(author, "bot") = "1" || DiscordRemote._Get(m, "webhook_id") != "")
            return
        uid := DiscordRemote._Get(author, "id")
        if !this.allowed.Has(uid) {
            if (!this._unknownLogged.Has(uid) && this._unknownLogged.Count < 100) {
                this._unknownLogged[uid] := true
                this._Log("Remote: ignored a message from a user who is not allowed (id " RegExReplace(uid, "\D") ")")
            }
            return
        }
        typ := DiscordRemote._Get(m, "type")
        if !(typ = "" || typ = "0" || typ = "19")
            return
        content := m.Has("content") ? String(m["content"]) : ""
        if (content = "") {
            if (!this._emptyHint && DiscordRemote._Empty(m, "attachments") && DiscordRemote._Empty(m, "embeds")
                && DiscordRemote._Empty(m, "sticker_items") && !m.Has("message_snapshots") && !m.Has("poll")) {
                this._emptyHint := true
                this._Problem("Remote: an allowed user sent a message but Discord gave the bot no text. Turn on the MESSAGE CONTENT INTENT in the Discord developer portal (Bot page).")
            }
            return
        }
        p := DiscordRemote.Parse(content, this.prefix)
        if !IsObject(p)
            return
        if (p.cmd = "help") {
            this._AddReply(this._HelpText(), "", DiscordRemote._Get(m, "id"))
            return
        }
        if !this.handlers.Has(p.cmd) {
            this._AddReply("Unknown command. Try " this.prefix "help", "", DiscordRemote._Get(m, "id"))
            return
        }
        this._Log("Remote: " this.prefix p.cmd " from user " uid)
        info := {id: DiscordRemote._Get(m, "id"), authorId: uid, cmd: p.cmd, args: p.args}
        try {
            r := this.handlers[p.cmd].Call(p.args, info)
        } catch Any as e {
            this._Log("Remote: " this.prefix p.cmd " failed: " (e is Error ? e.Message : "error"))
            r := "That command failed."
        }
        rep := DiscordRemote._ReplyOf(r)
        this._AddReply(rep.text, rep.file, info.id)
    }

    _HelpText() {
        lines := ["Commands:"]
        for c in DiscordRemote.Commands {
            if (c = "help" || this.handlers.Has(c))
                lines.Push("``" this.prefix c "`` - " DiscordRemote.Describe[c])
        }
        out := ""
        for l in lines
            out .= (out = "" ? "" : "`n") l
        return out
    }

    _AddReply(text, file, refId) {
        text := this.Scrub(text)
        if (text = "" && file = "")
            return
        if (StrLen(text) > 2000)
            text := SubStr(text, 1, 1990) " [...]"
        this._queue.Push({text: text, file: file, refId: refId, attempts: 0, limited: 0})
    }

    _SendReply(item) {
        payload := Map("content", item.text, "allowed_mentions", Map("parse", []))
        if RegExMatch(item.refId, "^\d{1,25}$")
            payload["message_reference"] := Map("message_id", item.refId, "fail_if_not_exists", Json.Raw("false"))
        fileBuf := ""
        if (item.file != "") {
            try {
                fileBuf := FileRead(item.file, "RAW")
                if (fileBuf.Size > DiscordRemote.MaxFileBytes || fileBuf.Size = 0)
                    throw Error("size")
            } catch {
                fileBuf := ""
                item.file := ""
                payload["content"] := item.text := Trim(item.text "`n(the picture could not be attached)", "`n")
            }
        }
        jsonText := Json.Stringify(payload, 0)
        if IsObject(fileBuf) {
            SplitPath(item.file, &name)
            name := RegExReplace(name, '[^\w.\-]', "_")
            boundary := "----MoontideBoundary" A_TickCount Random(100000, 999999)
            body := DiscordRemote.BuildMultipart(jsonText, name, fileBuf, boundary)
            ctype := "multipart/form-data; boundary=" boundary
        } else {
            body := Buffer(StrPut(jsonText, "UTF-8") - 1)
            StrPut(jsonText, body, body.Size, "UTF-8")
            ctype := "application/json; charset=utf-8"
        }
        this._Start("reply", "POST", "/channels/" this.channelId "/messages", DiscordRemote._ToSafeArray(body), ctype, item)
    }

    ; ---- the blocking check (dashboard button) ------------------------------

    Test() {
        if (this.token = "" || this.channelId = "")
            return {ok: false, msg: "Fill in the bot token and the channel id first."}
        if !DiscordRemote._ValidToken(this.token)
            return {ok: false, msg: "That does not look like a bot token - copy it again from the Bot page."}
        if !RegExMatch(this.channelId, "^\d{5,25}$")
            return {ok: false, msg: "The channel id must be digits only (Developer Mode -> right click the channel -> Copy Channel ID)."}
        try {
            r := this._Sync("/users/@me")
            if (r.status = 401)
                return {ok: false, msg: "Bot token rejected - copy it again from the Bot page (Reset Token)."}
            if (r.status != 200)
                return {ok: false, msg: "Discord answered HTTP " r.status " for the bot account."}
            me := Json.Parse(r.body)
            who := DiscordRemote._Get(me, "username")
            disc := DiscordRemote._Get(me, "discriminator")
            if (disc != "" && disc != "0")
                who .= "#" disc
            who := this.Scrub(who)
            r := this._Sync("/channels/" this.channelId)
            if (r.status = 403)
                return {ok: false, msg: "Connected as " who ", but the bot cannot see that channel - invite it and give it View Channels."}
            if (r.status = 404)
                return {ok: false, msg: "Connected as " who ", but that channel was not found - check the channel id."}
            if (r.status != 200)
                return {ok: false, msg: "Connected as " who ", but Discord answered HTTP " r.status " for the channel."}
            ch := this.Scrub(DiscordRemote._Get(Json.Parse(r.body), "name"))
            r := this._Sync("/channels/" this.channelId "/messages?limit=1")
            if (r.status = 403)
                return {ok: false, msg: "Connected as " who " and sees #" ch ", but cannot read it - give it Read Message History."}
            if (r.status != 200)
                return {ok: false, msg: "Connected as " who ", but reading #" ch " gave HTTP " r.status "."}
        } catch Any as e {
            return {ok: false, msg: "Could not reach Discord: " this.Scrub(e is Error ? e.Message : "error")}
        }
        msg := "Connected as " who ", can read #" ch
        if (this.allowed.Count = 0)
            msg .= ". Add your Discord user id to the allowed users."
        if this._halted
            this.Reset()
        return {ok: true, msg: msg}
    }

    _Sync(path) {
        req := this._NewRequest()
        req.Open("GET", DiscordRemote.Api path, false)
        req.SetRequestHeader("Authorization", "Bot " this.token)
        req.SetRequestHeader("User-Agent", DiscordRemote.UserAgent)
        req.Send()
        return {status: Integer(req.Status), body: String(req.ResponseText)}
    }

    ; ---- helpers -----------------------------------------------------------

    ; Removes the token and anything shaped like a bot token or an
    ; Authorization value from text.
    Scrub(text) {
        text := String(text)
        if (StrLen(this.token) >= 8)
            text := StrReplace(text, this.token, "[token]")
        text := RegExReplace(text, "i)\bBot\s+[\w-]{20,}\.[\w.-]+", "Bot [token]")
        return RegExReplace(text, "[\w-]{20,}\.[\w-]{4,}\.[\w-]{20,}", "[token]")
    }

    _Log(text) {
        if HasMethod(this._logFn, "Call")
            try this._logFn.Call(this.Scrub(text))
    }

    ; A problem the dashboard can show (LastError) and the log gets.
    _Problem(text) {
        this.LastError := this.Scrub(text)
        this._Log(text)
    }

    _Now() => HasMethod(this._clock, "Call") ? this._clock.Call() : A_TickCount

    _NewRequest() {
        if HasMethod(this._httpFn, "Call")
            return this._httpFn.Call()
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 8000, 8000)    ; resolve, connect, send, receive (ms)
        return req
    }

    ; Snowflake ids as strings: a < b ?
    static IdLess(a, b) {
        a := String(a), b := String(b)
        if (StrLen(a) != StrLen(b))
            return StrLen(a) < StrLen(b)
        return StrCompare(a, b, true) < 0
    }

    static _ValidToken(t) => (StrLen(t) >= 20 && StrLen(t) <= 200 && RegExMatch(t, "^[\w.\-]+$")) ? true : false

    static _IsCommand(c) {
        for x in DiscordRemote.Commands
            if (x = c)
                return true
        return false
    }

    static _Get(m, key) {
        if !(m is Map) || !m.Has(key)
            return ""
        v := m[key]
        return IsObject(v) ? "" : String(v)
    }

    static _Empty(m, key) => !m.Has(key) || !(m[key] is Array) || m[key].Length = 0

    ; handler result -> {text, file}
    static _ReplyOf(r) {
        if (r is Map)
            return {text: r.Has("text") ? String(r["text"]) : "", file: r.Has("file") ? String(r["file"]) : ""}
        if IsObject(r)
            return {text: r.HasProp("text") ? String(r.text) : "", file: r.HasProp("file") ? String(r.file) : ""}
        return {text: String(r), file: ""}
    }

    ; Discord's 429 wait: "retry_after" (seconds) in the body, else the
    ; Retry-After header -> ms, 250..60000 (default 2000).
    static _RetryAfterMs(body, req) {
        secs := ""
        if RegExMatch(body, '"retry_after"\s*:\s*(\d+(?:\.\d+)?)', &m)
            secs := m[1]
        if (secs = "") {
            try {
                h := Trim(String(req.GetResponseHeader("Retry-After")))
                if RegExMatch(h, "^\d+(?:\.\d+)?$")
                    secs := h
            }
        }
        if (secs = "")
            return 2000
        return Max(250, Min(60000, Ceil(Float(secs) * 1000)))
    }

    ; multipart/form-data: payload_json + files[0] (a PNG) -> Buffer.
    static BuildMultipart(jsonText, fileName, fileBuf, boundary) {
        crlf := "`r`n"
        name := RegExReplace(fileName, '["\r\n\\]', "_")
        head := "--" boundary crlf
            . 'Content-Disposition: form-data; name="payload_json"' crlf
            . "Content-Type: application/json" crlf crlf
            . jsonText crlf
            . "--" boundary crlf
            . 'Content-Disposition: form-data; name="files[0]"; filename="' name '"' crlf
            . "Content-Type: image/png" crlf crlf
        tail := crlf "--" boundary "--" crlf
        hn := StrPut(head, "UTF-8") - 1
        tn := StrPut(tail, "UTF-8") - 1
        body := Buffer(hn + fileBuf.Size + tn)
        StrPut(head, body.Ptr, hn, "UTF-8")
        if (fileBuf.Size > 0)
            DllCall("RtlMoveMemory", "Ptr", body.Ptr + hn, "Ptr", fileBuf.Ptr, "UPtr", fileBuf.Size)
        StrPut(tail, body.Ptr + hn + fileBuf.Size, tn, "UTF-8")
        return body
    }

    ; Buffer -> VT_UI1 SAFEARRAY (WinHttp's binary body type).
    static _ToSafeArray(buf) {
        arr := ComObjArray(0x11, buf.Size)
        if (buf.Size > 0) {
            pv := NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr")   ; SAFEARRAY.pvData
            DllCall("RtlMoveMemory", "Ptr", pv, "Ptr", buf.Ptr, "UPtr", buf.Size)
        }
        return arr
    }
}
