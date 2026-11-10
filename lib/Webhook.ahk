#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Brand.ahk
#Include %A_LineFile%\..\Json.ahk
; ---------------------------------------------------------------------------
; Discord multi-webhook router (spec 4.7).
;
;   wh := Webhook(cfg, logFn := "")
;     cfg    object exposing Webhooks() -> Array of Map{name,url,mention,
;            enabled(1/0),events(Array of event names)}  (lib\Config.ahk)
;     logFn  optional callback logFn(text). Text NEVER contains a webhook URL
;            (all text is scrubbed; invalid URLs are rejected, not echoed).
;
;   wh.Route(eventType)      -> Array of the webhook Maps that are enabled AND
;                               have the event checked. Unknown event throws.
;   wh.Send(eventType, title, desc, color, opts)
;       opts.thumbnail: path to a PNG -> uploaded with the message and shown
;       as the embed's small square picture (top right; biome cards). A
;       missing or unreadable file is left out.
;       opts.buttons: Array of {label, url} -> link buttons under the embed
;       (max 5, https only). Sent with ?with_components=true (Discord drops
;       components on a normal webhook without it); if Discord answers 400
;       the message is sent again at once without the buttons.
;                            queues one message per routed webhook.
;                            opts: object {mention, screenshot} or a Map with
;                            those keys.
;                              mention    true -> put the webhook's mention in
;                                         message content (see rule below)
;                              screenshot path to a PNG; uploaded as
;                                         multipart/form-data (payload_json +
;                                         files[0]) and shown in the embed.
;                                         Missing file is ignored.
;   wh.SendTo(hook, title, desc, color, opts)
;                            queues ONE message to ONE webhook Map (as returned
;                            by cfg.Webhooks()), bypassing routing: ignores the
;                            hook's enabled flag and event checkboxes. NEVER
;                            carries a mention or @everyone (opts.mention /
;                            opts.everyone are ignored). Same queue, async
;                            send, retry and scrubbing as Send. opts:
;                              event       label stored in dry-run records
;                                          (default "direct")
;                              screenshot  as in Send
;                              thumbnail, buttons, fields   as in Send
;                              done        callable(ok, why), called ONCE when
;                                          the message is delivered (ok=1) or
;                                          finally fails / is skipped (ok=0).
;                                          why is scrubbed (never a URL).
;   wh.Broadcast(title, desc, color, opts)
;                            SendTo every ENABLED webhook, regardless of its
;                            event checkboxes (start announcement). No
;                            mention, no @everyone. Returns the count queued.
;   wh.PostText(eventType, content, opts) -> WebhookText handle, or "" when
;                            no webhook gets it. ONE plain message (content
;                            only, no embed) per routed webhook, NEVER a
;                            ping: allowed_mentions {"parse": []} and the
;                            hook's mention unused. Posted with ?wait=true:
;                            Discord answers with the message, whose id is
;                            kept per webhook entry in the handle (parts:
;                            {name, id, state "pending"/"ok"/"failed",
;                            edited ""/1/0}). opts.hook: one webhook Map in
;                            place of routing (as SendTo: its enabled flag
;                            and events ignored).
;   wh.EditText(handle, content)
;                            PATCH {url}/messages/{id} with the new content
;                            (same allowed_mentions) for every part of the
;                            handle: posted -> queued now; still on its way
;                            -> queued once its id comes; failed -> nothing.
;                            Same queue, pacing, 429 and retry as Send.
;                            -> parts queued or waiting.
;   wh.Flush()               call regularly (scheduler tick). Non-blocking:
;                            polls in-flight requests (WaitForResponse(0)),
;                            then starts queued ones asynchronously
;                            (WinHttp Open(..., true)). A failure (exception
;                            or non-2xx) is retried ONCE, retryDelayMs later
;                            (default 2000) on a following Flush. At most
;                            PacePerWindow (4) requests per PaceWindowMs (2 s)
;                            go to one URL; the rest wait. HTTP 429 holds that
;                            URL for Discord's retry_after / Retry-After and
;                            requeues WITHOUT spending the retry.
;   wh.Pending()             queued + in-flight count.
;   wh.Drain(timeoutMs)      BLOCKING helper for shutdown: Flush until idle.
;   wh.dryRun := true        Flush records to wh.sent instead of HTTP:
;                            each record {name, event, json, screenshot}.
;                            (URLs are not stored.)
;   wh.httpFactory           test seam: callable returning a WinHttp-like
;                            request object (default: WinHttp.WinHttpRequest.5.1).
;
; Mention rule (Webhook.NormalizeMention): the stored value may be written as
;   "123"  or "@123"  or "<@123>"    -> user  -> content "<@123>"
;   "@&123" or "&123" or "<@&123>"   -> role  -> content "<@&123>"
; Anything else (non-numeric, @everyone, @here) is ignored. Content is only
; set when opts.mention is true AND the webhook has a valid mention. The
; payload always carries allowed_mentions limited to that one id (or none),
; so embed text can never ping anyone.
;
; @everyone rule: opts.everyone is honoured ONLY by Send("rare", ...) and only
; when the title is not a "[TEST] " title. The content then carries "@everyone"
; (before the webhook's own mention, if any) and allowed_mentions adds
; parse:["everyone"] for that one message. Every other message keeps the strict
; allowed_mentions (at most the one user/role id, never everyone).
;
; Only discord.com / discordapp.com (incl. ptb./canary.) /api/webhooks/ URLs
; are ever requested.
; ---------------------------------------------------------------------------

class Webhook {
    static EventTypes := ["biome", "rare", "merchant", "quests", "craft", "errors", "startstop", "potions", "clips", "obby", "memorymatch", "sinister"]
    static _UrlRe := "i)^https://(?:(?:ptb|canary)\.)?(?:discord|discordapp)\.com/api/(?:v\d+/)?webhooks/\d+/[\w-]+(?:\?.*)?$"
    static _InflightTimeoutMs := 30000
    ; Pacing per webhook URL (2026-10-27 review): Discord allows about 5
    ; requests per 2 s per webhook, and one rare event queues 9+ cards in a
    ; millisecond; the ones over the limit got HTTP 429 and were dropped
    ; after one blind retry. At most PacePerWindow dispatches per
    ; PaceWindowMs to one URL; the rest wait in the queue (no attempt used).
    static PacePerWindow := 4
    static PaceWindowMs := 2000
    ; HTTP 429: wait Discord's retry_after (JSON body, seconds) or the
    ; Retry-After header, else this; requeued without spending an attempt,
    ; at most MaxRateLimited times per message.
    static DefaultRetryAfterMs := 2000
    static MaxRateLimited := 5

    dryRun := false
    sent := []
    httpFactory := ""
    retryDelayMs := 2000
    maxFileBytes := 10 * 1024 * 1024   ; larger screenshots are sent without the image
    clock := ""                        ; test seam: callable returning ms (default A_TickCount)

    __New(cfg, logFn := "") {
        this._cfg := cfg
        this._logFn := logFn
        this._queue := []
        this._inflight := []
        this._sentAt := Map()       ; url -> dispatch times (ms) inside the pacing window
        this._blocked := Map()      ; url -> ms until which a 429 holds every message to it
    }

    ; ---- routing -----------------------------------------------------------

    Route(eventType) {
        if !Webhook._IsEvent(eventType)
            throw ValueError("Webhook: unknown event type")
        out := []
        for w in this._cfg.Webhooks() {
            if !Webhook._Truthy(w.Has("enabled") ? w["enabled"] : 1)
                continue
            if !w.Has("events")
                continue
            for e in w["events"] {
                if (e = eventType) {
                    out.Push(w)
                    break
                }
            }
        }
        return out
    }

    ; ---- queue -------------------------------------------------------------

    Send(eventType, title, desc, color, opts := "") {
        hooks := this.Route(eventType)
        if (hooks.Length = 0)
            return
        wantMention := Webhook._Truthy(Webhook._Opt(opts, "mention", false))
        wantEveryone := (eventType = "rare") && Webhook._Truthy(Webhook._Opt(opts, "everyone", false))
        if (SubStr(String(title), 1, 7) = "[TEST] ") {      ; fake events never ping anyone
            wantMention := false
            wantEveryone := false
        }
        shot := String(Webhook._Opt(opts, "screenshot", ""))
        fields := Webhook._Opt(opts, "fields", "")
        buttons := Webhook._Opt(opts, "buttons", "")
        thumb := String(Webhook._Opt(opts, "thumbnail", ""))
        title := Webhook._Decorate(eventType, title)
        for w in hooks {
            mention := wantMention ? Webhook.NormalizeMention(w.Has("mention") ? w["mention"] : "") : ""
            this._Enqueue(w, eventType, title, desc, color, mention, wantEveryone, shot, "", fields, buttons, thumb)
        }
    }

    SendTo(hook, title, desc, color, opts := "") {
        if !(hook is Map)
            throw ValueError("Webhook: SendTo needs a webhook Map")
        ev := String(Webhook._Opt(opts, "event", "direct"))
        done := Webhook._Opt(opts, "done", "")
        this._Enqueue(hook, ev, title, desc, color, "", false, String(Webhook._Opt(opts, "screenshot", "")), done
            , Webhook._Opt(opts, "fields", ""), Webhook._Opt(opts, "buttons", ""), String(Webhook._Opt(opts, "thumbnail", "")))
    }

    Broadcast(title, desc, color, opts := "") {
        n := 0
        ev := String(Webhook._Opt(opts, "event", "broadcast"))
        shot := String(Webhook._Opt(opts, "screenshot", ""))
        for w in this._cfg.Webhooks() {
            if !Webhook._Truthy(w.Has("enabled") ? w["enabled"] : 1)
                continue
            this._Enqueue(w, ev, title, desc, color, "", false, shot, "", Webhook._Opt(opts, "fields", ""))
            n++
        }
        return n
    }

    _Enqueue(w, eventType, title, desc, color, mention, everyone, shot, done, fields := "", buttons := "", thumb := "") {
        if (shot != "" && !FileExist(shot))
            shot := ""
        fileName := shot != "" ? Webhook._BaseName(shot) : ""
        if (thumb != "" && !FileExist(thumb))
            thumb := ""
        thumbName := thumb != "" ? "thumb_" Webhook._BaseName(thumb) : ""
        this._queue.Push({
            name: w.Has("name") ? String(w["name"]) : "",
            url: w.Has("url") ? String(w["url"]) : "",
            event: eventType,
            payload: Webhook._BuildPayload(title, desc, color, mention, fileName, everyone, fields, buttons, thumbName),
            screenshot: shot,
            fileName: fileName,
            thumb: thumb,
            thumbName: thumbName,
            done: done,
            attempts: 0,
            limited: 0,
            notBefore: 0
        })
    }

    ; ---- plain text messages that can be edited (PostText / EditText) ------

    PostText(eventType, content, opts := "") {
        hook := Webhook._Opt(opts, "hook", "")
        if (hook is Map)
            hooks := [hook]
        else
            hooks := this.Route(eventType)
        if (hooks.Length = 0)
            return ""
        h := WebhookText(eventType)
        for w in hooks {
            part := {name: w.Has("name") ? String(w["name"]) : "", url: w.Has("url") ? String(w["url"]) : ""
                , id: "", state: "pending", edit: "", edited: ""}
            h.parts.Push(part)
            this._EnqueueText(part, eventType, content, "")
        }
        return h
    }

    EditText(handle, content) {
        if !(handle is WebhookText)
            return 0
        n := 0
        for part in handle.parts {
            if (part.state = "ok") {
                this._EnqueueText(part, handle.event, content, part.id)
                n++
            } else if (part.state = "pending") {
                part.edit := String(content)        ; sent once the post's id comes
                n++
            }
        }
        return n
    }

    ; msgId "" = the post (?wait=true, the id kept from Discord's answer),
    ; else the PATCH of that message.
    _EnqueueText(part, eventType, content, msgId) {
        this._queue.Push({
            name: part.name,
            url: part.url,
            event: eventType,
            payload: Map("content", SubStr(String(content), 1, 2000), "allowed_mentions", Map("parse", [])),
            screenshot: "", fileName: "", thumb: "", thumbName: "",
            done: ObjBindMethod(this, "_TextDone", part, msgId != ""),
            onOk: msgId = "" ? ObjBindMethod(this, "_TextPosted", part, eventType) : "",
            method: msgId = "" ? "POST" : "PATCH",
            msgId: msgId,
            wait: msgId = "",
            attempts: 0,
            limited: 0,
            notBefore: 0
        })
    }

    ; The post's answer (Discord's message JSON): its id kept, and an edit
    ; asked for meanwhile queued.
    _TextPosted(part, eventType, body) {
        id := Webhook.MessageId(body)
        if (id = "") {
            part.state := "failed", part.edit := ""
            this._Log('Webhook "' part.name '": posted, but Discord gave no message id (it cannot be edited)')
            return
        }
        part.id := id, part.state := "ok"
        if (part.edit != "") {
            c := part.edit, part.edit := ""
            this._EnqueueText(part, eventType, c, id)
        }
    }

    _TextDone(part, isEdit, ok, why) {
        if isEdit {
            part.edited := ok ? 1 : 0
            return
        }
        if (!ok && part.state = "pending")
            part.state := "failed", part.edit := ""
    }

    ; Discord's message JSON -> its id (digits) or "".
    static MessageId(body) {
        try {
            m := Json.Parse(String(body))
            if (m is Map && m.Has("id") && RegExMatch(String(m["id"]), "^\d{1,25}$"))
                return String(m["id"])
        }
        return ""
    }

    ; The URL a queued item goes to: /messages/{id} for an edit (before any
    ; query, a thread_id kept), ?wait=true for a text post, with_components
    ; for buttons.
    static _TargetUrl(item) {
        RegExMatch(item.url, "^([^?]*)(?:\?(.*))?$", &m)
        base := m[1], q := m[2]
        if (item.HasOwnProp("msgId") && item.msgId != "")
            base .= "/messages/" item.msgId
        add := []
        if (item.HasOwnProp("wait") && item.wait)
            add.Push("wait=true")
        if (item.payload.Has("components"))     ; a normal webhook drops components without it
            add.Push("with_components=true")
        for a in add
            q .= (q = "" ? "" : "&") a
        return base (q = "" ? "" : "?" q)
    }

    Pending() {
        return this._queue.Length + this._inflight.Length
    }

    Flush() {
        if !this.dryRun
            this._Poll()
        if (this._queue.Length = 0)
            return
        now := this._Now()
        q := this._queue
        this._queue := []
        for item in q {
            if (item.notBefore > now) {
                this._queue.Push(item)
                continue
            }
            if this.dryRun {
                this.sent.Push({name: item.name, event: item.event
                    , json: Json.Stringify(item.payload, 0), screenshot: item.screenshot, thumb: item.thumb
                    , method: item.HasOwnProp("method") ? item.method : "POST", msgId: item.HasOwnProp("msgId") ? item.msgId : ""})
                if (item.HasOwnProp("onOk") && IsObject(item.onOk))     ; a made-up message id
                    try item.onOk.Call('{"id":"' (900000 + this.sent.Length) '"}')
                Webhook._Done(item, true, "")
            } else if !this._PaceOk(item.url, now)
                this._queue.Push(item)          ; over the URL's rate: next Flush, order kept
            else
                this._Dispatch(item)
        }
    }

    ; True when one more request to url fits: not held by a 429 and fewer
    ; than PacePerWindow dispatches in the last PaceWindowMs.
    _PaceOk(url, now) {
        if (this._blocked.Has(url) && this._blocked[url] > now)
            return false
        if !this._sentAt.Has(url)
            return true
        keep := []
        for t in this._sentAt[url]
            if (now - t < Webhook.PaceWindowMs)
                keep.Push(t)
        this._sentAt[url] := keep
        return keep.Length < Webhook.PacePerWindow
    }

    _PaceNote(url) {
        if !this._sentAt.Has(url)
            this._sentAt[url] := []
        this._sentAt[url].Push(this._Now())
    }

    ; Blocking; only for shutdown so the final Start/Stop message gets out.
    Drain(timeoutMs := 5000) {
        end := this._Now() + timeoutMs
        while (this.Pending() > 0 && this._Now() < end) {
            this.Flush()
            Sleep(50)
        }
    }

    ; ---- payload -----------------------------------------------------------

    static NormalizeMention(raw) {
        s := Trim(String(raw))
        if RegExMatch(s, "^<@&(\d+)>$", &m)
            return "<@&" m[1] ">"
        if RegExMatch(s, "^<@!?(\d+)>$", &m)
            return "<@" m[1] ">"
        if RegExMatch(s, "^@?&(\d+)$", &m)
            return "<@&" m[1] ">"
        if RegExMatch(s, "^@?(\d+)$", &m)
            return "<@" m[1] ">"
        return ""
    }

    ; One embed field. Pass these as opts.fields := [Webhook.Field(...), ...]
    ; (Map or {name, value, inline} objects work too).
    static Field(name, value, inline := true) {
        return Map("name", name, "value", value, "inline", inline ? 1 : 0)
    }

    ; Clear emoji in front of every routed title, by event type. A title that
    ; already starts with an emoji / symbol is left alone; the "[TEST] " tag
    ; stays first.
    static _Decorate(eventType, title) {
        static em := ""
        if !IsObject(em) {
            em := Map("biome", Emoji.Globe, "rare", Emoji.Siren, "merchant", Emoji.Cart, "quests", Emoji.Scroll
                , "craft", Emoji.Alembic, "errors", Emoji.Warn, "startstop", Emoji.Stop, "potions", Emoji.Potion
                , "clips", Emoji.Clapper, "obby", Emoji.Moon, "memorymatch", Emoji.Scroll)
        }
        title := String(title)
        tag := (SubStr(title, 1, 7) = "[TEST] ") ? "[TEST] " : ""
        body := SubStr(title, StrLen(tag) + 1)
        if (!em.Has(eventType) || body = "" || Ord(body) > 0x2000)
            return title
        return tag em[eventType] " " body
    }

    ; fields -> Discord field list: <= 25, name <= 256, value <= 1024, empty ones
    ; dropped, inline as a real JSON boolean.
    static _NormFields(fields) {
        out := []
        if !(fields is Array)
            return out
        for f in fields {
            if (out.Length >= 25)
                break
            name := Trim(String(Webhook._Opt(f, "name", "")))
            value := Trim(String(Webhook._Opt(f, "value", "")))
            if (name = "" || value = "")
                continue
            out.Push(Map("name", SubStr(name, 1, 256), "value", SubStr(value, 1, 1024)
                , "inline", Json.Raw(Webhook._Truthy(Webhook._Opt(f, "inline", false)) ? "true" : "false")))
        }
        return out
    }

    ; buttons -> one action row of link buttons (style 5): <= 5, label <= 80,
    ; https URLs only; bad entries dropped.
    static _NormButtons(buttons) {
        out := []
        if !(buttons is Array)
            return out
        for b in buttons {
            if (out.Length >= 5)
                break
            label := Trim(String(Webhook._Opt(b, "label", "")))
            url := Trim(String(Webhook._Opt(b, "url", "")))
            if (label = "" || !RegExMatch(url, "i)^https://[^\s]+$") || StrLen(url) > 512)
                continue
            out.Push(Map("type", 2, "style", 5, "label", SubStr(label, 1, 80), "url", url))
        }
        return out
    }

    static _BuildPayload(title, desc, color, mention, fileName, everyone := false, fields := "", buttons := "", thumbName := "") {
        try
            c := Integer(color)
        catch
            c := 0xF2A93B
        c := Max(0, Min(0xFFFFFF, c))
        embed := Map(
            "description", SubStr(String(desc), 1, 4096),
            "color", c,
            "timestamp", FormatTime(A_NowUTC, "yyyy-MM-dd'T'HH:mm:ss'Z'"),
            "footer", Map("text", Brand.Footer)
        )
        if (String(title) != "")                ; "" = no title line (biome cards)
            embed["title"] := SubStr(String(title), 1, 256)
        nf := Webhook._NormFields(fields)
        if (nf.Length > 0)
            embed["fields"] := nf
        if (fileName != "")
            embed["image"] := Map("url", "attachment://" fileName)
        if (thumbName != "")
            embed["thumbnail"] := Map("url", "attachment://" thumbName)
        ; No "username": messages keep the name the webhook has in the server.
        payload := Map("embeds", [embed])
        nb := Webhook._NormButtons(buttons)
        if (nb.Length > 0)
            payload["components"] := [Map("type", 1, "components", nb)]
        if everyone {
            payload["content"] := "@everyone" (mention != "" ? " " mention : "")
            am := Map("parse", ["everyone"])
            if (mention != "")
                am[InStr(mention, "&") ? "roles" : "users"] := [RegExReplace(mention, "\D")]
            payload["allowed_mentions"] := am
        } else if (mention != "") {
            payload["content"] := mention
            id := RegExReplace(mention, "\D")
            payload["allowed_mentions"] := InStr(mention, "&")
                ? Map("roles", [id]) : Map("users", [id])
        } else {
            payload["allowed_mentions"] := Map("parse", [])
        }
        return payload
    }

    ; multipart/form-data body -> Buffer. fileBuf is a Buffer with raw PNG bytes.
    static BuildMultipart(jsonText, fileName, fileBuf, boundary)
        => Webhook.BuildMultipartFiles(jsonText, [{name: fileName, buf: fileBuf}], boundary)

    ; Same with several PNGs: files = Array of {name, buf} -> files[0], files[1], ...
    static BuildMultipartFiles(jsonText, files, boundary) {
        crlf := "`r`n"
        parts := []                 ; [header text, Buffer] per file
        head := "--" boundary crlf
            . 'Content-Disposition: form-data; name="payload_json"' crlf
            . "Content-Type: application/json" crlf crlf
            . jsonText
        for i, f in files {
            name := RegExReplace(f.name, '["\r\n\\]', "_")
            parts.Push([(i = 1 ? head : "") crlf "--" boundary crlf
                . 'Content-Disposition: form-data; name="files[' (i - 1) ']"; filename="' name '"' crlf
                . "Content-Type: image/png" crlf crlf, f.buf])
        }
        post := crlf "--" boundary "--" crlf
        if (parts.Length = 0)
            post := head post
        size := StrPut(post, "UTF-8") - 1
        for p in parts
            size += StrPut(p[1], "UTF-8") - 1 + p[2].Size
        body := Buffer(size)
        at := 0
        for p in parts {
            n := StrPut(p[1], "UTF-8") - 1
            StrPut(p[1], body.Ptr + at, n, "UTF-8")
            at += n
            if (p[2].Size > 0)
                DllCall("RtlMoveMemory", "Ptr", body.Ptr + at, "Ptr", p[2].Ptr, "UPtr", p[2].Size)
            at += p[2].Size
        }
        StrPut(post, body.Ptr + at, StrPut(post, "UTF-8") - 1, "UTF-8")
        return body
    }

    static MultipartType(boundary) {
        return "multipart/form-data; boundary=" boundary
    }

    ; ---- transport ---------------------------------------------------------

    _Dispatch(item) {
        if (item.url = "") {
            this._Log('Webhook "' item.name '": no url set, skipped')
            Webhook._Done(item, false, "no webhook URL set")
            return
        }
        if !RegExMatch(item.url, Webhook._UrlRe) {
            this._Log('Webhook "' item.name '": not a Discord webhook url, skipped')
            Webhook._Done(item, false, "not a Discord webhook URL")
            return
        }
        try {
            ctype := "application/json; charset=utf-8"
            files := []
            if (item.screenshot != "") {
                try {
                    fileBuf := FileRead(item.screenshot, "RAW")
                    if (fileBuf.Size > this.maxFileBytes)
                        throw Error("too big")
                    files.Push({name: item.fileName, buf: fileBuf})
                } catch {
                    item.screenshot := ""
                    item.payload["embeds"][1].Delete("image")
                    this._Log('Webhook "' item.name '": screenshot unreadable or too large, sending without')
                }
            }
            if (item.HasOwnProp("thumb") && item.thumb != "") {
                try {
                    tb := FileRead(item.thumb, "RAW")
                    if (tb.Size > this.maxFileBytes)
                        throw Error("too big")
                    files.Push({name: item.thumbName, buf: tb})
                } catch {
                    item.thumb := ""
                    item.payload["embeds"][1].Delete("thumbnail")
                }
            }
            jsonText := Json.Stringify(item.payload, 0)
            if (files.Length > 0) {
                boundary := "----VesperBoundary" A_TickCount Random(100000, 999999)
                body := Webhook.BuildMultipartFiles(jsonText, files, boundary)
                ctype := Webhook.MultipartType(boundary)
            } else {
                body := Buffer(StrPut(jsonText, "UTF-8") - 1)
                StrPut(jsonText, body, body.Size, "UTF-8")
            }
            if (item.HasOwnProp("msgId") && item.msgId != "" && !RegExMatch(item.msgId, "^\d{1,25}$")) {
                Webhook._Done(item, false, "bad message id")
                return
            }
            req := this._NewRequest()
            this._PaceNote(item.url)
            url := Webhook._TargetUrl(item)
            req.Open(item.HasOwnProp("method") ? item.method : "POST", url, true)
            req.SetRequestHeader("Content-Type", ctype)
            req.SetRequestHeader("User-Agent", "VesperMacro/1.0")
            req.Send(Webhook._ToSafeArray(body))
            this._inflight.Push({item: item, req: req, started: this._Now()})
        } catch Any as e {
            this._Fail(item, e is Error ? e.Message : "error")
        }
    }

    _Poll() {
        if (this._inflight.Length = 0)
            return
        keep := []
        for rec in this._inflight {
            item := rec.item
            try {
                if rec.req.WaitForResponse(0) {
                    status := rec.req.Status
                    wait := (status = 429) ? Webhook._RetryAfterMs(rec.req) : 0
                    body := ""               ; a ?wait=true post's answer: the message (its id)
                    if (status >= 200 && status < 300 && item.HasOwnProp("onOk") && IsObject(item.onOk))
                        try body := String(rec.req.ResponseText)
                    rec.req := ""            ; release the COM object
                    if (status = 429) {
                        this._RateLimited(item, wait)
                        continue
                    }
                    if (status >= 200 && status < 300) {
                        if (item.HasOwnProp("onOk") && IsObject(item.onOk))
                            try item.onOk.Call(body)
                        Webhook._Done(item, true, "")
                        continue
                    }
                    if (status = 400 && item.payload.Has("components")) {
                        item.payload.Delete("components")   ; button refused: send it without
                        this._Log('Webhook "' item.name '": Discord refused the link button; sending without it')
                        this._queue.Push(item)
                        continue
                    }
                    this._Fail(item, "HTTP " status)
                    continue
                }
            } catch Any as e {
                rec.req := ""
                this._Fail(item, e is Error ? e.Message : "error")
                continue
            }
            if (this._Now() - rec.started > Webhook._InflightTimeoutMs) {
                try rec.req.Abort()
                rec.req := ""
                this._Fail(item, "timeout")
                continue
            }
            keep.Push(rec)
        }
        this._inflight := keep
    }

    ; HTTP 429: hold every message to this URL for ms and requeue this one
    ; WITHOUT spending an attempt (a rate limit is not a failure); a message
    ; limited more than MaxRateLimited times is given up.
    _RateLimited(item, ms) {
        item.limited++
        if (item.limited > Webhook.MaxRateLimited) {
            this._Log('Webhook "' item.name '": rate limited by Discord ' Webhook.MaxRateLimited ' times, giving up')
            Webhook._Done(item, false, "rate limited (HTTP 429)")
            return
        }
        till := this._Now() + ms
        if (!this._blocked.Has(item.url) || this._blocked[item.url] < till)
            this._blocked[item.url] := till
        item.notBefore := till
        this._queue.Push(item)
        this._Log('Webhook "' item.name '": rate limited by Discord, retrying in ' ms ' ms')
    }

    ; Discord's 429 wait: "retry_after" (seconds, may be fractional) in the
    ; JSON body, else the Retry-After header (seconds). -> ms, 250..60000;
    ; DefaultRetryAfterMs when neither reads.
    static _RetryAfterMs(req) {
        secs := ""
        try {
            if RegExMatch(String(req.ResponseText), '"retry_after"\s*:\s*(\d+(?:\.\d+)?)', &m)
                secs := m[1]
        }
        if (secs = "") {
            try {
                h := Trim(String(req.GetResponseHeader("Retry-After")))
                if RegExMatch(h, "^\d+(?:\.\d+)?$")
                    secs := h
            }
        }
        if (secs = "")
            return Webhook.DefaultRetryAfterMs
        return Max(250, Min(60000, Ceil(Float(secs) * 1000)))
    }

    _Fail(item, why) {
        item.attempts++
        if (item.attempts < 2) {
            item.notBefore := this._Now() + this.retryDelayMs
            this._queue.Push(item)
            this._Log('Webhook "' item.name '": send failed (' why '), will retry')
        } else {
            this._Log('Webhook "' item.name '": send failed (' why '), giving up')
            Webhook._Done(item, false, Webhook.ScrubText(why))
        }
        ; Note: _Fail runs inside Flush's _Poll before the queue snapshot, so a
        ; retry queued here is dispatched in that same Flush once notBefore
        ; has passed.
    }

    _NewRequest() {
        if IsObject(this.httpFactory)
            return this.httpFactory.Call()
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 15000, 15000)   ; resolve, connect, send, receive (ms)
        return req
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

    ; ---- misc --------------------------------------------------------------

    _Log(text) {
        if !IsObject(this._logFn)
            return
        try this._logFn.Call(Webhook.ScrubText(text))
    }

    ; Removes every URL / webhook path from text (logs, UI status).
    static ScrubText(text) {
        text := RegExReplace(String(text), "i)https?://\S*", "[url]")
        return RegExReplace(text, "i)(?:discord(?:app)?\.com)?/api/(?:v\d+/)?webhooks\S*", "[webhook]")
    }

    static _Done(item, ok, why) {
        if !IsObject(item.done)
            return
        try item.done.Call(ok ? 1 : 0, why)
    }

    _Now() {
        return IsObject(this.clock) ? this.clock.Call() : A_TickCount
    }

    static _IsEvent(e) {
        for t in Webhook.EventTypes {
            if (t = e)
                return true
        }
        return false
    }

    static _Truthy(v) {
        if (v is String) {
            v := StrLower(Trim(v))
            return !(v = "" || v = "0" || v = "false" || v = "no" || v = "off")
        }
        return !!v
    }

    static _Opt(opts, key, default) {
        if (opts is Map)
            return opts.Has(key) ? opts[key] : default
        if IsObject(opts)
            return opts.HasProp(key) ? opts.%key% : default
        return default
    }

    static _BaseName(path) {
        SplitPath(path, &name)
        return RegExReplace(name, '[^\w.\-]', "_")
    }
}

; Handle of one PostText message: one part per webhook entry it went to
; (name, url, id, state, edited; Webhook keeps them up to date). Never
; logged (url).
class WebhookText {
    __New(event) {
        this.event := event
        this.parts := []
    }

    ; message ids by webhook name (posted parts only)
    Ids() {
        m := Map()
        for p in this.parts
            if (p.state = "ok")
                m[p.name] := p.id
        return m
    }

    ; true while a part's post has no answer yet
    Waiting() {
        for p in this.parts
            if (p.state = "pending")
                return true
        return false
    }
}
