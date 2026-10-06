"""Build streamed overlay traversal from the immutable 3.5.304 release."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'update/current/versions/3.5.304'
code = (BASE / 'X-TOOL.lua').read_text('utf-8')

def replace(old, new):
    global code
    assert code.count(old) == 1, (code.count(old), old[:100])
    code = code.replace(old, new)

replace('local APP = {session = 0}', '''local APP = {session = 0}
APP.streamedPlayers=integration.service('streamed_players.lua').new(_G)
function APP.renderPlayerIds()
    -- Preserve ascending ID order: nametag collision placement depends on it.
    local ids={}
    for id in pairs(APP.streamedPlayers:list())do ids[#ids+1]=id end
    table.sort(ids)
    return ids
end''')
replace('''    local maxPlayerId = sampGetMaxPlayerId(false)
    DATA.customNametags.occupied={}

    for playerId = 0, maxPlayerId do''', '''    DATA.customNametags.occupied={}

    for _,playerId in ipairs(APP.renderPlayerIds())do''')
replace('''  for id=0,sampGetMaxPlayerId(false)do
   if sampIsPlayerConnected(id)then''', '''  for _,id in ipairs(APP.renderPlayerIds())do
   if sampIsPlayerConnected(id)then''')
replace('''function sampev.onPlayerStreamIn(playerId, team, model, position, rotation, color, fightingStyle)
    markPlayerOnlineById''', '''function sampev.onPlayerStreamOut(playerId)
    APP.streamedPlayers:remove(playerId)
end

function sampev.onPlayerStreamIn(playerId, team, model, position, rotation, color, fightingStyle)
    APP.streamedPlayers:add(playerId)
    markPlayerOnlineById''')
replace('''function sampev.onPlayerQuit(playerId, reason)
    local id = tonumber(playerId) or -1
    markPlayerOnlineById''', '''function sampev.onPlayerQuit(playerId, reason)
    APP.streamedPlayers:remove(playerId)
    local id = tonumber(playerId) or -1
    markPlayerOnlineById''')
replace('''function integration.stop()
    if APP.shieldTexture''', '''function integration.stop()
    APP.streamedPlayers:reset()
    if APP.shieldTexture''')
start = code.index('    sources["modules/capture.lua"]')
pos = code.index('integration.onDisconnect = function()\n', start)
code = code[:pos] + code[pos:].replace('integration.onDisconnect = function()\n', 'integration.onDisconnect = function()\n    APP.streamedPlayers:reset()\n', 1)
from release_305_changes import transform
code = transform(code).replace('[CADM]', '[XTOOLS]').replace('3.5.304', '3.5.305').encode('utf-8')
manifest = json.loads((BASE / 'manifest.json').read_text('utf-8'))
manifest.update(version='3.5.305', packagePath='versions/3.5.305/')
manifest['script'].update(bytes=len(code), sha256=hashlib.sha256(code).hexdigest())
for directory in (ROOT / 'update/current', ROOT / 'update/current/versions/3.5.305'):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'X-TOOL.lua').write_bytes(code)
    (directory / 'manifest.json').write_bytes((json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode('utf-8'))
    shutil.copyfile(BASE / 'assets.pack', directory / 'assets.pack')
(ROOT / 'X-TOOL.lua').write_bytes(code)
print(json.dumps(manifest['script']))
