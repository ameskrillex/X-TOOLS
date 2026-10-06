"""Static dialog inventory. Does not load Lua, connect to GTA, or capture credentials."""
from pathlib import Path
import hashlib
import html
import json
import re
import difflib

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'X-TOOL.lua'
raw = source.read_bytes()
code = raw.decode('utf-8')
lines = code.splitlines()
out = ROOT / 'docs/dialog-catalog'
out.mkdir(parents=True, exist_ok=True)
entries = []

def add(key, name, trigger, match, fields, response, guard, refs, category='server'):
    entries.append(dict(key=key, name=name, category=category, trigger=trigger,
        recognition=match, required_data=fields, response=response, ownership_and_limits=guard,
        source_lines=refs, cef_status='Не исследован; соответствие CEF-событиям не установлено'))

add('login','Авторизация','Вход на сервер','ID 1; заголовок Авторизация',
    'Заголовок, признак неверного пароля; секрет передаётся отдельно от каталога',
    'button=1, row=-1, input=пароль; скрыть окно при автовходе',
    'Поддерживаемый сервер, включённый автовход, проверка зашифрованного значения; сброс прав сессии', [214,43223])
add('totp','Код приложения','Вход с двухфакторной проверкой','ID 88; style 1; Код с приложения; Authenticator в тексте',
    'Имя текущего аккаунта, признак окна проверки; секрет и код не журналировать',
    'button=1, row=-1, input=одноразовый код',
    'Одна попытка; привязка к аккаунту; секрет защищён Windows', [692,703])
add('leaders','Лидеры','/leaders','ID 424; style 5; Лидеры в заголовке',
    'Табличные строки лидеров и организаций', 'Обновление чекера; опциональное закрытие через 80 мс',
    'Закрывать только распознанный ответ обновления', [7418,7653])
add('special_admins','Администраторы S уровня','Обновление чекера: /leaders, /admins, /adms',
    'ID 0; style 5; Администраторы S уровня', 'Строки ников и уровней',
    'Обновление списка; опциональное закрытие', 'Не считать ID 0 уникальным типом окна', [7339,7653])
add('account','Данные аккаунта','/get, /admget','Контекст запроса + признаки Номер аккаунта / № аккаунта / IP / Баны / Предупр',
    'Все строки аккаунта, ник, номер аккаунта, IP, наказания, время игры и AFK',
    'Разобрать в досье и скрыть штатное окно',
    'Активный запрос; исключены ID 1,66,424. leader_online отдельно требует ID 0, style 0 и заголовок=ожидаемый ник', [25581,25626,26697,4445])
add('offline_stats','Оффлайн-статистика','/offst NICK','Оффлайн статистика в заголовке либо набор полей опыта, Credits и организации/проживания/статуса',
    'Имя, Семья и остальные поля статистики', 'Досье скрывает окно; семейный обработчик затем закрывает ID 0 ответом 0,0',
    'Семейный запрос: ID 0, style 0, точный заголовок Оффлайн статистика игрока, совпадение имени и pending; досье имеет отдельный контекст', [25598,26022,20117,20227])
add('baninfo','Проверка бана','/baninfo NICK','Досье: Ник забаненного + Ник администратора + Дней до конца бана; защита бана: style 0, заголовок=цель',
    'Ник, администратор, оставшиеся дни, причина, IP; ответ об отсутствии бана',
    'Досье; защита перед баном скрывает и закрывает свой ответ',
    'Сохранить очередь и корреляцию запроса; чужой/неоднозначный ответ не разрешает наказание', [25613,25817,34808,34872])
for key, name, trigger, match, fields, refs in [
    ('iplog','История авторизаций','/iplog','Авторизации … или Дата и время + IP адрес','Строки авторизаций, даты, адреса',[25591,25760]),
    ('ip','Поиск по IP','/ip','Заголовок — валидный IP','Адрес и строки найденных аккаунтов',[25666,25680]),
    ('lip','Поиск по последнему IP','/lip','Заголовок — валидный IP','Адрес и строки найденных аккаунтов',[25669,25680]),
    ('log','Логи аккаунта','/log','Активный контекст log; исключены offst и iplog','Полный текст серверного лога',[25672,25806])]:
    add(key,name,trigger,match,fields,'Перенос в досье; скрытие окна','Активный запрос соответствующего вида и проверка прав',refs)
add('history','История ников','/history NICK','Заголовок начинается с Прошлые имена / прошлые имена',
    'Цель, строки истории, кнопка 1 с >> для следующей страницы', 'Следующая страница: button=1,row=0,input=""',
    'Только при загрузке history_preview; учитывать дедупликацию страниц и целевой аккаунт', [23998,24035,24092,24153])
add('capture_roster','Белые/зелёные ники диалога 66','Включить сбор в тулсе, затем вручную открыть диалог 66; команда в этом обработчике не задана',
    'ID 66 и активный сбор', 'Табличные ячейки ников С ЦВЕТОВЫМИ ТЕГАМИ, кнопка 2',
    'При >>: button=0,row=0,input="", задержка 250 мс',
    'Проверка сессии; белые добавляются, зелёные удаляются из исключений. Нельзя потерять семантику цвета в CEF', [13789,13822,13847,17101])
add('family_menu','Меню семьи','/family после /tempfamily либо проверка текущей семьи','style 4; заголовок Семья',
    'Строки меню, точный индекс Участники семьи', 'button=1,row=найденный индекс; выход button=0,row=-1',
    'Автомат стадий сканирования; ID берётся из ответа', [3076,20484,20555])
add('family_members','Состав семьи','Семья → Участники семьи','style 5; Список игроков в семье в заголовке',
    'Ники, заголовок таблицы, строка Далее >> или кнопка следующей страницы',
    'Строка Далее: button=1,row=index; иначе button=0,row=-1',
    'Индекс без заголовка таблицы; максимум 100 страниц; повтор/неизвестная навигация не заменяют сохранённый состав', [3091,20555])
add('square_stats','Итоги Квадрата','/fs после серверного объявления','style 5/2/0; Статистика мероприятия «Квадрат» либо без кавычек',
    'Семьи и очки; победитель и очки из сообщения сервера', 'Закрыть button=0,row=-1',
    'Сверить победителя и очки; устаревшие итоги не включать', [38894])
add('season_menu','Сезоны','/season','style 2; Сезоны', 'Строка топа семей текущего сезона, индекс и подпись',
    'button=1,row=chosen,input=label; при отсутствии — закрытие', 'Ожидаемая стадия season; чужое окно завершает неполный сбор', [38900])
add('family_top','Топ семей','Выбор пункта /season','style 0; Топ семей', 'Названия семей и очки',
    'Закрыть button=0,row=-1', 'Ожидаемая стадия top', [38904])
add('lego_list','Список LEGO','/lego','ID 688; style 4/5; lego в заголовке',
    'Строки локаций, автор, статус и прочие столбцы; страницы по кнопке 2',
    'Далее button=0,row=0; выбор button=1,row=исходный индекс',
    'До 30 страниц; перед выбором сверить имя и автора; сохранять владение поздними ответами', [22566,22614,22649])
add('lego_action','Действия локации LEGO','Выбор локации','В тексте Загрузить или убрать локацию и Удалить локацию; кнопка Выбрать',
    'Фактический ID окна и порядок действий', 'button=1,row=выбранное действие; назад button=0,row=0',
    'Только после собственного выбора; не придумывать индексы действий', [22654,22718])
add('online_time','Чистый онлайн','/c 60','Текст содержит Вы позвонили в службу точного времени',
    'Дата сервера, Время в игре сегодня/вчера, AFK за сегодня/вчера',
    'Сохранить статистику; скрыть лишь собственный ответ',
    'Уровень 2; окно ожидания 30 сек, identity и revision; ручной ответ наблюдать без скрытия', [32477,32502,34958])
add('weapon_skills','Навыки оружия','/askill','style 0; Навыки владения оружием',
    'Две группы по 11 навыков; цель из ожидающего запроса', 'Собственный ответ закрыть button=0,row=0; изменения отдельными /setskill',
    '10 сек на ответ; revision; редактирование только своего аккаунта; данные не старше минуты', [33962,33985,34008])
add('organization','Состав организации','/find; в автоматическом обходе после /templeader','ID 63; style 5; В организации N чел. (онлайн M)',
    'ID игроков, отметки На паузе, итоговые количества и страницы', 'Следующая страница button=0,row=0,input=""',
    'organizationFindWaiting; дедупликация; исключение себя; таймаут обхода 15 сек', [35011,45337,45870])
add('spectate_menu','Меню наблюдения','/sp и серверные INITMENU/SHOWMENU','Не ShowDialog: меню с STAT, UPDATE, SLAP, MUTE, WEAP, SKICK, INFO',
    'ID меню, колонки, строки, доступность, исходные номера действий', 'sampSendMenuSelect(row)',
    'Кэш INITMENU; неизвестное меню остаётся штатным. Это отдельный протокол для CEF-адаптера', [30709,30958,30973], 'server_menu')
add('casual','Настройка автоматического выхода','/casual','Локальный ID 28641; style 2',
    'Список ников и выключение', 'onSendDialogResponse; сохранить настройку, не отправлять серверу',
    'Локальное окно; не путать с CEF сервера', [18019,18022], 'local')
add('multiban_confirm','Подтверждение группового бана','Функция группового бана','Локальный ID 713; style 0',
    'Цели, срок, причина и явное подтверждение пользователя', 'sampHasDialogRespond(713)',
    'Подтверждение должно остаться явным; не эмулировать согласие', [44267,45008], 'local')
add('local_reports','Отчёты организации и KillList','Отчёт обхода организаций / список смертей','Локальный ID 700; style 0',
    'Сформированный тулсом текст', 'Закрыть', 'Локальные отчёты; один ID для разных окон', [45505,45988], 'local')

# Original catalog line numbers referred to the streamed build before the valley
# was removed. Rebase them against that reproducible in-memory source.
builder=ROOT/'tools/prepare_streamed_305.py'
reference={'__file__':str(builder)}
exec(builder.read_text('utf-8').split('from release_305_changes import transform')[0],reference)
line_map={}
for block in difflib.SequenceMatcher(None,reference['code'].splitlines(),lines,autojunk=False).get_matching_blocks():
    for offset in range(block.size):line_map[block.a+offset+1]=block.b+offset+1
for entry in entries:
    entry['source_lines']=[line_map[n] for n in entry['source_lines'] if n in line_map]

adapted={'leaders','special_admins','account','offline_stats','baninfo','ip','lip','log','history',
         'family_menu','family_members','square_stats','season_menu','family_top','lego_list',
         'online_time','weapon_skills','organization'}
for entry in entries:
    if entry['key'] in adapted:
        entry['cef_status']='Подключён в локальной CEF-сборке; проверен на записях. Проверка новой сборки в игре ещё требуется.'
    if entry['key']=='account':entry['cef_status']+=' Формат /get записан; /admget отложен.'
    if entry['key']=='weapon_skills':entry['cef_status']+=' Поддержан ответ только с базовыми навыками; отсутствующая группа не изменяется.'
    if entry['key']=='organization':entry['cef_status']+=' Учтены меню /find, «Все подразделения» и заголовок «В подразделении…».'
    if entry['key']=='iplog':entry['cef_status']='Отложен: нет записи CEF /iplog.'
    if entry['key']=='lego_action':entry['cef_status']='Нет записи меню действий. Оставлено штатное окно CEF; адаптирован список и переход к выбору.'
    if entry['key']=='login':entry['cef_status']='Отдельный мост сохранённого автовхода установлен ранее. Секреты не попадают в каталог.'

pattern = re.compile(r'onShowDialog|onSendDialogResponse|samp\w*Dialog\w*|\b\w+:dialog\(|onInitMenu|onShowMenu|onHideMenu|sampSendMenuSelect')
inventory=[]
module='bootstrap'
for n,line in enumerate(lines,1):
    found=re.search(r'sources\["([^"]+)"\] = function',line)
    if found: module=found[1]
    if line.startswith("script_name('X-Tools')"): module='core'
    if len(line)>2000 or line.lstrip().startswith('--'): continue
    if pattern.search(line):
        inventory.append(dict(line=n,module=module,code=line.strip(),
            kind='visibility_guard' if 'sampIsDialogActive' in line else 'dialog_or_menu_reference'))
catalog=dict(schema=1,version=re.search(r'CasualTool release: ([\d.]+)',code)[1],
    source='X-TOOL.lua',source_sha256=hashlib.sha256(raw).hexdigest(),
    scope='Каталог обработчиков базового скрипта и статусы локальных CEF-адаптеров. Строки относятся к базовому SHA256. Экспериментальная сборка: artifacts/cef-family-dev/X-TOOL.lua; не опубликована.',
    dialog_contract=['semantic_type','transport','session','request_owner','request_id','target','native_id','style','title','rows','columns','raw_text','color_semantics','buttons','page','actions','visible','focused'],
    adapter_requirements=['Коррелировать ответ с владельцем, целью и сессией; сохранять таймауты и права.',
        'Разделить закрытие визуального окна и отправку серверного ответа.',
        'Сохранять исходные индексы строк, заголовки таблиц, цвета и направление пагинации.',
        'Нормализовать CP1251/UTF-8 на границе; не удалять значимые цвета до разбора.',
        'Не журналировать пароли, TOTP-коды и секреты.',
        'Объединить проверки видимости и фокуса SA-MP/CEF: горячие клавиши и очереди сейчас проверяют sampIsDialogActive.',
        'Неизвестные окна оставлять пользователю; не отвечать автоматически по одному ID.'],
    entries=entries,code_references=inventory)
(out/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
esc=lambda s:html.escape(str(s))
cards=[]
for entry in entries:
    cards.append('<article><h2>'+esc(entry['name'])+' <small>'+esc(entry['key'])+'</small></h2><dl>'+''.join(
        '<dt>'+label+'</dt><dd>'+esc(entry[key])+'</dd>' for key,label in [
            ('category','Тип'),('cef_status','Состояние CEF'),('trigger','Открытие'),('recognition','Распознавание'),('required_data','Данные'),
            ('response','Ответ'),('ownership_and_limits','Контекст и ограничения'),('source_lines','Строки X-TOOL.lua')])+'</dl></article>')
page='''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>X-Tools — каталог диалогов</title><style>body{font:16px/1.5 system-ui;background:#12151c;color:#e8edf6;max-width:1100px;margin:40px auto;padding:0 24px}h1{font-size:32px}small{font-size:13px;color:#aab8cf}article{background:#1e2531;border:1px solid #38465c;border-radius:12px;padding:20px;margin:16px 0}dt{color:#8ebeff;font-weight:600}dd{margin:0 0 12px}input{padding:12px;width:90%;font:inherit}summary{cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}</style>
<h1>Каталог диалогов X-Tools</h1>'''+f'<p>Версия {esc(catalog["version"])} · {len(entries)} функциональных записей · {len(inventory)} ссылок в коде</p><p>{esc(catalog["scope"])}</p>'
page+='<input id="search" placeholder="Поиск по команде, названию, полям или ID" aria-label="Поиск"><section>'+''.join(cards)+'</section>'
page+='<h2>Требования к адаптеру</h2><ul>'+''.join('<li>'+esc(x)+'</li>' for x in catalog['adapter_requirements'])+'</ul>'
page+='<details><summary>Полный индекс обращений к диалогам и меню</summary><pre>'+esc('\n'.join(f'{r["line"]} [{r["module"]}] {r["code"]}' for r in inventory))+'</pre></details>'
page+='''<script>document.querySelector('#search').addEventListener('input',e=>{const q=e.target.value.toLowerCase();document.querySelectorAll('article').forEach(a=>a.hidden=!a.textContent.toLowerCase().includes(q))})</script></html>'''
(out/'index.html').write_text(page,encoding='utf-8')
assert len({e['key'] for e in entries})==len(entries)
assert all(1<=n<=len(lines) for e in entries for n in e['source_lines'])
print(json.dumps({'entries':len(entries),'references':len(inventory),'version':catalog['version'],'output':str(out)},ensure_ascii=False))
