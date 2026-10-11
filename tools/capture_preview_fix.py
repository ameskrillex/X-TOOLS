def transform(code):
    old='''function buildCaptureTopOverlayEntries()
    if not STATE.capture.active then
        return {}
    end
    return DATA.captureTopOverlayEntries or {}
end'''
    new='''function buildCaptureTopOverlayEntries()
    if STATE.capture.active then return DATA.captureTopOverlayEntries or {} end
    if DATA.overlayTestActive then
        -- Illustrative rows only: never add preview kills to capture statistics.
        return {
            {index=1,id=-1,nick="Предпросмотр: игрок 1",kills=12},
            {index=2,id=-1,nick="Предпросмотр: игрок 2",kills=9},
            {index=3,id=-1,nick="Предпросмотр: игрок 3",kills=7},
            {index=4,id=-1,nick="Предпросмотр: игрок 4",kills=5},
            {index=5,id=-1,nick="Предпросмотр: игрок 5",kills=3},
            {index=6,id=-1,nick="Предпросмотр: игрок 6",kills=1}
        }
    end
    return {}
end'''
    assert code.count(old)==1
    return code.replace(old,new)

if __name__=='__main__':
    from pathlib import Path
    import hashlib,json
    root=Path(__file__).resolve().parents[1]
    code=transform((root/'X-TOOL.lua').read_text('utf-8')).encode('utf-8')
    (root/'X-TOOL.lua').write_bytes(code)
    for folder in (root/'update/current',root/'update/current/versions/3.5.305'):
        (folder/'X-TOOL.lua').write_bytes(code)
        path=folder/'manifest.json';m=json.loads(path.read_text('utf-8'))
        m['script'].update(bytes=len(code),sha256=hashlib.sha256(code).hexdigest())
        path.write_bytes((json.dumps(m,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
