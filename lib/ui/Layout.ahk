#Requires AutoHotkey v2.0
; Layout: the pure rules for placing a dashboard card (2026-11-18 themes +
; layout design, spec 2). Every number is in 100 % units. A rect is
; {x, y, w, h}; a layout entry is [x, y, w, h, hidden]. Nothing here touches
; a control (Dashboard.ApplyLayout does), and nothing throws on bad input.
;
;   Layout.Grid                the drag grid, 8
;   Layout.Snap(n)             n rounded to the grid
;   Layout.MinSize(card)       {w, h}: the card's controls' box (from the
;                              frame's corner) + 12
;   Layout.Clamp(rect, area, least := "")
;                              a rect inside the area; the size is kept when
;                              it fits (never below least), else cut down to
;                              the area, then the place is moved inside
;   Layout.Overlaps(rects)     rects: Map id -> rect (or Array of rects with
;                              an id) -> Array of [idA, idB] sharing pixels
;                              (touching edges do not count)
;   Layout.Place(card, entry, area)
;                              {dx, dy, w, h, hidden} that takes the card
;                              (from Dashboard.Cards) to its entry, clamped
;                              to the area; "" for an entry that is no good
class Layout {
    static Grid := 8
    static Pad := 12

    static Snap(n) {
        try return Round(n / Layout.Grid) * Layout.Grid
        return 0
    }

    static MinSize(card) {
        w := 0, h := 0
        try {
            f := Theme.Pos(card.frame)
            for c in card.ctrls {
                if (c = card.frame || c = card.fill)
                    continue
                p := Theme.Pos(c)
                w := Max(w, p.x + p.w - f.x)
                h := Max(h, p.y + p.h - f.y)
            }
        }
        return {w: w + Layout.Pad, h: h + Layout.Pad}
    }

    static Clamp(rect, area, least := "") {
        mw := IsObject(least) ? least.w : 1
        mh := IsObject(least) ? least.h : 1
        w := Min(Max(rect.w, mw), Max(area.w, 1))
        h := Min(Max(rect.h, mh), Max(area.h, 1))
        x := Min(Max(rect.x, area.x), area.x + area.w - w)
        y := Min(Max(rect.y, area.y), area.y + area.h - h)
        return {x: x, y: y, w: w, h: h}
    }

    static Overlaps(rects) {
        items := []
        if (rects is Map) {
            for id, r in rects
                items.Push([id, r])
        } else if (rects is Array) {
            for r in rects
                items.Push([r.id, r])
        }
        out := []
        for i, a in items {
            Loop items.Length - i {
                b := items[i + A_Index]
                ra := a[2], rb := b[2]
                if (ra.x < rb.x + rb.w && rb.x < ra.x + ra.w && ra.y < rb.y + rb.h && rb.y < ra.y + ra.h)
                    out.Push([a[1], b[1]])
            }
        }
        return out
    }

    static Place(card, entry, area) {
        try {
            if !(entry is Array) || entry.Length < 4
                return ""
            v := []
            Loop 4 {
                if !IsNumber(entry[A_Index])
                    return ""
                v.Push(Round(Number(entry[A_Index])))
            }
            r := Layout.Clamp({x: v[1], y: v[2], w: v[3], h: v[4]}, area, Layout.MinSize(card))
            hid := (entry.Length >= 5 && IsNumber(entry[5]) && Number(entry[5])) ? 1 : 0
            return {dx: r.x - card.x, dy: r.y - card.y, w: r.w, h: r.h, hidden: hid}
        }
        return ""
    }
}
