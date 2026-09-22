"""Run with Python + lupa (LuaJIT 2.1). No game or network access required."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-deps'))
from lupa.luajit21 import LuaRuntime

CODE = (ROOT / 'X-TOOL.lua').read_text(encoding='utf-8')


def module(name, code=CODE):
    start = code.index('    sources["' + name + '"] = function()\n')
    start = code.index('\n', start) + 1
    return code[start:code.index('\n    end\n    sources[', start)]


class HotfixTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)

    def updates(self, scenario='new'):
        self.lua.globals().Updates = self.lua.execute(module('updates.lua'))
        self.lua.globals().scenario = scenario
        self.lua.execute('''
            local function hash(bytes)
                local n=0
                for i=1,#bytes do n=(n*31+bytes:byte(i))%2147483647 end
                return string.format('%064x',n)
            end
            local resource='fixture resource'
            local pack='CTAS1\\n'..resource
            local resourceHash=hash(resource)
            local packHash=hash(pack)
            local id=hash('test.txt\\0'..#resource..'\\0'..resourceHash..'\\n'..packHash)
            local target=scenario=='current' and '3.5.170' or (scenario=='older' and '3.5.169' or '3.5.171')
            newCode='-- CasualTool release: '..target..'\\n-- CasualTool assets: '..id..'\\nreturn true\\n'
            oldCode='-- CasualTool release: 3.5.170\\nreturn true\\n'
            manifest={schema=1,product='CasualTool',version=target,packagePath='versions/'..target..'/',
                script={file='X-TOOL.lua',bytes=#newCode,sha256=hash(newCode)},
                assets={file='assets.pack',bytes=#pack,sha256=packHash,id=id,
                    files={{path='test.txt',offset=6,bytes=#resource,sha256=resourceHash}}}}
            if scenario=='bad_manifest' then manifest.assets.files[1].path='../escape.txt' end
            queue,messages,requests,writes={}, {}, {}, {}
            disk={['game/X-TOOL.lua']=oldCode,['game/X-TOOL/settings/user.ini']='keep me'}
            reloads=0
            api={
                hash=hash, decode=function() return manifest end,
                read=function(path) return disk[path] end,
                write=function(path,bytes) disk[path]=bytes; writes[#writes+1]=path; return true end,
                ensure=function() return true end,
                remove=function(path) disk[path]=nil; return true end,
                rename=function(a,b)
                    if scenario=='commit_failure' and a:match('update%-new$') then return false end
                    if not disk[a] then return false end
                    disk[b]=disk[a];disk[a]=nil;return true
                end,
                compile=loadstring,
                reload=function() reloads=reloads+1;return true end,
                message=function(s) messages[#messages+1]=s end,
                run=function(fn) queue[#queue+1]=fn end,
                fetch=function(url)
                    requests[#requests+1]=url
                    if scenario=='network_error' then error('HTTPS timeout') end
                    if url:match('manifest.json$') then return '{}' end
                    if url:match('X%-TOOL.lua$') then
                        return scenario=='bad_code' and newCode..'corrupt' or newCode
                    end
                    return scenario=='bad_pack' and pack..'corrupt' or pack
                end
            }
            updater=Updates.new(api,{path='game/X-TOOL.lua',version='3.5.170'},
                {bundled=true,updateUrl='https://example.test/update/manifest.json'})
            function drain()
                local steps=0
                while #queue>0 do
                    steps=steps+1;assert(steps<10,'recursive jobs')
                    table.remove(queue,1)()
                end
            end
        ''')
        return self.lua.globals().updater

    def run_lua(self, code):
        self.lua.execute(code)

    def test_bundle_compiles_in_luajit(self):
        compile_code = self.lua.eval('function(code) local f,e=loadstring(code); assert(f,e); return true end')
        self.assertTrue(compile_code(CODE))

    def test_manifest_and_pack_integrity(self):
        manifest = json.loads((ROOT / 'update/live/manifest.json').read_text())
        release = ROOT / 'update/live' / manifest['packagePath']
        for descriptor in (manifest['script'], manifest['assets']):
            payload = (release / descriptor['file']).read_bytes()
            self.assertEqual(len(payload), descriptor['bytes'])
            self.assertEqual(hashlib.sha256(payload).hexdigest(), descriptor['sha256'])
        self.assertEqual((release / 'X-TOOL.lua').read_bytes(), (ROOT / 'X-TOOL.lua').read_bytes())
        pack = (release / 'assets.pack').read_bytes()
        self.assertEqual(pack[:6], b'CTAS1\n')
        identity = b''
        for file in manifest['assets']['files']:
            data = pack[file['offset']:file['offset']+file['bytes']]
            self.assertEqual(hashlib.sha256(data).hexdigest(), file['sha256'])
            identity += f"{file['path']}\0{file['bytes']}\0{file['sha256']}\n".encode()
        self.assertEqual(hashlib.sha256(identity + manifest['assets']['sha256'].encode()).hexdigest(), manifest['assets']['id'])

    def test_update_installs_backs_up_preserves_settings_and_reloads(self):
        self.updates()
        self.run_lua('''
            updater:update(); assert(updater.busy and updater.state=='checking')
            drain()
            assert(disk['game/X-TOOL.lua']==newCode)
            assert(disk['game/X-TOOL.lua.bak']==oldCode)
            assert(disk['game/X-TOOL/settings/user.ini']=='keep me')
            assert(reloads==1 and updater.awaitingReload and not updater.busy)
            assert(#requests==3)
        ''')

    def test_up_to_date_does_not_install(self):
        self.updates('current')
        self.run_lua("updater:update();drain();assert(updater.state=='current' and #writes==0 and reloads==0)")

    def test_older_manifest_does_not_downgrade(self):
        self.updates('older')
        self.run_lua("updater:update();drain();assert(#writes==0 and reloads==0)")

    def test_check_only_keeps_manual_install(self):
        for manual in ('true', 'false'):
            with self.subTest(manual=manual):
                self.updates()
                self.run_lua(f"updater:check({manual});drain();assert(updater.state=='available' and #writes==0 and reloads==0)")

    def test_double_command_does_not_duplicate_jobs(self):
        self.updates()
        self.run_lua("updater:update();assert(updater:update()==false);assert(#queue==1);drain();assert(reloads==1)")

    def test_command_during_startup_check_can_be_retried(self):
        self.updates()
        self.run_lua("updater:start();assert(updater:update()==false);drain();assert(#writes==0);updater:update();drain();assert(reloads==1)")

    def test_failures_preserve_installed_code(self):
        for scenario in ('network_error','bad_manifest','bad_code','bad_pack','commit_failure'):
            with self.subTest(scenario=scenario):
                self.updates(scenario)
                self.run_lua("updater:update();drain();assert(updater.state=='error' and not updater.busy);assert(disk['game/X-TOOL.lua']==oldCode and reloads==0)")

    def test_failure_does_not_trigger_later_unrequested_install(self):
        self.updates('network_error')
        self.run_lua("updater:update();drain();scenario='new';updater:check(true);drain();assert(updater.state=='available' and #writes==0)")

    def test_stop_cancels_queued_update(self):
        self.updates()
        self.run_lua("updater:update();updater:stop();drain();assert(updater.state=='stopped' and #writes==0);assert(updater:update()==false)")

    def test_retry_reload_does_not_reinstall(self):
        self.updates()
        self.run_lua("updater:update();drain();local count=#requests;updater:update();assert(reloads==2 and #requests==count)")

    def test_update_registration_defers_and_coalesces_until_runtime_tick(self):
        runtime = self.lua.execute(module('runtime.lua'))
        self.lua.globals().Runtime = runtime
        # Exercise the real registration expression and real Runtime:register wrapper.
        line = next(line.strip() for line in module('runtime.lua').splitlines() if "'update', function()" in line)
        self.lua.execute('''
            called=0;registered={}
            rt=setmetatable({commands={},updates={update=function() called=called+1 end},
                api={sampRegisterChatCommand=function(name,fn)registered[name]=fn;return true end}}, {__index=Runtime})
            function rt:component()return {id='integration',enabled=true}end
            function rt:commandAllowed()return true end
            function rt:featureAllowed()return true end
            function rt:call(m,fn,...)return fn(...)end
            function rt:open()error('Command must not open the broken GUI')end
        ''')
        self.lua.execute('local self=rt;'+line+''';
            registered.update();registered.update();assert(called==0)
            rt:processUpdateCommand();assert(called==1)
            rt:processUpdateCommand();assert(called==1)
            registered.update();rt.stopped=true
            rt:processUpdateCommand();assert(called==1 and not rt.updateCommandPending)
        ''')
        self.assertIn('self.api.wait(0)\n            self:processUpdateCommand()', module('runtime.lua'))

    def test_command_uses_checked_release_without_second_manifest_request(self):
        self.updates()
        self.run_lua('''
            updater:start();drain();assert(#requests==1)
            local checked=updater.pending
            updater:update();assert(updater.state=='installing' and updater.pending==checked)
            drain();assert(#requests==3 and reloads==1 and disk['game/X-TOOL.lua']==newCode)
        ''')

    def test_command_and_menu_install_make_the_same_requests_and_writes(self):
        snapshots=[]
        for action in ('update', 'install'):
            self.updates()
            self.run_lua('updater:start();drain();updater:'+action+'();drain()')
            g=self.lua.globals()
            snapshots.append((list(g.requests.values()), list(g.writes.values()), dict(g.disk.items()), g.reloads))
        self.assertEqual(*snapshots)

    def test_cached_release_still_rejects_corrupt_download(self):
        self.updates()
        self.run_lua('''
            updater:start();drain();scenario='bad_code';updater:update();drain()
            assert(updater.state=='error' and disk['game/X-TOOL.lua']==oldCode and reloads==0)
        ''')

    def test_hash_yields_with_real_sha_and_cancels_before_more_work(self):
        self.lua.globals().Adapter = self.lua.execute(module('update_adapter.lua'))
        self.lua.globals().sha = self.lua.execute(module('sha256.lua'))
        self.run_lua('''
            waits=0
            local rt={api={io=io,os=os,wait=function()waits=waits+1 end},
                storage={path=function()return 'release.ini' end},
                service=function(_,name)assert(name=='sha256.lua');return sha end}
            adapter=Adapter.new(rt)
            local bytes=string.rep('x',200000)
            assert(adapter.hash(bytes)==sha(bytes) and waits>=4)
            adapter.cancel()
            local ok,err=pcall(adapter.hash,bytes)
            assert(not ok and tostring(err):find('stopped'))
        ''')

    def dashboard(self, source=CODE):
        workspace = module('workspace.lua', source)
        dashboard = self.lua.execute(workspace[:workspace.index('local function drawCore(')] + '\nreturn dashboard')
        self.lua.globals().dashboard = dashboard
        self.lua.execute('''
            function drawDashboard(scale,font,padding,width)
                local cursor={x=0,y=0};local inputY,firstRowY
                local function noop()end
                local g={
                    ImBuffer=function()return {v=''}end,
                    ImBool=function(v)return {v=v}end,ImInt=function(v)return {v=v}end,
                    ImVec2=function(x,y)return {x=x,y=y}end,
                    GetTextLineHeight=function()return font end,
                    GetStyle=function()return {FramePadding={y=padding}}end,
                    SetCursorPos=function(v)cursor=v end,
                    GetCursorPosY=function()return cursor.y end,
                    CalcTextSize=function(s)return {x=#s*8,y=font}end,
                    PushItemWidth=noop,PopItemWidth=noop,InputText=function()inputY=cursor.y end,
                    IsItemHovered=function()return false end,
                    GetColorU32=function()return 0 end,
                    Combo=function()return false end,Checkbox=function()return false end,
                    TextWrapped=noop,Dummy=noop
                }
                assert(g.GetFrameHeight==nil)
                local services={
                    ['permissions.lua']={modules={}},
                    ['ui_components.lua']={checkbox=function()firstRowY=firstRowY or cursor.y;return false end},
                    ['schedule.lua']={},['appearance.lua']={choices=function()return {}end}
                }
                local rt={imgui=g,theme={palette={},color=function()return 0 end},modules={},
                    preferences={data={main={scale=scale,font=1}}},
                    access={can=function()return false end},
                    api={require=function()return {UTF8={decode=function(_,v)return v end}}end,os=os},
                    keys={order={}},schedule={nextEvents=function()return {}end},
                    typography={choices=function()return {}end},
                    service=function(_,name)return assert(services[name],name)end}
                local ui={measure=function(_,size)return size*scale end,
                    buttonHeight=function()return 32*scale end,
                    panel=noop,text=function(_,_,_,size)return size*scale end,
                    button=noop,rect=noop,image=noop,avatar=noop}
                dashboard(rt,ui,width,900)
                assert(firstRowY>=inputY+font+2*padding+12*scale,'Input overlaps first checkbox')
                return true
            end
        ''')

    def test_dashboard_legacy_imgui_and_large_fonts(self):
        self.dashboard()
        for scale in (0.75,1,1.5,2):
            for font in (14,32,56):
                for width in (600,1200):
                    with self.subTest(scale=scale,font=font,width=width):
                        self.assertTrue(self.lua.globals().drawDashboard(scale,font,6*scale,width))

    def test_regression_reproduces_original_crash(self):
        baseline = ROOT / 'update/versions/3.5.170/X-TOOL.lua'
        self.dashboard(baseline.read_text(encoding='utf-8'))
        with self.assertRaisesRegex(Exception, 'GetFrameHeight'):
            self.lua.globals().drawDashboard(1,16,3,1200)


if __name__ == '__main__':
    unittest.main(verbosity=2)
