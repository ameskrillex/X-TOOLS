"""Readable kill feed and actual registered follow binding."""
def transform(code):
    start=code.index('    local hotkeyText = formatHotkeyText(')
    end=code.index('\nend\n',start)
    code=code[:start]+'    local hotkeyText = integration.keys:name(\'capture_follow\')\n    chat(COLORS.ACCENT .. "Следить за " .. colorizeName(killerId, killerName) ..\n        COLORS.ACCENT .. " — нажмите " .. COLORS.WHITE .. hotkeyText .. COLORS.ACCENT .. ".")'+code[end:]
    old='"%s - %s | оружие: %s"'
    assert code.count(old)==1
    return code.replace(old, '"%s {FFFFFF}убил %s {FFFFFF}| оружие: %s"')
