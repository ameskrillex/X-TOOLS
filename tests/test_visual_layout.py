"""Exercise the bundled Lua geometry, preference migration and ImGui image calls."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-deps'))
from lupa.luajit21 import LuaRuntime

CODE = (ROOT / 'X-TOOL.lua').read_text(encoding='utf-8')


def module(name):
    marker = '    sources["' + name + '"] = function()\n'
    start = CODE.index(marker) + len(marker)
    return CODE[start:CODE.index('\n    end\n    sources[', start)]


class VisualLayoutTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        for name, file in [('geometry', 'window_geometry.lua'), ('Preferences', 'preferences.lua'),
                           ('art', 'legends_art.lua'), ('Workspace', 'workspace.lua')]:
            self.lua.globals()[name] = self.lua.execute(module(file))
        self.lua.execute('''
            storage={path=function()return 'interface.ini' end,
                loadIni=function(_,defaults)return input or defaults end,
                saveIni=function(_,data)saved=data;return true end}
            function preferences(data)input=data;return Preferences.new(storage)end
        ''')

    def test_existing_manual_size_migrates_once_without_resetting_theme(self):
        self.lua.execute('''
            pref=preferences({main={windowWidth=900,windowHeight=600,windowX=33,windowY=22,
                windowManual=true,themeStyle=4,font=3,families=true}})
            local p=pref.data.main
            assert(p.windowPresetVersion==1 and pref.windowPresetPending)
            assert(not p.windowManual and not p.windowMoved and p.windowWidth==0)
            assert(p.themeStyle==4 and p.font==3 and p.families)
            local w,h=geometry.resolve(p,1920,1080);assert(w==1493 and h==1047)
            p.windowWidth=1200;p.windowHeight=800;p.windowManual=true;p.windowX=12;p.windowY=31
            pref:save();pref=preferences(saved)
            w,h,x,y=geometry.resolve(pref.data.main,1920,1080)
            assert(w==1200 and h==800 and x==12 and y==31)
            assert(not pref.windowPresetPending)
        ''')

    def test_new_defaults_center_and_fit_all_supported_resolutions(self):
        self.lua.execute('''
            pref=preferences();local p=pref.data.main
            for _,screen in ipairs({{3840,2160},{2560,1440},{1920,1080},{1600,900},
                                     {1366,768},{1280,720},{800,600},{640,480}})do
                local sw,sh=unpack(screen);local w,h,x,y=geometry.resolve(p,sw,sh)
                assert(w==math.min(1493,sw-24) and h==math.min(1047,sh-32))
                assert(x==(sw-w)/2 and y==(sh-h)/2)
                assert(x>=0 and y>=0 and x+w<=sw and y+h<=sh)
                p.windowWidth,p.windowHeight,p.windowX,p.windowY=w,h,x,y
            end
            local w,h=geometry.resolve(p,1920,1080)
            assert(w==1493 and h==1047, 'Clamped automatic size must recover on a larger screen')
        ''')

    def test_moved_window_keeps_position_and_clamps_off_screen(self):
        self.lua.execute('''
            local p={windowMoved=true,windowX=200,windowY=100}
            local w,h,x,y=geometry.resolve(p,2560,1440)
            assert(w==1493 and h==1047 and x==200 and y==100)
            p.windowManual=true;p.windowWidth=1900;p.windowHeight=1300;p.windowX=2100;p.windowY=1400
            w,h,x,y=geometry.resolve(p,1280,720)
            assert(w==1256 and h==688 and x==24 and y==32)
        ''')

    def test_workspace_applies_migration_ignores_stale_imgui_and_preserves_user_resize(self):
        self.lua.execute('''
            screen={1920,1080};size={x=700,y=500};pos={x=700,y=300};clock=0
            g={ImVec2=function(x,y)return {x=x,y=y}end,Cond={Always=1,FirstUseEver=2},
                WindowFlags={NoTitleBar=1,NoScrollbar=2,NoScrollWithMouse=4},
                SetNextWindowSize=function(v,cond)sizeCondition=cond;if cond==1 then size=v end end,
                SetNextWindowPos=function(v,cond)if cond==1 then pos=v end end,
                SetNextWindowSizeConstraints=function()end,Begin=function()end,
                GetWindowSize=function()return size end,GetWindowPos=function()return pos end,
                SetWindowFontScale=function()error('GEOMETRY_DONE')end}
            rt={imgui=g,preferences=preferences({main={windowWidth=700,windowHeight=500,windowManual=true}}),
                theme={palette={},apply=function()end,push=function()return 0,0 end},
                api={getScreenResolution=function()return unpack(screen)end,os={clock=function()return clock end}},
                service=function(_,name)assert(name=='window_geometry.lua');return geometry end}
            function frame(page)
                rt.page=page or 'home';clock=clock+1
                local ok,err=pcall(Workspace.draw,rt,function()end)
                assert(not ok and tostring(err):find('GEOMETRY_DONE',1,true),tostring(err))
            end
            frame();assert(size.x==1493 and size.y==1047 and sizeCondition==1)
            assert(not rt.preferences.data.main.windowManual)
            size={x=1200,y=800};pos={x=100,y=80};frame('familia')
            assert(sizeCondition==2 and rt.preferences.data.main.windowManual and rt.preferences.data.main.windowMoved)
            frame('core');assert(size.x==1200 and size.y==800 and pos.x==100 and pos.y==80)
            assert(saved.main.windowWidth==1200)
            screen={800,600};frame();assert(size.x==776 and size.y==568)
            assert(pos.x>=0 and pos.x+size.x<=800 and pos.y+size.y<=600)
        ''')

    def test_screen_resize_does_not_turn_automatic_geometry_into_manual(self):
        self.test_workspace_applies_migration_ignores_stale_imgui_and_preserves_user_resize()
        self.lua.execute('''
            rt.preferences=preferences();screen={1280,720};frame()
            assert(size.x==1256 and size.y==688 and not rt.preferences.data.main.windowManual)
            screen={1920,1080};frame()
            assert(size.x==1493 and size.y==1047 and not rt.preferences.data.main.windowManual)
            assert(not rt.preferences.data.main.windowMoved)
        ''')

    def test_all_theme_tints_and_crop_preserve_image_proportions(self):
        self.lua.execute('''
            g={ImVec2=function(x,y)return {x=x,y=y}end,
               ImVec4=function(r,g,b,a)return {r=r,g=g,b=b,a=a}end,GetColorU32=function(c)return c end}
            calls=0;draw={AddImage=function(_,texture,first,last,uv0,uv1,tint)
                calls=calls+1;call={texture=texture,first=first,last=last,uv0=uv0,uv1=uv1,tint=tint}
            end}
            image={texture=77,width=2172,height=724}
            for _,color in ipairs(Preferences.colors)do
                for _,rect in ipairs({{558,186},{230,94},{900,160},{300,240},{80,94}})do
                    local w,h=unpack(rect)
                    art.draw(g,draw,image,g.ImVec2(11,17),g.ImVec2(11+w,17+h),color[2],.92)
                    local c=call.tint
                    assert(math.floor(c.r*255+.5)*65536+math.floor(c.g*255+.5)*256+math.floor(c.b*255+.5)==color[2])
                    assert(c.a==.92 and call.texture==77)
                    local u,v=call.uv1.x-call.uv0.x,call.uv1.y-call.uv0.y
                    assert(math.abs((2172*u)/(724*v)-w/h)<.000001)
                    assert(call.uv0.x>=0 and call.uv0.y>=0 and call.uv1.x<=1 and call.uv1.y<=1)
                end
            end
            local before=calls
            art.draw(g,draw,image,g.ImVec2(0,0),g.ImVec2(0,10),0xffffff,1)
            assert(calls==before)
        ''')

    def test_both_surfaces_use_shared_tint_renderer(self):
        self.lua.globals().browserCode = module('modules/legends_browser.lua')
        self.lua.globals().theme = self.lua.execute(module('theme.lua'))
        self.lua.execute('''
            local function upvalue(fn,name)
                for i=1,100 do local key,value=debug.getupvalue(fn,i)
                    if key==name then return value end;if not key then break end end
                error('Missing upvalue '..name)
            end
            image={texture=77,width=2172,height=724}
            draw={AddImage=function(_,texture,a,b,uv0,uv1,tint)
                rendered={texture=texture,a=a,b=b,tint=tint}
            end}
            g={ImVec2=function(x,y)return {x=x,y=y}end,ImVec4=function(r,g,b,a)return {r=r,g=g,b=b,a=a}end,
                GetColorU32=function(c)return c end,GetWindowPos=function()return {x=10,y=20}end,
                GetScrollX=function()return 0 end,GetScrollY=function()return 0 end,
                GetWindowDrawList=function()return draw end,SetCursorPos=function()end,
                InvisibleButton=function()return false end,IsItemHovered=function()return false end,
                CalcTextSize=function()return {x=50,y=16}end,TextColored=function()end,
                GetContentRegionAvailWidth=function()return 558 end,
                ImBool=function(v)return {v=v}end,ImInt=function(v)return {v=v}end,ImBuffer=function(v)return {v=v}end}
            local cache={get=function()return image end}
            local services={['legends_art.lua']=art,['ui_components.lua']={wrap=function(_,text)return text end},
                ['art.lua']={new=function()return cache end},['legends_server.lua']={},
                ['dossier_ui.lua']={new=function()return {
                    cursor=function()return {x=0,y=0}end,measure=function()return 16 end,
                    rect=function()end,text=function()return 16 end,finish=function()end}end}}
            rt={imgui=g,theme=theme,preferences=preferences(),art=cache,
                typography={get=function()end},service=function(_,name)return assert(services[name],name)end}
            local ui=upvalue(Workspace.draw,'painter')(rt)
            package.preload.imgui=function()return g end
            integration={service=function(name)return assert(services[name],name)end,palette=theme.palette}
            assert(loadstring(browserCode))()
            local header=upvalue(integration.drawHud,'header')
            for _,color in ipairs({0x59DFFF,0xFFAB51,0x62E9AB,0xFF6086,0xAA91FF,0xC080FF})do
                theme.apply(color)
                for _,paint in ipairs({function()ui.legendsButton('test',0,0,558,function()end)end,header})do
                    paint()
                    assert(rendered.texture==77 and rendered.b.x-rendered.a.x==558 and rendered.b.y-rendered.a.y==186)
                    local c=rendered.tint
                    assert(math.floor(c.r*255+.5)*65536+math.floor(c.g*255+.5)*256+math.floor(c.b*255+.5)==color)
                end
            end
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
