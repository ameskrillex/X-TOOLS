-- Correlate server results with a request actually sent by auto-issue.
local M={}
local function clean(s)
    return tostring(s or ''):gsub('{%x%x%x%x%x%x}',''):gsub('^%s*%[%d%d%.%d%d%.%d%d%d%d %d%d:%d%d:%d%d%]%s*',''):match('^%s*(.-)%s*$')
end
function M.normalize(command)
    command=clean(command)
    local kind,target,rest=command:match('^(/%a+)%s+(%S+)%s+(.+)$')
    if target and not target:match('^%d+$') then
        if kind=='/warn' then return '/offwarn '..target..' '..rest,true end
        if kind=='/ban' and rest:match('^%d+%s+.+$') then return '/offban '..target..' '..rest,true end
    end
    return command,false
end
function M.reply(context,text,now,localName)
    if not context or not context.sent_at or now-context.sent_at>8 or now<context.sent_at then return end
    local admin=clean(context.admin_name):gsub('%[%d+%]$','')
    if admin=='' then return end
    -- Address the requester by their first name, as in the admin-chat convention.
    admin=admin:match('^([^_ ]+)') or admin
    text=clean(text)
    if text:match('^Такого игрока нет в базе данных[%.!]*$') then
        return admin..', такого игрока нет в базе данных.'
    end
    local kind=context.kind
    if (kind=='/warn' or kind=='/offwarn') and
        text:match('^Этот игрок забанен%. Выдать предупреждение забаненному игроку нельзя[%.!]*$') then
        return admin..', этот игрок заблокирован.'
    end
    if kind~='/unban' and kind~='/unwarn' then return end
    if kind=='/unwarn' and text:match('^У этого игрока нет предупреждений[%.!]*$') then
        return admin..', у этого игрока нет предупреждений.'
    end
    local target=clean(context.target_name)
    if target=='' then return end
    local named
    if kind=='/unban' then
        named=text:match('^Аккаунт ([%w_%.]+) разблокирован[%.!]*$')
            or text:match('^Вы разблокировали аккаунт ([%w_%.]+)[%.!]*$')
    else
        named=text:match('^Предупреждение игрока ([%w_%.]+) снято[%.!]*$')
            or text:match('^Вы сняли предупреждение игроку ([%w_%.]+)[%.!]*$')
    end
    if not named then
        local issuer,who
        if kind=='/unban' then
            issuer,who=text:match('^%[A%]%s+(%S+)%[%d+%]%s+разбанил игрока ([%w_%.]+)%s+%(аккаунт %d+%)[%.!]*$')
            if not issuer then issuer,who=text:match('^%[A%]%s+(%S+)%[%d+%]%s+разбанил игрока ([%w_%.]+)[%.!]*$') end
            if not issuer then issuer,who=text:match('^Администратор (%S+) разблокировал аккаунт ([%w_%.]+)[%.!]*$') end
        else
            issuer,who=text:match('^%[A%]%s+(%S+)%[%d+%]%s+снял %d+ предупреждени.- игроку ([%w_%.]+)%[%d+%][%.!]*$')
            if not issuer then issuer,who=text:match('^%[A%]%s+(%S+)%[%d+%]%s+снял предупреждение игроку ([%w_%.]+)[%.!]*$') end
            if not issuer then issuer,who=text:match('^Администратор (%S+) снял предупреждение игроку ([%w_%.]+)[%.!]*$') end
        end
        if issuer and clean(issuer):gsub('%[%d+%]$',''):lower()==clean(localName):lower() then named=who end
    end
    if not named or named:lower()~=target:lower() then return end
    if kind=='/unban' then return admin..', аккаунт '..target..' разблокирован.' end
    return admin..', предупреждение у '..target..' снято.'
end
return M
