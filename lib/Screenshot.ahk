#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Window screenshot via GDI + GDI+ (own DllCalls, no third-party library).
;
;   path := Screenshot.Capture(hwnd)
;     Copies the window rectangle (GetWindowRect) from the screen DC and
;     saves it as PNG to A_Temp\vesper_shot_<timestamp>.png.
;     Returns the path, or "" on ANY failure (bad/minimised window, GDI+
;     error). Never throws.
;   Screenshot.Cleanup(maxAgeHours := 24)
;     Deletes old vesper_shot_*.png files from A_Temp.
;
; Note: it grabs what is on screen, so the window must be visible and not
; covered. Live capture is a manual check (needs a real window).
; ---------------------------------------------------------------------------

class Screenshot {
    static Capture(hwnd) {
        try
            return Screenshot._Capture(hwnd)
        catch
            return ""
    }

    static Cleanup(maxAgeHours := 24) {
        cutoff := DateAdd(A_Now, -Integer(maxAgeHours), "Hours")
        try {
            Loop Files, A_Temp "\vesper_shot_*.png" {
                if (A_LoopFileTimeModified < cutoff)
                    try FileDelete(A_LoopFilePath)
            }
        }
    }

    static _Capture(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return ""
        if DllCall("IsIconic", "Ptr", hwnd, "Int")
            return ""
        rc := Buffer(16, 0)
        if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc, "Int")
            return ""
        x := NumGet(rc, 0, "Int"), y := NumGet(rc, 4, "Int")
        w := NumGet(rc, 8, "Int") - x, h := NumGet(rc, 12, "Int") - y
        if (w < 1 || h < 1)
            return ""

        path := A_Temp "\vesper_shot_" FormatTime(, "yyyyMMdd_HHmmss") "_" A_MSec ".png"

        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        token := 0
        hdcScreen := 0, hdcMem := 0, hbm := 0, hbmOld := 0, pBitmap := 0
        ok := false
        try {
            si := Buffer(3 * A_PtrSize, 0)
            NumPut("UInt", 1, si, 0)   ; GdiplusVersion
            if DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0, "Int")
                return ""

            hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
            hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
            if (!hdcScreen || !hdcMem || !hbm)
                return ""
            hbmOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
            ; SRCCOPY | CAPTUREBLT
            if !DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h
                , "Ptr", hdcScreen, "Int", x, "Int", y, "UInt", 0x40CC0020, "Int")
                return ""
            DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbmOld, "Ptr")
            hbmOld := 0

            if DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBitmap, "Int")
                return ""
            clsid := Buffer(16, 0)   ; PNG encoder {557CF406-1A04-11D3-9A73-0000F81EF32E}
            DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
            if DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", path, "Ptr", clsid, "Ptr", 0, "Int")
                return ""
            ok := true
        } finally {
            if pBitmap
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
            if (hdcMem && hbmOld)
                DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbmOld, "Ptr")
            if hbm
                DllCall("DeleteObject", "Ptr", hbm)
            if hdcMem
                DllCall("DeleteDC", "Ptr", hdcMem)
            if hdcScreen
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
            if token
                DllCall("gdiplus\GdiplusShutdown", "Ptr", token)
        }
        return (ok && FileExist(path)) ? path : ""
    }
}
