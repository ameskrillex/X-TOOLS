script_name('X-Tools Libraries')
local messages=(function()
-- X-TOOLS | Casual_Alvarez | Dependency-free Russian setup messages.
local M={}
function M.cp1251(text)
 return tostring(text):gsub('[\194-\244][\128-\191]+',function(ch)
  local a,b=ch:byte(1,2);local code=(a-192)*64+(b-128)
  if #ch==2 and code>=1040 and code<=1103 then return string.char(code-848)end
  if code==1025 then return string.char(168)end
  if code==1105 then return string.char(184)end
  return ({['—']='-',['–']='-',['…']='...',['«']='"',['»']='"'})[ch]or '?'
 end)
end
function M.reason(err)
 local s=tostring(err):lower()
 if s:find('checksum',1,true)or s:find('sha256',1,true)then return 'Скачанный файл не прошёл проверку целостности.\nПовторите скачивание.'end
 if s:find('timed out',1,true)or s:find('timeout',1,true)then return 'Сервер загрузки не ответил вовремя.\nПроверьте интернет и повторите попытку.'end
 if s:find('https',1,true)or s:find('download',1,true)then return 'Не удалось скачать файлы.\nПроверьте интернет и доступность GitHub.'end
 if s:find('permission',1,true)or s:find('access denied',1,true)or s:find('cannot create',1,true)then return 'Не удалось записать файлы.\nПроверьте доступ к папке игры и свободное место.'end
 if s:find('url',1,true)then return 'Некорректный адрес обновления.\nУстановите полный архив X-Tools с GitHub.'end
 return 'Не удалось подготовить файлы X-Tools.\nТочная причина записана в moonloader.log.'
end
function M.chat(api,root,text)
 local accent=0xC080FF
 local f=api.io.open(root..'/X-TOOL/settings/interface.ini','rb')
 if f then
  local bytes=f:read('*a')or '';f:close()
  local theme=tonumber(bytes:match('themeStyle%s*=%s*(%d+)')or bytes:match('backgroundStyle%s*=%s*(%d+)'))or 0
  accent=({0x59DFFF,0xFFAB51,0x62E9AB,0xFF6086,0xAA91FF})[theme]or accent
 end
 for line in tostring(text):gmatch('[^\r\n]+')do
  local prefix=string.format('{%06X}[X-TOOLS] {F0EDF8}',accent)
  local row=''
  for word in M.cp1251(line):gmatch('%S+')do
   if #row+#word+1>85 and row~=''then api.sampAddChatMessage(prefix..row,-1);row=''end
   while #word>85 do
    api.sampAddChatMessage(prefix..word:sub(1,85),-1);word=word:sub(86)
   end
   row=row..(row~=''and ' 'or '')..word
  end
  if row~=''then api.sampAddChatMessage(prefix..row,-1)end
 end
end
return M

end)()
local hash=(function()
-- X-TOOLS | Project and integration: Casual_Alvarez | Module: sha256.lua
-- Original third-party credits, where present, are retained below.
-- SHA-256 over byte strings. LuaJIT bit operations; no external hashing package.
local bit = require 'bit'
local band, bxor, bnot, rshift, ror = bit.band, bit.bxor, bit.bnot, bit.rshift, bit.ror
local constants = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
}
local function word(n)
    return string.char(band(rshift(n,24),255),band(rshift(n,16),255),band(rshift(n,8),255),band(n,255))
end
return function(bytes, yield)
    local length=#bytes
    bytes=bytes..'\128'..string.rep('\0',(55-length)%64)..word(math.floor(length/536870912))..word(length*8)
    local hash={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local words={}
    for offset=1,#bytes,64 do
        if yield and offset % 65536 == 1 then yield(0) end
        for i=0,15 do
            local a,b,c,d=bytes:byte(offset+i*4,offset+i*4+3)
            words[i]=bit.tobit(((a*256+b)*256+c)*256+d)
        end
        for i=16,63 do
            local x,y=words[i-15],words[i-2]
            words[i]=bit.tobit(words[i-16]+bxor(ror(x,7),ror(x,18),rshift(x,3))+words[i-7]+bxor(ror(y,17),ror(y,19),rshift(y,10)))
        end
        local a,b,c,d,e,f,g,h=unpack(hash)
        for i=0,63 do
            local first=bit.tobit(h+bxor(ror(e,6),ror(e,11),ror(e,25))+bxor(band(e,f),band(bnot(e),g))+constants[i+1]+words[i])
            local second=bit.tobit(bxor(ror(a,2),ror(a,13),ror(a,22))+bxor(band(a,b),band(a,c),band(b,c)))
            h,g,f,e,d,c,b,a=g,f,e,bit.tobit(d+first),c,b,a,bit.tobit(first+second)
        end
        local final={a,b,c,d,e,f,g,h}
        for i=1,8 do hash[i]=bit.tobit(hash[i]+final[i]) end
    end
    local result={}
    for i=1,8 do result[i]=bit.tohex(hash[i]) end
    return table.concat(result)
end

end)()
local service=(function()
-- X-TOOLS | Project and integration: Casual_Alvarez | Module: dependencies.lua
-- Original third-party credits, where present, are retained below.
-- Installs only missing files from the release-pinned library catalogue.
local M={}
function M.new(api,catalog,hash,notify)
    local self={busy=false,status='Нажмите «Проверить библиотеки».',missing={}}
    local root=api.getWorkingDirectory():gsub('\\','/')..'/lib'
    local function exists(path)local f=api.io.open(path,'rb');if f then f:close();return true end;return false end
    local function read(path)local f=assert(api.io.open(path,'rb'));local b=f:read('*a');f:close();return b end
    local function ensure(path)
        if api.doesDirectoryExist(path) then return end
        local parent=path:match('^(.*)/[^/]+$');if parent then ensure(parent)end
        api.createDirectory(path);assert(api.doesDirectoryExist(path),'Cannot create '..path)
    end
    local seen={}
    for _,f in ipairs(catalog.files)do
        assert(type(f.path)=='string' and f.path:match('^[%w_./%-]+$') and not f.path:find('..',1,true)
            and f.path:sub(1,1)~='/' and not seen[f.path:lower()],'Invalid dependency path')
        assert(type(f.bytes)=='number' and f.bytes>0 and type(f.offset)=='number' and f.offset>=0
            and f.offset+f.bytes<=catalog.bytes and #f.sha256==64,'Invalid dependency descriptor')
        seen[f.path:lower()]=true
    end
    function self:check()
        self.missing={}
        for _,f in ipairs(catalog.files)do if not exists(root..'/'..f.path)then self.missing[#self.missing+1]=f end end
        self.status=#self.missing==0 and 'Все файлы комплекта библиотек присутствуют.' or ('Отсутствует файлов: '..#self.missing)
        return #self.missing
    end
    function self:install()
        if self.busy then return end
        if self:check()==0 then notify(self.status);return end
        self.busy=true;self.status='Скачивание библиотек…'
        api.lua_thread.create(function()
            local temp
            local ok,err=pcall(function()
                ensure(root)
                repeat temp=root..'/xt-libraries-'..tostring(api.getGameTimer())..'-'..tostring(math.random(100000,999999))..'.tmp' until not exists(temp)
                local finished=false
                api.downloadUrlToFile(catalog.url,temp,function(_,status)if status==6 or status==58 then finished=true end end)
                local deadline=api.getGameTimer()+120000
                while not finished and api.getGameTimer()<deadline do api.wait(100)end
                assert(finished,'Download timeout')
                local bytes=read(temp)
                assert(#bytes==catalog.bytes and hash(bytes)==catalog.sha256,'Library package checksum mismatch')
                -- Validate every missing file before committing any of them.
                for _,f in ipairs(self.missing)do
                    assert(hash(bytes:sub(f.offset+1,f.offset+f.bytes))==f.sha256,'Library checksum mismatch: '..f.path)
                    api.wait(0)
                end
                local installed=0
                for _,f in ipairs(self.missing)do
                    local path=root..'/'..f.path
                    if not exists(path)then
                        ensure(path:match('^(.*)/[^/]+$'))
                        local stage=path..'.xt-new'
                        assert(not exists(stage),'Staging file exists: '..stage)
                        local output=assert(api.io.open(stage,'wb'))
                        assert(output:write(bytes:sub(f.offset+1,f.offset+f.bytes)));assert(output:close())
                        assert(hash(read(stage))==f.sha256,'Written library checksum mismatch')
                        if exists(path)then api.os.remove(stage)
                        else assert(api.os.rename(stage,path));installed=installed+1 end
                    end
                    api.wait(0)
                end
                self:check();self.status='Добавлено файлов: '..installed..'. Перезапустите игру.'
            end)
            if temp then api.os.remove(temp)end
            self.busy=false
            if not ok then
                if api.print then api.print('[X-Tools Libraries ERROR] '..tostring(err))end
                self.status='Не удалось установить все библиотеки.\nПроверьте интернет, доступ к папке игры и свободное место.\nПодробности: moonloader.log. Повторная попытка: /xtlibs.\nПосле установки перезапустите игру.'
            end
            notify(self.status)
        end)
    end
    function self:draw(g)
        g.Separator();g.TextWrapped('Библиотеки X-Tools');g.TextWrapped(self.status)
        if not self.busy then
            if g.Button('Проверить библиотеки##xt_dependencies')then self:check()end
            if #self.missing>0 and g.Button('Скачать недостающие библиотеки##xt_dependencies_install')then self:install()end
        end
        
    end
    return self
end
return M

end)()
local catalog=decodeJson([====[{
  "schema": 1,
  "url": "https://raw.githubusercontent.com/ameskrillex/X-TOOLS/main/libraries/3.5.29/libraries.pack",
  "bytes": 14206748,
  "sha256": "be50dae6dfedc17ab4322e8e154a43fd87e074b3ee7963ec67dc5ea3f0976fd6",
  "files": [
    {
      "path": "MoonImGui.dll",
      "offset": 0,
      "bytes": 2523648,
      "sha256": "4253191c312fa4a25bfd38a87ffde01d4f606df7491463b8aefa3034dec2127f"
    },
    {
      "path": "aeslua.lua",
      "offset": 2523648,
      "bytes": 3461,
      "sha256": "3fcd6f07c6dc0ed83825ed4967c2ab67de20f6a65f71d798190b9a109c550e96"
    },
    {
      "path": "aeslua/aes.lua",
      "offset": 2527109,
      "bytes": 17825,
      "sha256": "c141206d045bafe99eac40bbc374d8eac6b17fd1e050c5cc6c4249310ed36c34"
    },
    {
      "path": "aeslua/buffer.lua",
      "offset": 2544934,
      "bytes": 454,
      "sha256": "02364f1e8d68fadeeee8cff9aead42514240def869c3404b40f398cc8e98f5fe"
    },
    {
      "path": "aeslua/ciphermode.lua",
      "offset": 2545388,
      "bytes": 3600,
      "sha256": "5c65873d17eac620d3f76513afef41e392bbf58dc12495ba458b24c2d4f1454a"
    },
    {
      "path": "aeslua/gf.lua",
      "offset": 2548988,
      "bytes": 2289,
      "sha256": "b5af38abfbfe0749ae27b28a80b0cd5571792d0d2b03267edf18c91d44f9eddc"
    },
    {
      "path": "aeslua/util.lua",
      "offset": 2551277,
      "bytes": 3703,
      "sha256": "9d1fc9e03612bc3bd0298060de237fca5afb96d18db566728a3051be1fb99333"
    },
    {
      "path": "base64.dll",
      "offset": 2554980,
      "bytes": 72192,
      "sha256": "4e19bac2a3e0a3e854143ed9259b82a4f405409b0d2928e10a27db672bf346be"
    },
    {
      "path": "bitex.lua",
      "offset": 2627172,
      "bytes": 557,
      "sha256": "f447e48e80522e66cd9f4a038a361cfa19912f4c3ed9cd1d8965c8db1a23f24f"
    },
    {
      "path": "cjson.dll",
      "offset": 2627729,
      "bytes": 122880,
      "sha256": "9fa1f6c66644a3e14a7d0e8d2937512963773fd047fa6826482caa304ecf964c"
    },
    {
      "path": "cjson/cjson/util.lua",
      "offset": 2750609,
      "bytes": 6837,
      "sha256": "0f9c82e5ba2779ecf5c4016e944213524549e8ea0c91fd7f00b2c6bb0441ee4a"
    },
    {
      "path": "cjson/util.lua",
      "offset": 2757446,
      "bytes": 6837,
      "sha256": "0f9c82e5ba2779ecf5c4016e944213524549e8ea0c91fd7f00b2c6bb0441ee4a"
    },
    {
      "path": "des56.dll",
      "offset": 2764283,
      "bytes": 76800,
      "sha256": "f11c13152a8f6fbc44d3c3fa8a8c804d7fbb2d22a20a869a130e6da3264e7862"
    },
    {
      "path": "effil.dll",
      "offset": 2841083,
      "bytes": 368128,
      "sha256": "0c823502bc9576225bf7ba315ca54aafa82668947b1af1ca4f09b07396fc4153"
    },
    {
      "path": "effil.lua",
      "offset": 3209211,
      "bytes": 1654,
      "sha256": "5685236a73337237372226bef9740a6f7cb981998912724a0e4bd326da7e96dd"
    },
    {
      "path": "encoding.lua",
      "offset": 3210865,
      "bytes": 2636,
      "sha256": "57cb02218d46eb1b8b2b14ecde30fc0d1798fad9c69c2138ff9a7bf63d3efe9d"
    },
    {
      "path": "fAwesome6.lua",
      "offset": 3213501,
      "bytes": 3839469,
      "sha256": "e0a3bcd5d0dab0aec5ea843a58bae05148caf44f64aa83c55153c239175fcd48"
    },
    {
      "path": "game/globals.lua",
      "offset": 7052970,
      "bytes": 28363,
      "sha256": "f8b12223b5bc4909b90d7b4774c43668f123d094ade3d0d379cb0514e7815c39"
    },
    {
      "path": "game/keys.lua",
      "offset": 7081333,
      "bytes": 1062,
      "sha256": "10bfe26a67586eabf07823077ab5ba6acd78ebda7666179eaea91fcf2a6a5836"
    },
    {
      "path": "game/models.lua",
      "offset": 7082395,
      "bytes": 12767,
      "sha256": "ba4dcac97bdd11de9daee4ce771ba34cc9e87ed24298201ea74661ae7b7d2475"
    },
    {
      "path": "game/weapons.lua",
      "offset": 7095162,
      "bytes": 2443,
      "sha256": "ab044731f71a30a426e2d1aac1936169d4b558a5f6fe11d81c5c290ad0ae1e98"
    },
    {
      "path": "iconv.dll",
      "offset": 7097605,
      "bytes": 1000960,
      "sha256": "bb4cc421b7606055d1d517775b15ce77a27ad97b14de2fc31c9d9e3cf788b98f"
    },
    {
      "path": "iconv/COPYING-libiconv",
      "offset": 8098565,
      "bytes": 25291,
      "sha256": "56bdea73b6145ef6ac5259b3da390b981d840c24cb03b8e1cbc678de7ecfa18d"
    },
    {
      "path": "iconv/README-libiconv",
      "offset": 8123856,
      "bytes": 5801,
      "sha256": "b4f5932ef35fe4a66ae9e8eecf1bac0702fe2a75ece40861baf3ebbc0ee9ed02"
    },
    {
      "path": "iconv/README-lua-iconv",
      "offset": 8129657,
      "bytes": 4755,
      "sha256": "7aebae7bea8fb38be3aa18b6e2e6298f9370bfe0b3415ac19fe4d04ba5fca58a"
    },
    {
      "path": "imgui.lua",
      "offset": 8134412,
      "bytes": 113971,
      "sha256": "c3cf0eee207d637e4192427cf8929d1bd9180ef9df520b652a9ab400182db9ae"
    },
    {
      "path": "inspect.lua",
      "offset": 8248383,
      "bytes": 9792,
      "sha256": "15d622f57df18ab4842d6d4ca13d7473f3d9a713de0ef132573ba05a93e72499"
    },
    {
      "path": "json2lua.lua",
      "offset": 8258175,
      "bytes": 304,
      "sha256": "0a7830dca64d95336c0c4e06865ddad412517c3d685f30265b075941d65aa591"
    },
    {
      "path": "lanes.lua",
      "offset": 8258479,
      "bytes": 24777,
      "sha256": "697bca772fcbcdb05abdf57eb4777dd2d5122dd3d5abdc6e3be6111c85265ebe"
    },
    {
      "path": "lanes/core.dll",
      "offset": 8283256,
      "bytes": 174592,
      "sha256": "aaf492a38689d1b2c24dbc966b3c23727e6d1d961ddd513a5b4942283fd95559"
    },
    {
      "path": "lfs.dll",
      "offset": 8457848,
      "bytes": 126976,
      "sha256": "2f093e36fc36ec56c852181f428c1d5b6ad9d1071b53f21e93946c490a24609a"
    },
    {
      "path": "lib-effil/effil.lua",
      "offset": 8584824,
      "bytes": 1654,
      "sha256": "5685236a73337237372226bef9740a6f7cb981998912724a0e4bd326da7e96dd"
    },
    {
      "path": "lib-effil/libeffil.dll",
      "offset": 8586478,
      "bytes": 594432,
      "sha256": "8ac736f5d9116fda2682909477bb7da83e53fbc1eaaeb2826aec35dbd6da874c"
    },
    {
      "path": "libeffil.dll",
      "offset": 9180910,
      "bytes": 594432,
      "sha256": "8ac736f5d9116fda2682909477bb7da83e53fbc1eaaeb2826aec35dbd6da874c"
    },
    {
      "path": "lockbox.lua",
      "offset": 9775342,
      "bytes": 31,
      "sha256": "0efa8f85cf3c8c4d87f16bcc12b624242b2501d94cd74196e85550e3c1cc4439"
    },
    {
      "path": "lockbox/cipher/aes128.lua",
      "offset": 9775373,
      "bytes": 15290,
      "sha256": "9916291c379e2f2d5a9e3b3b7d7684d161c5ad1ac8fccd08d05553b6aae0b358"
    },
    {
      "path": "lockbox/cipher/mode/ecb.lua",
      "offset": 9790663,
      "bytes": 2846,
      "sha256": "92d95b812e09f644eafe311add7ea365e755aba2de1e87828218e456559c7bd9"
    },
    {
      "path": "lockbox/digest/md5.lua",
      "offset": 9793509,
      "bytes": 4845,
      "sha256": "58b7ac5e3e96b30e715da6c4590c385e0d08356f2ccc64b47493a99fb232f7a3"
    },
    {
      "path": "lockbox/digest/sha2_256.lua",
      "offset": 9798354,
      "bytes": 5410,
      "sha256": "a327c2dce4b83f5e429e18f539b45dae4948b1f8aa3532eba239b5ce703b7ce1"
    },
    {
      "path": "lockbox/init.lua",
      "offset": 9803764,
      "bytes": 513,
      "sha256": "b4288fb07c8f21f277d813b61204caf9b7be3f97648116e41d34e3d6cb1d7333"
    },
    {
      "path": "lockbox/mac/hmac.lua",
      "offset": 9804277,
      "bytes": 1606,
      "sha256": "8d32920ea93ef74736de787848e4d475ac712a4903cb4dd625b03f1a55b4cb0b"
    },
    {
      "path": "lockbox/padding/zero.lua",
      "offset": 9805883,
      "bytes": 374,
      "sha256": "23f58ef7fa04ac78018a73294b9ff0ecd67e84876198befb12b0589700e7cccf"
    },
    {
      "path": "lockbox/util/array.lua",
      "offset": 9806257,
      "bytes": 2914,
      "sha256": "35ae9d9c96e883e4be6872a5d61c3b1c1080f438ab9ff5d0a1b610ab500e5717"
    },
    {
      "path": "lockbox/util/base64.lua",
      "offset": 9809171,
      "bytes": 3464,
      "sha256": "21dadf4a2b00eb0bcc0e45ca118561704c7df6cc822c9bd07d7f1f461d9b63ef"
    },
    {
      "path": "lockbox/util/bit.lua",
      "offset": 9812635,
      "bytes": 559,
      "sha256": "31feb876e084bb35e06e73cc4dc319089847a8083a9db182e0c9de7b073fee52"
    },
    {
      "path": "lockbox/util/queue.lua",
      "offset": 9813194,
      "bytes": 613,
      "sha256": "39ca120ee5e4fcc630dd1a8408426336c7fa8748121ec17e20cfa326d3526c1a"
    },
    {
      "path": "lockbox/util/stream.lua",
      "offset": 9813807,
      "bytes": 1512,
      "sha256": "fdf62afbfdbca8c81529adbe972e0cdb330f2fcbd01c671a7f16887693402c53"
    },
    {
      "path": "ltn12.lua",
      "offset": 9815319,
      "bytes": 8331,
      "sha256": "3bf0000f86d25da94089d47de3bbb204fd5be491edbe275730e73f68c710ea42"
    },
    {
      "path": "lua2json.lua",
      "offset": 9823650,
      "bytes": 387,
      "sha256": "8b2fb6a36753079ff5b49d7e737468215668f0ce075bf285923f004ad0dbeda2"
    },
    {
      "path": "luasql-sqlite/luasql/sqlite3.dll",
      "offset": 9824037,
      "bytes": 654336,
      "sha256": "ac2aa49ff7cde55563cb0e13920b018a4ad039dca3ab3bfb9ee0ac361fcf6605"
    },
    {
      "path": "lub/Autoload.lua",
      "offset": 10478373,
      "bytes": 2877,
      "sha256": "0c6f85b09079a01359b1073e7870aec9f325b9aabfa41f8ff557152437ef0318"
    },
    {
      "path": "lub/Dir.lua",
      "offset": 10481250,
      "bytes": 2813,
      "sha256": "3adacf1cd484fdb3587def9ff9176e44cd02d72ee804e60442ac4b5ab333735b"
    },
    {
      "path": "lub/Param.lua",
      "offset": 10484063,
      "bytes": 9094,
      "sha256": "7f2eda637349e6e4231e559e3fe691ac7b3518186aaf6a6508e6679c7a83b877"
    },
    {
      "path": "lub/Template.lua",
      "offset": 10493157,
      "bytes": 4556,
      "sha256": "8ca1ff31f526668907f38e349fccc2578b62895c4a215c086ef6d18e1c57de65"
    },
    {
      "path": "lub/init.lua",
      "offset": 10497713,
      "bytes": 20988,
      "sha256": "b9a5335d638ff9776679a677e8df5f41a90f8a94b91f41b371273371047c806e"
    },
    {
      "path": "matrix3x3.lua",
      "offset": 10518701,
      "bytes": 2070,
      "sha256": "4ac3e8f840fdf294edce96a95e3199b2c6b5ea115036a2fd9862742d5db3d4e9"
    },
    {
      "path": "md5.lua",
      "offset": 10520771,
      "bytes": 836,
      "sha256": "921f2e4d48d8987be0eb96a93762a918bbdd825b7c506ef68aedf1b217ae6355"
    },
    {
      "path": "md5/core.dll",
      "offset": 10521607,
      "bytes": 75776,
      "sha256": "cba9525d93957d6b442ef019557cf6c47bde0aad07652c897900475335e281e0"
    },
    {
      "path": "mime.lua",
      "offset": 10597383,
      "bytes": 2487,
      "sha256": "a548fc214ac1e935afa683df9bdbeded0ca60cf353dfcc16f6db0187b9fc512d"
    },
    {
      "path": "mime/core.dll",
      "offset": 10599870,
      "bytes": 77824,
      "sha256": "e845e535e70086ab72f18d53d00cf80d15300089ab78db3eff383b5854e8667f"
    },
    {
      "path": "mimgui/LICENSE",
      "offset": 10677694,
      "bytes": 1060,
      "sha256": "df4b74acb305863b56efce70b9d1d03541c3fb8670b2d41c64cc5c6e1cd8462d"
    },
    {
      "path": "mimgui/cdefs.lua",
      "offset": 10678754,
      "bytes": 118018,
      "sha256": "8e5d3488f23c446a6a8a61b6b0ecc25cc38f326257b14801023bfad3bf650a7e"
    },
    {
      "path": "mimgui/cimgui_dx9.dll",
      "offset": 10796772,
      "bytes": 588288,
      "sha256": "93bff4351d6c935c16ec7665e886d960b3a2dea3d197f5352a1361516e8e14f8"
    },
    {
      "path": "mimgui/cimguidx9.dll",
      "offset": 11385060,
      "bytes": 543744,
      "sha256": "1a7a059974c33095edc2f2da880d7c79c99d7e3b3c189e2f51036bb7e519d88b"
    },
    {
      "path": "mimgui/dx9.lua",
      "offset": 11928804,
      "bytes": 6717,
      "sha256": "617029534c747c9ef91cdf9674e1d399cda3cca719e9aa91240b423ad4e2624f"
    },
    {
      "path": "mimgui/imgui.lua",
      "offset": 11935521,
      "bytes": 103788,
      "sha256": "dac0e8cad50f766f8284a6bfeccb9ce275aa809d842e90ce81de52991cd87e9a"
    },
    {
      "path": "mimgui/init.lua",
      "offset": 12039309,
      "bytes": 14627,
      "sha256": "8a1187a313da1b4eade4dcb9e959e770af99163c2c965d37b46c88aef892a182"
    },
    {
      "path": "mimgui/win32.lua",
      "offset": 12053936,
      "bytes": 2276,
      "sha256": "90a3e731b1df60d2022c6935631553b2424aa28ae45b84797c62d5119df95bee"
    },
    {
      "path": "mimgui_blur/init.lua",
      "offset": 12056212,
      "bytes": 3988,
      "sha256": "639f985d77ce8b4c263f9565af15325c0f0304eea93b666961d89dac03673f2c"
    },
    {
      "path": "mimgui_blur/mimgui_blur_lib.dll",
      "offset": 12060200,
      "bytes": 11776,
      "sha256": "721de5d137733f639154a5cf09982fbff8c1d3d262efb17b59cba0f49191f20b"
    },
    {
      "path": "moonloader.lua",
      "offset": 12071976,
      "bytes": 3171,
      "sha256": "58dc9a058468f53efda285b2e1bc41318ca84e1e0c4821e38c70766029c1530e"
    },
    {
      "path": "requests.lua",
      "offset": 12075147,
      "bytes": 9016,
      "sha256": "52fc5c27c0de5bfcdc11b7411b4a562d46389f2624b097210ea31f4eb9daa18b"
    },
    {
      "path": "samp/events.lua",
      "offset": 12084163,
      "bytes": 26562,
      "sha256": "b0d052dd38aa8584c0de376558232e8947aae6a63e50a36182613a157c19c882"
    },
    {
      "path": "samp/events/bitstream_io.lua",
      "offset": 12110725,
      "bytes": 6888,
      "sha256": "bdc86d8ce69a6b6fd456f0d242224030ba6c91def98919d49ae06423600da689"
    },
    {
      "path": "samp/events/core.lua",
      "offset": 12117613,
      "bytes": 3739,
      "sha256": "dc93cf932b15a44c295cfb69fa6bf3651a6ad04c1ec30924eac9f7c363854a1a"
    },
    {
      "path": "samp/events/extra_types.lua",
      "offset": 12121352,
      "bytes": 1528,
      "sha256": "a61653de6e370ab6913d8f563d505c01fd74f811602ca80f33164ec3723bb701"
    },
    {
      "path": "samp/events/handlers.lua",
      "offset": 12122880,
      "bytes": 16879,
      "sha256": "22b5bbbc1590fbc10dafffb7007b8398b84f0463ba53add468633df73c0b8d6a"
    },
    {
      "path": "samp/events/utils.lua",
      "offset": 12139759,
      "bytes": 1340,
      "sha256": "9b210c87ccfc3981200e71f9893bdf89861bbd38eb069a32ed2efc897fd77356"
    },
    {
      "path": "samp/events_core.lua",
      "offset": 12141099,
      "bytes": 5644,
      "sha256": "e446ff32d3d1a8526a9e78bf7fed3fb70e9716ad4b78298d2c817aa367612c98"
    },
    {
      "path": "samp/packet.lua",
      "offset": 12146743,
      "bytes": 2390,
      "sha256": "ada854f7f0fa0131d09e36018521c263612fcec2dda36d29619ced8f2baa6d18"
    },
    {
      "path": "samp/raknet.lua",
      "offset": 12149133,
      "bytes": 11945,
      "sha256": "f114023602a6799cd9041347f9ba65d3a27a576af5e9c2a621d59d91e2215920"
    },
    {
      "path": "samp/synchronization.lua",
      "offset": 12161078,
      "bytes": 4097,
      "sha256": "9a41d729323efd63e298020d12b7b7cfbd447b6e7113592fa6eb6d0e88797344"
    },
    {
      "path": "sampfuncs.lua",
      "offset": 12165175,
      "bytes": 15207,
      "sha256": "7c2528ec287d4ffdcb381f3a96a6678361075828cc727e9ff2e9cb91d4ad0cd3"
    },
    {
      "path": "socket.lua",
      "offset": 12180382,
      "bytes": 4451,
      "sha256": "332871e3beeaccf8bff18cde1509e81c2bd16beb511b1fe586c12862dc7667b2"
    },
    {
      "path": "socket/core.dll",
      "offset": 12184833,
      "bytes": 142848,
      "sha256": "c7e65c06df09addf05fd807e964e87f4ea56476e15e19ea5e47a321419ace50e"
    },
    {
      "path": "socket/ftp.lua",
      "offset": 12327681,
      "bytes": 9243,
      "sha256": "05eae0f1477cc17a580cb88e11a62107b1b6cde37a1c76fced6f91b390d98ed5"
    },
    {
      "path": "socket/headers.lua",
      "offset": 12336924,
      "bytes": 3698,
      "sha256": "aecff8c2d99d77a6473269367d5b085ad0db189d9699c2f47dcb97ae5ad348df"
    },
    {
      "path": "socket/http.lua",
      "offset": 12340622,
      "bytes": 12330,
      "sha256": "9bdf0c2b37f1941e4a65c31697187ee976b43d0a4a8865b96260222f85c0fdb8"
    },
    {
      "path": "socket/smtp.lua",
      "offset": 12352952,
      "bytes": 8074,
      "sha256": "55bdeff392dffc381b1487b6e9493a7aadb52f851f78ec29316decf50d88df58"
    },
    {
      "path": "socket/tp.lua",
      "offset": 12361026,
      "bytes": 3612,
      "sha256": "9faacdfcde3167ab426054625ccf0ca8255a24dc7752f58543edbc93216b53b1"
    },
    {
      "path": "socket/url.lua",
      "offset": 12364638,
      "bytes": 11036,
      "sha256": "7290952cba25a671e0434a01b5693855cb5d19ba777adb302779b050d8b0d3c7"
    },
    {
      "path": "ssl.dll",
      "offset": 12375674,
      "bytes": 1633280,
      "sha256": "7ae579c19b20e618cd30d661bb22f3e9736428d1b62b1e758d87da32c00409c5"
    },
    {
      "path": "ssl.lua",
      "offset": 14008954,
      "bytes": 4842,
      "sha256": "1926c6fc79396cb573f40b8e3fd4810f2b48b9b76e62d2e190041eab1d4a4d16"
    },
    {
      "path": "ssl/https.lua",
      "offset": 14013796,
      "bytes": 4176,
      "sha256": "4a4d95bf6b4b3e8a0af84e1e53eb799e96c23a1527b424748927f5a62aa1318b"
    },
    {
      "path": "vector3d.lua",
      "offset": 14017972,
      "bytes": 1770,
      "sha256": "53ef9eedad5994e05320dcb5c14b504dd6c09e6a70111d76eb60a52d6c4a68af"
    },
    {
      "path": "vkeys.lua",
      "offset": 14019742,
      "bytes": 9814,
      "sha256": "a74b3f76666e8c8b9fa078e239bcfd3123762ee064c242f9349fdda9a449718b"
    },
    {
      "path": "windows/init.lua",
      "offset": 14029556,
      "bytes": 184,
      "sha256": "259c01a3c10b5470164dcf24614702d3d2121fb4c32b9fedfb626af281a93c11"
    },
    {
      "path": "windows/message.lua",
      "offset": 14029740,
      "bytes": 26909,
      "sha256": "4ab3845c28e7755c86736162fd22cba165e534ec1df5c76665ce8ffdbb8a929f"
    },
    {
      "path": "xml/Parser.lua",
      "offset": 14056649,
      "bytes": 1750,
      "sha256": "c46fa675a7f6303c70bfdffec3bbd4b6babe91fae463ab8d75bbf27f05c6125f"
    },
    {
      "path": "xml/core.dll",
      "offset": 14058399,
      "bytes": 140800,
      "sha256": "7f02af34a92b286bcad9ff5afc3deede314737b9957a9f1cad0108fb087555b6"
    },
    {
      "path": "xml/init.lua",
      "offset": 14199199,
      "bytes": 7549,
      "sha256": "49648e800722d846cf2a77d5cb4569b46458f217a19aadd4ca9b6652e48ce210"
    }
  ]
}]====])
local installer=service.new(_G,catalog,function(bytes)return hash(bytes,wait)end,function(text)
    print('[X-Tools Libraries] '..text)
    messages.chat(_G,getWorkingDirectory(),text)
end)
function main()
    repeat wait(100) until isSampAvailable()
    sampRegisterChatCommand('xtlibs',function()installer:install()end)
    wait(-1)
end
