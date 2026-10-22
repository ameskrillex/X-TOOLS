-- X-TOOLS | Project and integration: Casual_Alvarez | Module: native_fonts.lua
-- Original third-party credits, where present, are retained below.
local Fonts={}
Fonts.__index=Fonts
local faces={'Segoe UI','Arial','Tahoma'}
function Fonts.new(api,preferences) return setmetatable({api=api,preferences=preferences,sessionFont=preferences.data.main.font,entries={}},Fonts) end
function Fonts:create(requested,size,flags,preserveFace)
    local face=preserveFace and requested or faces[self.sessionFont] or faces[1]
    local font=self.api.renderCreateFont(face,size,flags)
    if font then self.entries[font]={size=size,flags=flags,face=face,current=font,fixed=preserveFace} end
    return font
end
function Fonts:resolve(font)
    local entry=self.entries[font];if not entry then return font end
    local face=entry.fixed and entry.face or faces[self.sessionFont] or faces[1]
    if entry.face~=face then
        local replacement=self.api.renderCreateFont(face,entry.size,entry.flags)
        if replacement then
            if entry.current~=font then self.api.renderReleaseFont(entry.current) end
            entry.current,entry.face=replacement,face
        end
    end
    return entry.current
end
function Fonts:release(font)
    local entry=self.entries[font]
    if entry and entry.current~=font then self.api.renderReleaseFont(entry.current) end
    self.entries[font]=nil
    return self.api.renderReleaseFont(font)
end
function Fonts:draw(font,text,...)
    if self.api.isGameWindowForeground and not self.api.isGameWindowForeground() then return end
    if self.api.isPauseMenuActive and self.api.isPauseMenuActive() then return end
    local u8=self.api.require('encoding').UTF8
    return self.api.renderFontDrawText(self:resolve(font),u8:decode(self.preferences:mask(tostring(u8(text or '')))),...)
end
function Fonts:width(font,text,...)
    local u8=self.api.require('encoding').UTF8
    return self.api.renderGetFontDrawTextLength(self:resolve(font),u8:decode(self.preferences:mask(tostring(u8(text or '')))),...)
end
function Fonts:height(font,...) return self.api.renderGetFontDrawHeight(self:resolve(font),...) end
return Fonts
