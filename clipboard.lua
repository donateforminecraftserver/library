clipboard = {}
local ffi = require("ffi")
ffi.cdef[[
    typedef int(__thiscall* get_clipboard_text_count)(void*);
    typedef void(__thiscall* get_clipboard_text)(void*, int, const char*, int);
    typedef void(__thiscall* set_clipboard_text)(void*, const char*, int);
]]

local VGUI_Systemdll =  Utils.CreateInterface("vgui2.dll", "VGUI_System010")
local VGUI_System = ffi.cast(ffi.typeof('void***'), VGUI_Systemdll)
local get_clipboard_text_count = ffi.cast( "get_clipboard_text_count", VGUI_System[ 0 ][ 7 ] )
local get_clipboard_text = ffi.cast( "get_clipboard_text", VGUI_System[ 0 ][ 11 ] )
local set_clipboard_text = ffi.cast( "set_clipboard_text", VGUI_System[ 0 ][ 9 ] )

function clipboard.set(string)
    if string then
        set_clipboard_text(VGUI_System, string, string:len())
    end
end

function clipboard.get()
    local clipboard_text_length = get_clipboard_text_count( VGUI_System )
    local clipboardstring = ""
    if clipboard_text_length > 0 then
        buffer = ffi.new("char[?]", clipboard_text_length)
        size = clipboard_text_length * ffi.sizeof("char[?]", clipboard_text_length)
        get_clipboard_text( VGUI_System, 0, buffer, size )
        clipboardstring = ffi.string( buffer, clipboard_text_length-1 )
    end
    return clipboardstring
end

return clipboard
