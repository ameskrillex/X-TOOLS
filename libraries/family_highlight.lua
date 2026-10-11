-- X-TOOLS | Project and integration: Casual_Alvarez | Module: family_highlight.lua
-- Original third-party credits, where present, are retained below.
-- Screen-space body overlay driven by streamed character bones. No model patches.
local M={}
-- MoonImGui does not expose the global background/overlay draw lists.
function M.frame(g,width,height,body,windowId)
 -- Conservative per-frame geometry budget for 16-bit MoonImGui indices.
 local function bounded(draw)
  local remaining=24000
  local proxy={}
  for _,name in ipairs({'AddLine','AddCircle','AddCircleFilled'})do
   proxy[name]=function(_,a,b,c,d,e)
    local segments=name=='AddLine'and 0 or math.max(3,math.min(64,tonumber(d)or 16))
    local cost=name=='AddLine'and 16 or segments*8+32
    if remaining<cost then return end
    local function valid(p)return p and p.x==p.x and p.y==p.y and math.abs(p.x)<=width*4 and math.abs(p.y)<=height*4 end
    if not valid(a)or(name=='AddLine'and not valid(b))then return end
    remaining=remaining-cost
    if name=='AddLine'then return draw:AddLine(a,b,c,d)end
    if name=='AddCircle'then return draw:AddCircle(a,b,c,segments,e)end
    return draw:AddCircleFilled(a,b,c,segments)
   end
  end
  return proxy
 end
 local getter=g.GetBackgroundDrawList or g.GetOverlayDrawList
 if getter then return body(bounded(getter())) end
 local f=g.WindowFlags
 g.SetNextWindowPos(g.ImVec2(0,0),g.Cond.Always)
 g.SetNextWindowSize(g.ImVec2(width,height),g.Cond.Always)
 g.PushStyleColor(g.Col.WindowBg,g.ImVec4(0,0,0,0))
 g.PushStyleColor(g.Col.Border,g.ImVec4(0,0,0,0))
 local visible=g.Begin(windowId or '##xt_family_highlight',nil,f.NoTitleBar+f.NoResize+f.NoMove+f.NoScrollbar+f.NoSavedSettings+f.NoInputs+f.NoFocusOnAppearing+f.NoBringToFrontOnFocus)
 local ok,err=true,nil
 if visible then ok,err=pcall(function()body(bounded(g.GetWindowDrawList()))end) end
 g.End();g.PopStyleColor(2)
 if not ok then error(err) end
end
function M.draw(g,points,color,style,drawList)
 for _,p in pairs(points)do
  if not p or p.x~=p.x or p.y~=p.y or math.abs(p.x)>100000 or math.abs(p.y)>100000 then return end
 end
 local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
 local torso=distance(points[3],points[1]);if torso<2 or torso>600 then return end
 local width=math.max(2,math.min(65,torso*0.3))
 local d=drawList or (g.GetBackgroundDrawList and g.GetBackgroundDrawList())or (g.GetOverlayDrawList and g.GetOverlayDrawList())
 assert(d,'Family highlight requires a draw list inside its frame')
 local function point(p)return g.ImVec2(p.x,p.y)end
 if style>=2 then
  if style==7 then
   local bit=require('bit');M.draw(g,points,bit.bor(bit.band(color,0xFFFFFF),0x33000000),0,d)
  end
  for _,pair in ipairs({{1,3},{3,4},{4,5},{4,22},{22,23},{23,24},{4,32},{32,33},{33,34},{1,41},{41,42},{42,43},{1,51},{51,52},{52,53}})do
   local a,b=points[pair[1]],points[pair[2]]
   if style==5 then
    local length=distance(a,b);local count=math.max(1,math.min(32,math.ceil(length/8)))
    for i=0,count-1 do
     local t=i/count;local u=math.min(1,(i+0.55)/count)
     d:AddLine(g.ImVec2(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t),g.ImVec2(a.x+(b.x-a.x)*u,a.y+(b.y-a.y)*u),color,2)
    end
   elseif style==6 then
    local length=math.max(0.01,distance(a,b));local nx,ny=-(b.y-a.y)/length*2,(b.x-a.x)/length*2
    for _,sign in ipairs({-1,1})do d:AddLine(g.ImVec2(a.x+nx*sign,a.y+ny*sign),g.ImVec2(b.x+nx*sign,b.y+ny*sign),color,1)end
   else
    if style==4 then
     local bit=require('bit')
     d:AddLine(point(a),point(b),bit.bor(bit.band(color,0xFFFFFF),0x33000000),7)
     d:AddLine(point(a),point(b),color,3)
    end
    d:AddLine(point(a),point(b),style==4 and 0xFFFFFFFF or color,1.5)
    if style==3 then d:AddCircleFilled(point(a),2.5,color,10);d:AddCircleFilled(point(b),2.5,color,10)end
   end
  end
  d:AddCircle(point(points[5]),width,color,16,1.5)
  return
 end
 local function limb(a,b,r)
  a,b=points[a],points[b];local length=distance(a,b);if length<0.01 then return end
  if style==0 then
   d:AddLine(point(a),point(b),color,r*2)
   d:AddCircleFilled(point(a),r,color,12);d:AddCircleFilled(point(b),r,color,12)
  else
   local nx,ny=-(b.y-a.y)/length*r,(b.x-a.x)/length*r
   d:AddLine(g.ImVec2(a.x+nx,a.y+ny),g.ImVec2(b.x+nx,b.y+ny),color,1.5)
   d:AddLine(g.ImVec2(a.x-nx,a.y-ny),g.ImVec2(b.x-nx,b.y-ny),color,1.5)
  end
 end
 limb(1,3,width*1.6);limb(3,4,width*0.8)
 for _,pair in ipairs({{22,23},{23,24},{32,33},{33,34},{41,42},{42,43},{51,52},{52,53}})do limb(pair[1],pair[2],width*0.65)end
 if style==0 then d:AddCircleFilled(point(points[5]),width,color,16)
 else d:AddCircle(point(points[5]),width,color,16,1.5)end
end
return M
