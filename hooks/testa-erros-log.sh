#!/bin/bash
# Teste do log de erros de ferramenta (scripts/erros.cjs) e da linha do /saude.
# Uso: bash hooks/testa-erros-log.sh
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$CAIXA_POSIX" 2>/dev/null || printf '%s' "$CAIXA_POSIX")"
trap 'rm -rf "$CAIXA_POSIX"' EXIT
export RFM_ROOT="$RAIZ"
ok=0; falhou=0
checa() { if [ "$2" = "$3" ]; then echo "ok   $1"; ok=$((ok+1)); else echo "FALHA $1: esperado [$3], veio [$2]"; falhou=$((falhou+1)); fi; }
E="$SRC/scripts/erros.cjs"

node "$E" contar > "$CAIXA_POSIX/c0"; checa "contar sem arquivo" "$(cat "$CAIXA_POSIX/c0")" '{"total":0,"erro":0,"bloqueio":0}'

printf '{"sessao":"s1","cwd":"C:/x/proj","ferramenta":"Bash","tipo":"erro","comando":"ls nada","mensagem":"Exit code 2\\nls: nada: No such file"}' | node "$E" gravar; checa "gravar erro exit" "$?" "0"
printf '{"sessao":"s1","cwd":"C:/x/proj","ferramenta":"Bash","tipo":"bloqueio","comando":"gh pr create","mensagem":"BLOQUEADO pelo gate"}' | node "$E" gravar; checa "gravar bloqueio exit" "$?" "0"
printf '{"ferramenta":"Bash","tipo":"outro"}' | node "$E" gravar 2>/dev/null; checa "tipo invalido recusa com exit 2" "$?" "2"
printf 'nao e json' | node "$E" gravar 2>/dev/null; checa "entrada nao-JSON recusa com exit 2" "$?" "2"
checa "duas linhas no arquivo" "$(wc -l < "$CAIXA_POSIX/erros.jsonl" | tr -d ' ')" "2"
checa "mensagem sem quebra de linha" "$(node -e "console.log(JSON.parse(require('fs').readFileSync('$RAIZ/erros.jsonl','utf8').split('\n')[0]).mensagem)")" "Exit code 2 ls: nada: No such file"

# linha velha (48 h) fica fora da janela de 24 h
node -e "require('fs').appendFileSync('$RAIZ/erros.jsonl', JSON.stringify({ts:new Date(Date.now()-48*3600e3).toISOString(),tipo:'erro',ferramenta:'Read'})+'\n')"
checa "contar 24 h ignora a velha" "$(node "$E" contar)" '{"total":2,"erro":1,"bloqueio":1}'
checa "contar 72 h pega a velha" "$(node "$E" contar --horas 72)" '{"total":3,"erro":2,"bloqueio":1}'

L=$(node "$E" listar)
checa "listar mostra o comando" "$(printf '%s' "$L" | grep -c 'Bash ls nada')" "1"
checa "listar separa bloqueios" "$(printf '%s' "$L" | grep -c '^Bloqueios')" "1"

S=$(node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const a=JSON.parse(d).find(x=>x.item==='erros de ferramenta');console.log(a?a.nivel+' '+a.detalhe:'ausente')})")
checa "saude avisa com a contagem" "$S" "aviso 2 nas ultimas 24 h (1 erro(s), 1 bloqueio(s))"

# segredo nunca chega ao disco
printf %s "{\"sessao\":\"s2\",\"cwd\":\"C:/x/p\",\"ferramenta\":\"Bash\",\"tipo\":\"erro\",\"comando\":\"curl -H Authorization:Bearer_abcdefghijklmnop https://luis:SenhaUrl99@h/x --password Segr3d0\",\"mensagem\":\"token ghp_abcdefghijklmnopqrstuvwx1234 invalido\"}" | node "$E" gravar
for seg in abcdefghijklmnop SenhaUrl99 Segr3d0 ghp_abcdefghijklmnopqrstuvwx1234; do
  checa "segredo $seg fora do arquivo" "$(grep -c "$seg" "$CAIXA_POSIX/erros.jsonl")" "0"
done
checa "comando mascarado continua legivel" "$(grep -c "curl -H" "$CAIXA_POSIX/erros.jsonl")" "1"

echo "placar: $ok ok, $falhou falha(s)"
[ "$falhou" -eq 0 ]
