from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().renderer=lua.execute((root/'libraries/family_highlight.lua').read_text('utf-8'))
lua.execute('''
local count=0
local draw={AddLine=function()count=count+16 end,
 AddCircle=function(_,a,b,c,n)count=count+n*8+32 end,
 AddCircleFilled=function(_,a,b,c,n)count=count+n*8+32 end}
local g={ImVec2=function(x,y)return {x=x,y=y}end,GetBackgroundDrawList=function()return draw end}
local points={}
for i=1,53 do points[i]={x=100+i,y=100+i}end
points[23]={x=7000,y=3000}
for style=0,7 do
 count=0
 renderer.frame(g,1920,1080,function(d)
  for i=1,1003 do renderer.draw(g,points,0xFFFFFFFF,style,d)end
 end)
 assert(count>0 and count<=24000,'geometry budget exceeded: '..count)
end
count=0;points[23]={x=0/0,y=1}
renderer.frame(g,1920,1080,function(d)renderer.draw(g,points,0xFFFFFFFF,5,d)end)
assert(count==0,'nonfinite projection reached native drawing')
points[23]={x=1e20,y=1};renderer.draw(g,points,0xFFFFFFFF,5,draw);assert(count==0)
points[23]={x=7000,y=3000};renderer.draw(g,points,0xFFFFFFFF,5,draw)
assert(count<=16*32*16+16*8+32,'dashed limb is unbounded')
''')
print('PASS: 1003 players, all 8 styles, per-frame budget, invalid projections and bounded dashes')
