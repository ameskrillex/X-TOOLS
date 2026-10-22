local M={}
local map={["ё"]="`",[184]="`",["Ё"]="`",[168]="`",["й"]="q",[233]="q",["Й"]="q",[201]="q",["ц"]="w",[246]="w",["Ц"]="w",[214]="w",["у"]="e",[243]="e",["У"]="e",[211]="e",["к"]="r",[234]="r",["К"]="r",[202]="r",["е"]="t",[229]="t",["Е"]="t",[197]="t",["н"]="y",[237]="y",["Н"]="y",[205]="y",["г"]="u",[227]="u",["Г"]="u",[195]="u",["ш"]="i",[248]="i",["Ш"]="i",[216]="i",["щ"]="o",[249]="o",["Щ"]="o",[217]="o",["з"]="p",[231]="p",["З"]="p",[199]="p",["х"]="[",[245]="[",["Х"]="[",[213]="[",["ъ"]="]",[250]="]",["Ъ"]="]",[218]="]",["ф"]="a",[244]="a",["Ф"]="a",[212]="a",["ы"]="s",[251]="s",["Ы"]="s",[219]="s",["в"]="d",[226]="d",["В"]="d",[194]="d",["а"]="f",[224]="f",["А"]="f",[192]="f",["п"]="g",[239]="g",["П"]="g",[207]="g",["р"]="h",[240]="h",["Р"]="h",[208]="h",["о"]="j",[238]="j",["О"]="j",[206]="j",["л"]="k",[235]="k",["Л"]="k",[203]="k",["д"]="l",[228]="l",["Д"]="l",[196]="l",["ж"]=";",[230]=";",["Ж"]=";",[198]=";",["э"]="'",[253]="'",["Э"]="'",[221]="'",["я"]="z",[255]="z",["Я"]="z",[223]="z",["ч"]="x",[247]="x",["Ч"]="x",[215]="x",["с"]="c",[241]="c",["С"]="c",[209]="c",["м"]="v",[236]="v",["М"]="v",[204]="v",["и"]="b",[232]="b",["И"]="b",[200]="b",["т"]="n",[242]="n",["Т"]="n",[210]="n",["ь"]="m",[252]="m",["Ь"]="m",[220]="m",["б"]=",",[225]=",",["Б"]=",",[193]=",",["ю"]=".",[254]=".",["Ю"]=".",[222]="."}
function M.convert(text, utf8)
    if type(text)~='string' then return text end
    local prefix,token,tail=text:match('^([/.])([^%s]+)(.*)$')
    if not token then return text end
    if prefix=='.' and (token:sub(1,1)=='.' or token:sub(1,1)=='/' or token:match('^%d'))then return text end
    local changed=prefix=='.'
    -- Native outgoing commands use CP1251; UTF-8 callers opt in explicitly.
    local out={};local i=1
    while i<=#token do
        local ch=token:sub(i,i);local value
        if utf8 and (token:byte(i)==208 or token:byte(i)==209)then
            ch=token:sub(i,i+1);value=map[ch];i=i+2
        else value=not utf8 and map[token:byte(i)] or nil;i=i+1 end
        if value then changed=true;out[#out+1]=value else out[#out+1]=ch end
    end
    return changed and ('/'..table.concat(out):lower()..tail) or text
end
return M
