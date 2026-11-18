from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT.parent/'tools/deps'))
from lupa.luajit21 import LuaRuntime
code=(ROOT/'X-TOOL.lua').read_text('utf8');m='    sources["geo_transport.lua"] = function()\n';a=code.index(m)+len(m);body=code[a:code.index('\n    end\n    sources[',a)]
class Geo(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime();self.l.globals().M=self.l.execute(body)
  self.l.execute('''now=0;files={};calls={};notices={};done={};budget={};decoded={}
   a={ms=function()return now end,time=function()return 86400+math.floor(now/1000)end,directory='cache',
   read=function(p)return files[p]end,remove=function(p)if p then files[p]=nil end end,
   decode=function(raw)return decoded[raw]end,loadBudget=function()return budget end,saveBudget=function(b)budget=b end,
   notify=function(s)table.insert(notices,s)end,download=function(url,path,cb)table.insert(calls,{url=url,path=path,cb=cb})end}
   c=M.new(a);function request(ip)c:request(ip or '1.2.3.4',function(info,err)table.insert(done,{info=info,err=err})end);c:update()end
   function tick(ms)now=now+ms;c:update()end
   function reply(n,data,status)local d=calls[n];local raw='body'..n;files[d.path]=raw;decoded[raw]=data;d.cb(n,status or 58);tick(250)end
  ''')
 def test_fallbacks_and_notifications(self):
  self.l.execute("request();calls[1].cb(1,53);tick(1);tick(2100);assert(calls[2].url:find('api.ipapi.is',1,true));calls[2].cb(2,53);tick(1);tick(2100);assert(calls[3].url:find('ip-api.com',1,true));reply(3,{status='success',query='1.2.3.4',country='Country',city='City',regionName='Region',isp='ISP'});assert(done[1].info.source=='ip-api.com');assert(#notices==2 and notices[1]:find('Ошибка',1,true) and notices[2]:find('ip-api.com',1,true))")
 def test_late_flush_and_status6(self):
  self.l.execute("request();calls[1].cb(1,6);tick(250);assert(#done==0 and #notices==0);reply(1,{ip='1.2.3.4',success=true,country='Country'});assert(done[1].info.success and #calls==1)")
 def test_missing_file_timeout_and_cancel_late_callback(self):
  self.l.execute("request();calls[1].cb(1,58);tick(2100);assert(#notices==1);tick(1);assert(#calls==2);local old=calls[2];c:cancel();old.cb(1,58);tick(13000);assert(#done==0)")
 def test_quota_survives_new_client(self):
  self.l.execute("budget={day=1,p1=1000,p2=30,p3=0};c=M.new(a);request();assert(#calls==1 and calls[1].url:find('ip-api.com',1,true));assert(budget.p3==1);c:cancel();c=M.new(a);request();assert(budget.p3==2)")
 def test_json_error_and_wrong_ip(self):
  self.l.execute("assert(not M.parse({ip='9.9.9.9',country='X'},'1.2.3.4',1));assert(not M.parse({ip='1.2.3.4',success=false,message='Rate limit exceeded'},'1.2.3.4',1));assert(not M.parse(nil,'1.2.3.4',1))")
 def test_serial_throttle(self):
  self.l.execute("request();request('5.6.7.8');assert(#calls==1);reply(1,{ip='1.2.3.4',country='C'});tick(1);assert(#calls==1);tick(2100);assert(#calls==2)")
 def test_cache_survives_refresh_failure_and_backoff(self):
  self.l.execute("clock=800000;cached={success=true,ip='1.2.3.4',country='Saved',fetched_at=1};ipwho_cache={['1.2.3.4']=cached};pending_geo={};geoRetry={};lookup_generation=1;requests=0;os.time=function()return clock end;integration={access={can=function()return true end}};function trim(s)return s end;function is_ip()return true end;function ensure_ipwho_file_cache_loaded()end;function get_cached_ipwhois(ip)return ipwho_cache[ip]end;function chat()end;function get_geo_client()return {request=function(_,ip,cb)requests=requests+1;callback=cb end}end")
  a=code.index('lookup_ipwhois = function(ip,force_refresh)');z=code.index('local function build_ipwhois_rows',a)
  self.l.execute(code[a:z])
  self.l.execute("lookup_ipwhois('1.2.3.4');assert(requests==1 and ipwho_cache['1.2.3.4'].country=='Saved');callback(nil,'timeout');assert(ipwho_cache['1.2.3.4'].success and ipwho_cache['1.2.3.4'].stale);lookup_ipwhois('1.2.3.4',true);assert(requests==1);clock=clock+301;lookup_ipwhois('1.2.3.4',true);assert(requests==2)")
 def test_fresh_cache_avoids_network(self):
  self.l.execute("ipwho_cache={};pending_geo={};geoRetry={};lookup_generation=1;integration={access={can=function()return true end}};function trim(s)return s end;function is_ip()return true end;function ensure_ipwho_file_cache_loaded()end;function get_cached_ipwhois()return {success=true,fetched_at=os.time(),country='Saved'}end;function get_geo_client()error('Cache must prevent network')end")
  a=code.index('lookup_ipwhois = function(ip,force_refresh)');z=code.index('local function build_ipwhois_rows',a);self.l.execute(code[a:z]);self.l.execute("assert(lookup_ipwhois('1.2.3.4').country=='Saved')")
 def test_compile(self):self.l.execute('assert(loadstring(...))',code)
if __name__=='__main__':unittest.main()
