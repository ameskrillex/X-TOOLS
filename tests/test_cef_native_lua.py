from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().bridge=lua.execute((root/'libraries/cef_family_bridge.lua').read_text('utf-8'))
lua.execute(r'''
local epoch,loads,starts,state,logs=100,0,0,0,0
local kernel={}
kernel.GetModuleFileNameW=function(_,out,size)
 local s='D:/Game/gta_sa.exe';for i=1,#s do out[i-1]=s:byte(i)end;return #s
end
kernel.LoadLibraryW=function(path)
 local s='';local i=0;while path[i]~=0 do s=s..string.char(path[i]);i=i+1 end
 assert(s=='D:/Game/XToolsBridge.asi');loads=loads+1;return {}
end
kernel.GetProcAddress=function(_,name)
 if name=='XTBridgeStart'then return function()starts=starts+1;state=1;return state end end
 if name=='XTBridgeStatus'then return function()return state end end
end
local ffi={cdef=function()end,new=function()return {}end,load=function(name)assert(name=='kernel32');return kernel end,cast=function(_,f)return f end}
local b=bridge.new({api={os={time=function()return epoch end},require=function(n)assert(n=='ffi');return ffi end,
 print=function()logs=logs+1 end}},'unused')
b:maintain();assert(loads==1 and starts==1 and logs==1)
epoch=101;b:maintain();assert(starts==1)
state=2;epoch=110;b:maintain();assert(starts==1 and logs==2)
epoch=120;b:maintain();assert(loads==1 and starts==1 and logs==2)
state=-3;epoch=130;b:maintain();assert(loads==1 and starts==2)
''')
print('PASS: native Lua loading, game-relative path, retained handle, throttled checks and worker restart')
