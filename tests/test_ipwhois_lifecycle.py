from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf-8')

class GeoLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        start=CODE.index('lookup_ipwhois = function(ip, force_refresh)')
        end=CODE.index('local function build_ipwhois_rows',start)
        update=CODE.index('function integration.update()\n    syncAccess()')
        pump=CODE[update:CODE.index('    if geo_changed then',update)]+'end'
        self.lua.execute('''
        now=100;downloads={};files={};ipwho_cache={};pending_geo={};lookup_generation=0;geo_serial=0
        SCRIPT_FOLDER='test';IPWHO_ENDPOINT='https://ipwho.is/%s?lang=ru'
        integration={access={can=function()return true end}}
        os.time=function()return now end;os.clock=function()return 0 end
        os.remove=function(path)files[path]=nil end
        trim=function(s)return s end;is_ip=function(s)return s=='1.1.1.1'end
        syncAccess=function()end;ensure_ipwho_file_cache_loaded=function()end
        get_cached_ipwhois=function(ip)return ipwho_cache[ip]end
        store_geo_response=function(ip,raw)ipwho_cache[ip]={success=true,raw=raw};geo_changed=true end
        io.open=function(path)
         if not files[path]then return end
         return {read=function(_,limit)assert(limit==1048577);return files[path]end,close=function()end}
        end
        downloadUrlToFile=function(url,path,cb)
         downloads[#downloads+1]={path=path,callback=cb};return true
        end
        '''+CODE[start:end]+pump)

    def test_missing_callback_times_out_with_frozen_cpu_clock(self):
        self.lua.execute("lookup_ipwhois('1.1.1.1');now=112;integration.update();assert(not pending_geo['1.1.1.1']and not ipwho_cache['1.1.1.1'].pending and ipwho_cache['1.1.1.1'].retry_at==172)")

    def test_false_start_and_tls_error_leave_loading_state(self):
        self.lua.execute("downloadUrlToFile=function()return false end;lookup_ipwhois('1.1.1.1');assert(not pending_geo['1.1.1.1']and not ipwho_cache['1.1.1.1'].pending)")
        self.setUp()
        self.lua.execute("lookup_ipwhois('1.1.1.1');downloads[1].callback(1,53);integration.update();assert(not pending_geo['1.1.1.1']and ipwho_cache['1.1.1.1'].message:find('HTTPS'))")

    def test_force_restart_and_stale_callback_cannot_overwrite_new_result(self):
        self.lua.execute('''
        lookup_ipwhois('1.1.1.1');now=103;lookup_ipwhois('1.1.1.1',true)
        assert(#downloads==2 and downloads[1].path~=downloads[2].path)
        files[downloads[1].path]='OLD';downloads[1].callback(1,58)
        assert(pending_geo['1.1.1.1']and not pending_geo['1.1.1.1'].completed)
        files[downloads[2].path]='NEW';downloads[2].callback(2,58);integration.update()
        assert(ipwho_cache['1.1.1.1'].raw=='NEW'and not pending_geo['1.1.1.1'])
        downloads[1].callback(1,58);assert(ipwho_cache['1.1.1.1'].raw=='NEW')
        ''')

    def test_duplicate_clicks_do_not_flood_and_progress_is_not_completion(self):
        self.lua.execute("lookup_ipwhois('1.1.1.1');lookup_ipwhois('1.1.1.1',true);assert(#downloads==1);downloads[1].callback(1,6);integration.update();assert(pending_geo['1.1.1.1']);now=112;integration.update();assert(not ipwho_cache['1.1.1.1'].pending)")

    def test_cache_expiry_uses_wall_clock(self):
        self.assertIn('cached.retry_at and os.time() >= cached.retry_at',CODE)
        self.assertNotIn("retry_at = os.clock() + 60",CODE)

if __name__=='__main__':unittest.main(verbosity=2)
