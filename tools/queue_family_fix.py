"""Route local family commands correctly and recognize their server confirmations."""
def transform(code):
    def replace(old,new):
        nonlocal code
        assert code.count(old)==1,(old[:100],code.count(old))
        code=code.replace(old,new)
    replace('local sent,sendError=pcall(sampSendChat,item.command)', '''-- Family aliases are local MoonLoader commands, not server commands.
            local dispatch=({fj=true,fw=true,fb=true})[kind] and sampProcessChatInput or sampSendChat
            local sent,sendError=pcall(dispatch,item.command)''')
    replace('''            if not sent then
                state.waiting=nil''','''            if not sent or sendError==false then
                state.waiting=nil''')
    replace('''    kind=kind:lower();local verbs=actions[kind];if not verbs then return false end''','''    kind=kind:lower()
    local family=({fj='jail',fw='warn',fb='ban'})[kind]
    kind=family or kind
    local verbs=actions[kind];if not verbs then return false end''')
    replace("jail={'посадил в тюрьму игрока','посадил в тюрьму','посадил игрока','посадил в КПЗ игрока'},", "jail={'посадил в тюрьму игрока','посадил в тюрьму','посадил игрока','посадил в КПЗ игрока','посадил оффлайн игрока в тюрьму','посадил оффлайн игрока'},")
    replace("if reported and reason and trim(reported):gsub('[.]$','')~=trim(reason):gsub('[.]$','')then return false end", """if reported and reason then
                    reported=trim(reported):gsub('[.]$','')
                    if family then
                        local base=reported:match('^(.-)%s+%[[^%[%]]+%]$')
                        if base then reported=trim(base)end
                    end
                    if reported~=trim(reason):gsub('[.]$','')then return false end
                end""")
    return code

if __name__=='__main__':
    from pathlib import Path
    import json,hashlib
    root=Path(__file__).resolve().parents[1]
    code=transform((root/'X-TOOL.lua').read_text('utf-8')).encode('utf-8')
    (root/'X-TOOL.lua').write_bytes(code)
    for folder in (root/'update/current',root/'update/current/versions/3.5.305'):
        (folder/'X-TOOL.lua').write_bytes(code)
        path=folder/'manifest.json';manifest=json.loads(path.read_text('utf-8'))
        manifest['script'].update(bytes=len(code),sha256=hashlib.sha256(code).hexdigest())
        path.write_bytes((json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
