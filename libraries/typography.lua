-- X-TOOLS | Project and integration: Casual_Alvarez | Module: typography.lua
-- Original third-party credits, where present, are retained below.
-- One font atlas extension for the workspace and observation HUD.
-- Keep glyph ranges alive until ImGui finishes rebuilding the atlas.
local Typography = {}
Typography.__index = Typography
Typography.sizes = {12,13,14,16,18,20,22,24,28,32,36}

Typography.faces={
    {'Segoe UI','segoeui.ttf','seguisb.ttf'}, {'Arial','arial.ttf','arialbd.ttf'},
    {'Tahoma','tahoma.ttf','tahomabd.ttf'}, {'Verdana','verdana.ttf','verdanab.ttf'},
    {'Calibri','calibri.ttf','calibrib.ttf'}, {'Trebuchet MS','trebuc.ttf','trebucbd.ttf'},
    {'Consolas','consola.ttf','consolab.ttf'}, {'Georgia','georgia.ttf','georgiab.ttf'},
    {'Manrope','Manrope-Regular.ttf','Manrope-Bold.ttf',bundled=true},
    {'Exo 2','Exo2-Regular.ttf','Exo2-Bold.ttf',bundled=true},
    {'IBM Plex Sans','IBMPlexSans-Regular.ttf','IBMPlexSans-Bold.ttf',bundled=true}
}
function Typography:paths(preference)
    local face=Typography.faces[preference] or Typography.faces[1]
    local folder=face.bundled and (self.base..'/fonts') or
        (self.api.getFolderPath and self.api.getFolderPath(0x14))
    local separator=face.bundled and '/' or '\\'
    return folder and (folder..separator..face[2]),folder and (folder..separator..face[3])
end
function Typography:choices()
    if self.choiceLabels then return self.choiceLabels end
    local names={}
    for i,face in ipairs(Typography.faces) do
        local normal=self:paths(i)
        local available=normal and self.api.doesFileExist(normal)
        names[#names+1]=face[1]..(available and '' or ' (резервный)')
    end
    self.choiceLabels=table.concat(names,'\0')..'\0\0'
    return self.choiceLabels
end

function Typography.new(base,api)
    return setmetatable({base=base,api=api,regular={},bold={},cache={},scale=1},Typography)
end

-- Called from BeforeDrawFrame, while the atlas is unlocked. Never call from get().
-- Each bounded face/scale pair is added once; cached fonts share the same context.
function Typography:load(imgui)
    local preference=tonumber(self.preference) or 1
    if not Typography.faces[preference] then preference=1 end
    local scale=tonumber(self.scale) or 1
    if scale~=1 and scale~=1.25 and scale~=1.5 then scale=1 end
    local key=tostring(preference)..':'..tostring(scale)
    if self.loadedKey and self.loadedKey~=key then
        self.restartRequired=true
        return true
    end
    self.restartRequired=false
    if self.loadedKey==key then self.failed,self.failedKey=nil,nil;return true end
    if self.failedEntries and self.failedEntries[key] then
        self.failed,self.failedKey=self.failedEntries[key].error,key
        return false
    end
    local cached=self.cache[key]
    if cached then
        self.regular,self.bold=cached.regular,cached.bold
        self.builder,self.ranges=cached.builder,cached.ranges
        self.loadedPreference,self.loadedScale=preference,scale
        self.loadedKey,self.loaded=key,true
        self.failed,self.failedKey=nil,nil
        return true
    end
    local io = imgui.GetIO()
    if not io or not io.Fonts or not io.Fonts.AddFontFromFileTTF then return false end
    local entry={regular={},bold={}}
    local ok,err = pcall(function()
        -- Keep the native builder/ranges with the cache entry for the atlas lifetime.
        entry.builder = imgui.ImFontAtlasGlyphRangesBuilder()
        entry.builder:AddRanges(io.Fonts:GetGlyphRangesCyrillic())
        entry.builder:AddText('‚„…†‡€‰‹‘’“”•–—™›№←↑→↓')
        entry.ranges = entry.builder:BuildRanges()
        local normal,bold=self:paths(preference)
        if not normal or not self.api.doesFileExist(normal) then normal=self.base..'/fonts/EagleSans.ttf' end
        if not bold or not self.api.doesFileExist(bold) then bold=normal end
        for _,size in ipairs(Typography.sizes) do
            entry.regular[size]=assert(io.Fonts:AddFontFromFileTTF(normal,size*scale,nil,entry.ranges))
            entry.bold[size]=assert(io.Fonts:AddFontFromFileTTF(bold,size*scale,nil,entry.ranges))
        end
        imgui.RebuildFonts()
    end)
    if not ok then
        -- Keep ranges alive even after a partial atlas addition and preserve working fonts.
        self.failedEntries=self.failedEntries or {}
        entry.error=tostring(err)
        self.failedEntries[key]=entry
        self.failed,self.failedKey=tostring(err),key
        return false
    end
    self.cache[key]=entry
    self.regular,self.bold=entry.regular,entry.bold
    self.builder,self.ranges=entry.builder,entry.ranges
    self.loadedPreference,self.loadedScale=preference,scale
    self.loadedKey,self.loaded=key,true
    self.failed,self.failedKey=nil,nil
    return true
end

function Typography:get(size,bold)
    return (bold and self.bold or self.regular)[size]
end

return Typography
