#!/usr/bin/env bash
# Базовый метод KOROBEINIKOV AI — один на компьютер, общий для всех наборов. Блок между метками в личных инструкциях
# Claude (~/.claude/CLAUDE.md); всё вне меток — инструкции человека, скрипт их не меняет.
#   bash baza.sh check    — что сейчас: полный метод / стоит vN / обновить / пусто / свои правила / метки сломаны
#   bash baza.sh install  — поставить или обновить свой блок (на более старую версию не меняет)
#   bash baza.sh remove   — убрать свой блок
# Перед каждой правкой — копия прежнего файла рядом. Без python: работает на голом Mac и в Git Bash на Windows (Windows не проверено).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/BAZOVYY-METOD.md"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
F="$CFG/CLAUDE.md"
# Метки — только в полном виде комментария: упоминание их имени в тексте меткой не считается.
S='<!-- korobeinikov-ai-baza:start'; E='<!-- korobeinikov-ai-baza:end'
FULL='osnova@korobeinikov-ai-method'; FULLW='osnova@korobeinikov-ai-windows'   # полный метод: Mac и Windows
[ -f "$SRC" ] || { echo "нет файла базы: $SRC"; exit 1; }

block() { awk -v s="$S" -v e="$E" 'index($0,s){p=1} p{print} index($0,e){p=0}' "$SRC"; }
ver() { grep -m1 "$S" | sed -nE "s/.*$S v([0-9]+).*/\1/p"; }

# Полный метод включён: спросить у Claude Code список плагинов (у пакета — «enabled»); нет команды — по настройкам
# (`"<пакет>": true`). Выключенный пакет правил не даёт — тогда база нужна. Файлы не печатаем: там бывают ключи.
full() {
  local c st
  for c in "$(command -v claude 2>/dev/null)" \
           "$(ls -d "$HOME"/Library/Application\ Support/Claude/claude-code/*/*/claude.app/Contents/MacOS/claude 2>/dev/null | sort -V | tail -1)" \
           "$HOME/.local/bin/claude.exe" \
           "$(find "$HOME/AppData/Roaming/Claude" "$HOME/AppData/Local/AnthropicClaude" -maxdepth 6 -iname claude.exe -path '*claude-code*' 2>/dev/null | sort | tail -1)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    st=$("$c" plugin list 2>/dev/null | awk -v f="$FULL" -v w="$FULLW" '(index($0,f)||index($0,w)){p=1;next} p&&/Status:/{print; exit}')
    case "$st" in *disabled*) ;; *enabled*) return 0 ;; esac
    break
  done
  grep -qsE "\"($FULL|$FULLW)\"[[:space:]]*:[[:space:]]*true" "$CFG/settings.json"
}

mine=$(block | ver); mine=${mine:-0}
[ "$mine" -gt 0 ] || { echo "в $SRC нет блока базы с версией"; exit 1; }
[ "$(grep -c "korobeinikov-ai-baza:" "$SRC")" = 2 ] || { echo "в $SRC имя метки встречается не дважды — поправь текст"; exit 1; }
nstart=0; have=0; valid=yes; own=0
if [ -f "$F" ]; then
  nstart=$(grep -c "$S" "$F" || true)
  have=$(ver < "$F"); have=${have:-0}
  valid=$(awk -v s="$S" -v e="$E" 'index($0,s){if(p)b=1;p=1} index($0,e){if(!p)b=1;p=0} END{print (b||p)?"no":"yes"}' "$F")
  own=$(awk -v s="$S" -v e="$E" 'index($0,s){p=1;next} index($0,e){p=0;next} !p&&NF{n++} END{print n+0}' "$F")
fi
rules=$(ls "$CFG"/rules/*.md 2>/dev/null | wc -l | tr -d ' ')

backup() {
  [ -s "$F" ] || return 0
  local b n=1; b="$F.bak-korobeinikov-$(date +%Y%m%d-%H%M%S)"
  while [ -e "$b" ]; do b="${b%-[0-9]}-$n"; n=$((n+1)); done
  cp "$F" "$b" && echo "копия прежнего файла: $b"
}
writable() { [ ! -e "$F" ] || [ -w "$F" ] || { echo "не могу записать $F — нет прав, ничего не менял"; return 1; }; }
# Без своего блока; хвостовые пустые строки — тоже (их добавил install). Запись поверх — ссылка на файл и права остаются.
strip() {
  local t; t=$(mktemp)
  awk -v s="$S" -v e="$E" 'index($0,s){p=1;next} p&&index($0,e){p=0;next} p{next}
       /^[[:space:]]*$/{q=q $0 "\n"; next} {printf "%s", q; q=""; print}' "$F" > "$t" && cat "$t" > "$F"
  local r=$?; rm -f "$t"; return $r
}

check() {
  if full; then
    if [ "$nstart" -gt 0 ]; then echo "полный метод — блок базы есть, убрать: bash baza.sh remove"
    else echo "полный метод — база не нужна"; fi
  elif [ "$valid" != yes ]; then echo "метки сломаны: $F"
  elif [ "$nstart" -eq 1 ] && [ "$have" -ge "$mine" ]; then echo "стоит v$have"
  elif [ "$nstart" -ge 1 ]; then echo "обновить v$have → v$mine"
  elif [ "$own" -gt 0 ] || [ "$rules" -gt 0 ]; then
    echo "свои правила: $F — $own строк$([ "$rules" -gt 0 ] && echo ", и ещё файлов в $CFG/rules: $rules")"
  else echo "пусто"; fi
}

install() {
  if full; then echo "полный метод — базу не ставлю"; return 0; fi
  [ "$valid" = yes ] || { echo "метки сломаны: $F — не трогаю"; return 1; }
  if [ "$nstart" -eq 1 ] && [ "$have" -ge "$mine" ]; then echo "стоит v$have — без изменений"; return 0; fi
  writable || return 1
  mkdir -p "$CFG" || { echo "не могу создать $CFG"; return 1; }
  backup
  local was=$nstart
  if [ "$was" -ge 1 ]; then strip || { echo "не могу записать $F"; return 1; }; fi
  { if [ -s "$F" ]; then [ -n "$(tail -c1 "$F")" ] && printf '\n'; printf '\n'; fi; block; } >> "$F" \
    || { echo "не могу записать $F"; return 1; }
  if [ "$was" -ge 1 ]; then echo "обновил v$have → v$mine: $F"; else echo "поставил v$mine: $F"; fi
}

remove() {
  [ "$nstart" -gt 0 ] || { echo "блока базы нет"; return 0; }
  [ "$valid" = yes ] || { echo "метки сломаны: $F — не трогаю"; return 1; }
  writable || return 1
  backup; strip || { echo "не могу записать $F"; return 1; }; echo "убрал блок базы: $F"
}

case "${1:-check}" in
  check) check ;; install) install ;; remove) remove ;;
  *) echo "bash baza.sh check | install | remove"; exit 1 ;;
esac
