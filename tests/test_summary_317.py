from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT.parent/'tools/deps'))
from lupa.luajit21 import LuaRuntime
code=(ROOT/'X-TOOL.lua').read_text('utf8')
class Summary(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime();self.l.execute('''
  infos={};sent={};function trim(s)return s end;function strip_color_tags(s)return s end
  function get_offst_value()return 'Нет'end;function is_ip(s)return s~=''end
  function lookup_ipwhois(ip)return infos[ip]end
  function format_geo_summary(i)return i.city or 'Нет данных'end
  function calculate_geo_distance_km()return nil end
  function shorten_text(s,n)return s end
  function utf8_to_cp1251(s)return (s:gsub('[\\194-\\244][\\128-\\191]+','x'))end
  function sampSendChat(s)table.insert(sent,s)end;function wait()end;function set_server_notice()end
  current={nick='Test_Player',account='123',level='10',reg_ip='192.0.2.1',last_ip='192.0.2.2'}
  ''')
  a=code.index('function build_admin_chat_lines(current)');z=code.index('\nlocal function collect_unique_session_ips',a);self.l.execute(code[a:z])
 def test_errors_not_locations(self):
  self.l.execute("infos['192.0.2.1']={success=false,message='secret error one'};infos['192.0.2.2']={success=false,message='secret error two'};local lines=build_admin_chat_lines(current);assert(lines[2]:find('геоданные недоступны',1,true));assert(lines[4]:find('IP различаются',1,true));assert(not table.concat(lines):find('secret',1,true))")
 def test_success_and_pending(self):
  self.l.execute("infos['192.0.2.1']={success=true,city='City'};infos['192.0.2.2']={success=true,city='City'};assert(build_admin_chat_lines(current)[4]:find('геопозиция совпадает',1,true));infos['192.0.2.2'].pending=true;assert(build_admin_chat_lines(current)[4]:find('IP различаются',1,true))")
 def test_long_lines_split(self):
  self.l.execute("infos['192.0.2.1']={success=true,city=string.rep('City ',35)};send_admin_chat_summary(current);assert(#sent>4);for _,s in ipairs(sent)do assert(#s<=93)end")
if __name__=='__main__':unittest.main()
