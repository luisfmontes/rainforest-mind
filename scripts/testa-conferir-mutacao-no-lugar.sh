#!/bin/bash
# Bateria do modo no lugar de scripts/conferir-mutacao.cjs (#527, #569; plano
# 2026-10-21-mutacao-no-lugar, tarefas 1 a 4 e 8 a 14, e 16).
# Uso: bash scripts/testa-conferir-mutacao-no-lugar.sh
#
# Cada caso monta um repo git descartavel com `src.js` commitado e uma bateria
# `node teste.js` que le `src.js`. O temporario de cada caso e isolado
# (TMPDIR/TEMP/TMP), porque o backup do modo no lugar mora la.
#
# O que precisa provar:
#   N1/N2  com --no-lugar a bateria roda na arvore real (marcador do sonda.js), o
#          veredito sai (0 vermelho, 2 verde) e src.js volta ao sha256 de antes;
#   N3     bateria presa a raiz real (cwd conferido) so mede no lugar;
#   N4     sem --no-lugar a copia segue: o fonte real nao muda durante a bateria;
#   N5     estouro de tempo sai 1 e restaura;
#   S1/S2  alvo sujo recusa (4) sem rodar a bateria; fora de repo mede e avisa;
#   O1/O2  backup orfao de PID morto: restaurado se o arquivo ainda e o mutante,
#          intocado (e o backup fica) se mudou depois;
#   O3-O5  backup plantado para outro arquivo nao escreve nele; backup de PID vivo
#          nao e restaurado; backup orfao de arquivo ja original sai sem aviso;
#   R1-R4  restauracao que falha sai 1; alvo somente-leitura nao deixa backup;
#          edicao durante o baseline (4) ou a bateria (1) nao e sobrescrita;
#   I1/G1/G2  alvo ignorado, git status que falha e .git/HEAD corrompido recusam;
#   V1/V2  backup de PID vivo recusa (4); a execucao no lugar avisa que o fonte
#          fica mutado durante a bateria.
# Nenhum caso afirma sobre o texto do fonte.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CM="$SRC/scripts/conferir-mutacao.cjs"
OK=0; FALHOU=0
SANDBOXES=()
LIMPAR_PIDS=()
cleanup() {
  for p in "${LIMPAR_PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done
}
trap cleanup EXIT

passa() { OK=$((OK + 1)); echo "  ok    $1"; }
falha() { FALHOU=$((FALHOU + 1)); echo "  FALHA $1"; }
confere() { if [ "$2" = "$3" ]; then passa "$1"; else falha "$1 (esperado '$3', veio '$2')"; fi; }
contem() { if grep -qF -- "$3" "$2"; then passa "$1"; else falha "$1 (sem '$3' em $(head -c 600 "$2" | tr '\n' ' '))"; fi; }

mixto() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
sha() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"; }

# novo_caso <com_git: 1|0>: cria CASO (pasta), R (repo, forma mista), TMPC
# (temporario isolado) e o par src.js / teste.js / sonda.js.
novo_caso() {
  CASO=$(mktemp -d); SANDBOXES+=("$CASO")
  mkdir -p "$CASO/repo" "$CASO/tmp"
  R=$(mixto "$CASO/repo"); TMPC=$(mixto "$CASO/tmp"); MARCA="$(mixto "$CASO")/marca"
  printf 'module.exports = (a) => a + 1;\n' > "$CASO/repo/src.js"
  printf "const f = require('./src.js');\nif (f(1) !== 2) { console.log('FALHA f(1) = ' + f(1)); console.log('ok: 0   falhou: 1'); process.exit(1); }\nconsole.log('ok: 1   falhou: 0');\n" > "$CASO/repo/teste.js"
  # sonda.js: grava MARCA quando o src.js REAL (caminho absoluto) esta mutado.
  printf "const fs = require('fs');\nif (!fs.readFileSync(process.env.SRC_REAL, 'utf8').includes('a + 1')) fs.writeFileSync(process.env.MARCA, 'mutado');\n" > "$CASO/repo/sonda.js"
  if [ "$1" = "1" ]; then
    git -C "$CASO/repo" init -q
    git -C "$CASO/repo" config core.autocrlf false
    git -C "$CASO/repo" -c user.name=t -c user.email=t@t add -A
    git -C "$CASO/repo" -c user.name=t -c user.email=t@t commit -qm base
  fi
  SHA0=$(sha "$CASO/repo/src.js")
}

# roda <saida-prefixo> [args...]: conferir-mutacao no temporario do caso.
roda() {
  local pre="$1"; shift
  TMPDIR="$TMPC" TEMP="$TMPC" TMP="$TMPC" SRC_REAL="$R/src.js" MARCA="$MARCA" R_REAL="$R" \
    node "$CM" --raiz "$R" --arquivo src.js "$@" > "$pre.out" 2> "$pre.err" < /dev/null
  echo $?
}

backups() { ls "$CASO/tmp" 2>/dev/null | grep -c '^conferir-mutacao-nolugar-' || true; }

# grava_backup <pid> <conteudo-atual>: backup no formato do script, com o nome
# que o script calcula para o alvo; src.js passa a ter <conteudo-atual>.
grava_backup() {
  node -e '
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const [tmp, alvoRel, raiz, pid, atual] = process.argv.slice(1);
const alvo = path.resolve(raiz, alvoRel);
const original = fs.readFileSync(alvo);
const mutado = Buffer.from("module.exports = (a) => a + 2;\n");
const chave = process.platform === "win32" ? alvo.toLowerCase() : alvo;
const nome = "conferir-mutacao-nolugar-" + crypto.createHash("sha1").update(chave).digest("hex") + ".json";
fs.writeFileSync(path.join(tmp, nome), JSON.stringify({ caminho: alvo, original: original.toString("base64"),
  hashMutado: crypto.createHash("sha256").update(mutado).digest("hex"), pid: Number(pid) }));
fs.writeFileSync(alvo, atual === "mutado" ? mutado : Buffer.from(atual));
' "$TMPC" src.js "$R" "$1" "$2"
}

BAT_SONDA='node sonda.js; node teste.js'

echo "== N1: --no-lugar, bateria vermelha, arvore real mutada durante a bateria, restaurada =="
novo_caso 1
EX=$(roda "$CASO/n1" --no-lugar --de 'a + 1' --para 'a + 2' --bateria "$BAT_SONDA")
confere "N1 exit 0 (bateria sabe falhar)" "$EX" "0"
confere "N1 src.js volta ao sha256 de antes" "$(sha "$CASO/repo/src.js")" "$SHA0"
confere "N1 a bateria viu o src.js REAL mutado (sem copia)" "$(cat "$CASO/marca" 2>/dev/null)" "mutado"
confere "N1 nenhum backup sobra no temporario" "$(backups)" "0"
echo "== V2: o stderr avisa que o fonte real fica mutado durante a bateria =="
contem "V2 aviso de fonte real mutado" "$CASO/n1.err" "fica MUTADO no fonte real"

echo "== N2: --no-lugar, bateria que nao mede o trecho sai 2 e restaura =="
novo_caso 1
EX=$(roda "$CASO/n2" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node -e "console.log(1)"')
confere "N2 exit 2 (bateria verde com o mutante)" "$EX" "2"
confere "N2 src.js volta ao sha256 de antes" "$(sha "$CASO/repo/src.js")" "$SHA0"

echo "== N3: bateria presa a raiz real so mede no lugar =="
novo_caso 1
BAT_CWD='node -e "const fs=require(\"fs\");const n=p=>fs.realpathSync(p).toLowerCase();process.exit(n(process.cwd())===n(process.env.R_REAL)?0:1)" && node teste.js'
EX=$(roda "$CASO/n3" --no-lugar --de 'a + 1' --para 'a + 2' --bateria "$BAT_CWD")
confere "N3 com --no-lugar mede (exit 0)" "$EX" "0"
confere "N3 src.js restaurado" "$(sha "$CASO/repo/src.js")" "$SHA0"
EX=$(roda "$CASO/n3b" --de 'a + 1' --para 'a + 2' --bateria "$BAT_CWD")
confere "N3 sem --no-lugar a mesma bateria nao mede na copia (exit 4)" "$EX" "4"

echo "== N4: sem --no-lugar a copia segue e o fonte real nao muda =="
novo_caso 1
EX=$(roda "$CASO/n4" --de 'a + 1' --para 'a + 2' --bateria "$BAT_SONDA")
confere "N4 exit 0 pela copia" "$EX" "0"
confere "N4 a bateria nunca viu o src.js real mutado" "$(cat "$CASO/marca" 2>/dev/null || echo ausente)" "ausente"
confere "N4 src.js intocado" "$(sha "$CASO/repo/src.js")" "$SHA0"

echo "== N5: estouro de tempo no lugar sai 1 e restaura =="
novo_caso 1
BAT_PENDURA='node teste.js || node -e "setTimeout(()=>{},20000)"'
EX=$(roda "$CASO/n5" --no-lugar --timeout 6000 --de 'a + 1' --para 'a + 2' --bateria "$BAT_PENDURA")
confere "N5 exit 1 (sem veredito)" "$EX" "1"
confere "N5 src.js restaurado" "$(sha "$CASO/repo/src.js")" "$SHA0"
confere "N5 nenhum backup sobra" "$(backups)" "0"

echo "== S1: alvo com mudanca nao commitada recusa sem rodar a bateria =="
novo_caso 1
printf 'module.exports = (a) => a + 1; // sujo\n' > "$CASO/repo/src.js"
SUJO=$(sha "$CASO/repo/src.js")
EX=$(roda "$CASO/s1" --no-lugar --de 'a + 1' --para 'a + 2' --bateria "$BAT_SONDA")
confere "S1 exit 4" "$EX" "4"
contem "S1 stderr diz que ha mudanca nao commitada" "$CASO/s1.err" "não commitada"
confere "S1 src.js sujo intacto" "$(sha "$CASO/repo/src.js")" "$SUJO"
confere "S1 a bateria nao rodou" "$(cat "$CASO/marca" 2>/dev/null || echo ausente)" "ausente"

echo "== S2: fora de repo git mede e avisa =="
novo_caso 0
EX=$(roda "$CASO/s2" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "S2 exit 0" "$EX" "0"
contem "S2 stderr avisa que nao e repositorio git" "$CASO/s2.err" "não é repositório git"
confere "S2 src.js restaurado" "$(sha "$CASO/repo/src.js")" "$SHA0"

echo "== O1: backup orfao com o arquivo ainda mutado e restaurado na abertura =="
novo_caso 1
grava_backup 999999 mutado
EX=$(roda "$CASO/o1" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "O1 src.js volta ao original" "$(sha "$CASO/repo/src.js")" "$SHA0"
contem "O1 stderr avisa a restauracao" "$CASO/o1.err" "restaurei"
confere "O1 backup apagado" "$(backups)" "0"
confere "O1 a execucao seguinte mede (exit 0)" "$EX" "0"

echo "== O2: backup orfao com o arquivo mudado depois fica, e o arquivo nao e tocado =="
novo_caso 1
grava_backup 999999 'outra coisa'
OUTRA=$(sha "$CASO/repo/src.js")
EX=$(roda "$CASO/o2" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "O2 src.js intocado" "$(sha "$CASO/repo/src.js")" "$OUTRA"
confere "O2 backup permanece" "$(backups)" "1"
contem "O2 stderr nomeia o backup orfao" "$CASO/o2.err" "conferir-mutacao-nolugar-"
confere "O2 nada foi medido (exit 4)" "$EX" "4"

echo "== O3: backup com o nome do alvo mas apontando outro arquivo nao escreve nele =="
novo_caso 1
printf 'module.exports = (a) => a + 2;\n' > "$CASO/repo/outro.js"
OUTRO=$(sha "$CASO/repo/outro.js")
node -e '
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const [tmp, raiz] = process.argv.slice(1);
const alvo = path.resolve(raiz, "src.js"), outro = path.resolve(raiz, "outro.js");
const chave = process.platform === "win32" ? alvo.toLowerCase() : alvo;
const nome = "conferir-mutacao-nolugar-" + crypto.createHash("sha1").update(chave).digest("hex") + ".json";
fs.writeFileSync(path.join(tmp, nome), JSON.stringify({ caminho: outro, original: Buffer.from("plantado\n").toString("base64"),
  hashMutado: crypto.createHash("sha256").update(fs.readFileSync(outro)).digest("hex"), pid: 999999 }));
' "$TMPC" "$R"
EX=$(roda "$CASO/o3" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "O3 outro.js intocado pelo backup plantado" "$(sha "$CASO/repo/outro.js")" "$OUTRO"
confere "O3 src.js intocado" "$(sha "$CASO/repo/src.js")" "$SHA0"

echo "== O4: backup de PID vivo com o arquivo mutado nao e restaurado por outra execucao =="
novo_caso 1
PIDF4="$(mixto "$CASO")/pid"
node -e 'require("fs").writeFileSync(process.argv[1], String(process.pid)); setTimeout(() => {}, 60000)' "$PIDF4" &
LIMPAR_PIDS+=("$!")
for _ in $(seq 1 50); do [ -s "$CASO/pid" ] && break; sleep 0.1; done
grava_backup "$(cat "$CASO/pid")" mutado
MUT=$(sha "$CASO/repo/src.js")
EX=$(roda "$CASO/o4" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "O4 src.js segue o mutante da execucao viva" "$(sha "$CASO/repo/src.js")" "$MUT"
confere "O4 backup da execucao viva permanece" "$(backups)" "1"
confere "O4 nada foi medido (exit 4)" "$EX" "4"

echo "== O5: backup orfao com o arquivo ja original sai sem alarde =="
novo_caso 1
grava_backup 999999 'module.exports = (a) => a + 1;
'
EX=$(roda "$CASO/o5" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "O5 backup apagado" "$(backups)" "0"
confere "O5 mede normalmente (exit 0)" "$EX" "0"
if grep -q 'backup órfão' "$CASO/o5.err"; then falha "O5 avisou backup orfao sem motivo"; else passa "O5 sem aviso de backup orfao"; fi

echo "== R1: restauracao que falha sai 1 e preserva o backup =="
novo_caso 1
BAT_TRAVA='node -e "const fs=require(\"fs\");if(fs.readFileSync(\"src.js\",\"utf8\").includes(\"a + 2\"))fs.chmodSync(\"src.js\",0o444)"; node teste.js'
EX=$(roda "$CASO/r1" --no-lugar --de 'a + 1' --para 'a + 2' --bateria "$BAT_TRAVA")
confere "R1 exit 1" "$EX" "1"
contem "R1 stderr diz FALHA AO RESTAURAR" "$CASO/r1.err" "FALHA AO RESTAURAR"
confere "R1 backup preservado" "$(backups)" "1"
chmod u+w "$CASO/repo/src.js" 2>/dev/null; node -e 'require("fs").chmodSync(process.argv[1],0o644)' "$R/src.js"

echo "== R2: alvo somente-leitura: nada mutado, backup nao sobra, proxima execucao mede =="
novo_caso 1
node -e 'require("fs").chmodSync(process.argv[1],0o444)' "$R/src.js"
EX=$(roda "$CASO/r2" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "R2 exit 1 (nao deu para mutar)" "$EX" "1"
confere "R2 src.js intocado" "$(sha "$CASO/repo/src.js")" "$SHA0"
confere "R2 backup nao sobra" "$(backups)" "0"
if grep -q 'FALHA AO RESTAURAR' "$CASO/r2.err"; then falha "R2 acusou falha de restauracao falsa"; else passa "R2 sem falha de restauracao falsa"; fi
node -e 'require("fs").chmodSync(process.argv[1],0o644)' "$R/src.js"
EX=$(roda "$CASO/r2b" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "R2 com a permissao de volta, mede (exit 0)" "$EX" "0"

echo "== R3: arquivo editado durante o baseline nao e mutado =="
novo_caso 1
BAT_EDITA='node -e "const fs=require(\"fs\");const t=fs.readFileSync(\"src.js\",\"utf8\");if(!t.includes(\"EDICAO\"))fs.appendFileSync(\"src.js\",\"// EDICAO\\n\")"; node teste.js'
EX=$(roda "$CASO/r3" --no-lugar --de 'a + 1' --para 'a + 2' --bateria "$BAT_EDITA")
confere "R3 exit 4" "$EX" "4"
if grep -q 'EDICAO' "$CASO/repo/src.js"; then passa "R3 a edicao ficou no arquivo"; else falha "R3 a edicao sumiu"; fi
contem "R3 stderr diz que mudou durante o baseline" "$CASO/r3.err" "mudou durante o baseline"

echo "== R4: arquivo editado durante a bateria pos-mutacao nao e sobrescrito =="
novo_caso 1
BAT_EDITA_POS='node -e "const fs=require(\"fs\");const t=fs.readFileSync(\"src.js\",\"utf8\");if(t.includes(\"a + 2\")&&!t.includes(\"EDICAO\"))fs.appendFileSync(\"src.js\",\"// EDICAO\\n\")"; node teste.js'
EX=$(roda "$CASO/r4" --no-lugar --de 'a + 1' --para 'a + 2' --bateria "$BAT_EDITA_POS")
confere "R4 exit 1" "$EX" "1"
if grep -q 'EDICAO' "$CASO/repo/src.js"; then passa "R4 a edicao ficou no arquivo"; else falha "R4 a edicao foi sobrescrita"; fi
contem "R4 stderr diz que mudou durante a bateria" "$CASO/r4.err" "mudou durante a bateria"
confere "R4 backup preservado" "$(backups)" "1"

if grep -q 'fonte foi restaurado' "$CASO/r4.out"; then falha "R4 stdout afirma restauracao que nao houve"; else passa "R4 stdout nao afirma restauracao"; fi

echo "== U1: alvo nao rastreado recusa mesmo com status.showUntrackedFiles=no =="
novo_caso 1
git -C "$CASO/repo" config status.showUntrackedFiles no
printf 'module.exports = (a) => a + 1;\n' > "$CASO/repo/novo.js"
EX=$(TMPDIR="$TMPC" TEMP="$TMPC" TMP="$TMPC" node "$CM" --raiz "$R" --arquivo novo.js --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node -e "process.exit(0)"' > "$CASO/u1.out" 2> "$CASO/u1.err" < /dev/null; echo $?)
confere "U1 exit 4" "$EX" "4"
contem "U1 stderr diz que nao e rastreado" "$CASO/u1.err" "não é rastreado"

echo "== I1: alvo ignorado pelo git recusa =="
novo_caso 1
printf 'module.exports = (a) => a + 1;\n' > "$CASO/repo/ign.js"
printf 'ign.js\n' > "$CASO/repo/.gitignore"
git -C "$CASO/repo" -c user.name=t -c user.email=t@t add .gitignore
git -C "$CASO/repo" -c user.name=t -c user.email=t@t commit -qm ignora
EX=$(TMPDIR="$TMPC" TEMP="$TMPC" TMP="$TMPC" node "$CM" --raiz "$R" --arquivo ign.js --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node -e "process.exit(0)"' > "$CASO/i1.out" 2> "$CASO/i1.err" < /dev/null; echo $?)
confere "I1 exit 4" "$EX" "4"
contem "I1 stderr diz que e ignorado" "$CASO/i1.err" "ignorado"

echo "== G1: git status que falha dentro do repo recusa =="
novo_caso 1
printf 'lixo' > "$CASO/repo/.git/index"
EX=$(roda "$CASO/g1" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "G1 exit 4" "$EX" "4"
contem "G1 stderr diz que o git status falhou" "$CASO/g1.err" "git status falhou"
confere "G1 src.js intocado" "$(sha "$CASO/repo/src.js")" "$SHA0"

echo "== G2: repo com .git/HEAD corrompido nao vira 'fora de repo' =="
novo_caso 1
printf 'module.exports = (a) => a + 1; // sujo\n' > "$CASO/repo/src.js"
SUJO2=$(sha "$CASO/repo/src.js")
printf 'lixo\n' > "$CASO/repo/.git/HEAD"
EX=$(roda "$CASO/g2" --no-lugar --de 'a + 1' --para 'a + 2' --bateria 'node teste.js')
confere "G2 exit 4" "$EX" "4"
contem "G2 stderr diz que o git falhou" "$CASO/g2.err" "git rev-parse falhou"
confere "G2 src.js sujo intacto" "$(sha "$CASO/repo/src.js")" "$SUJO2"

echo "== V1: backup de PID vivo para o mesmo arquivo recusa =="
novo_caso 1
PIDF="$(mixto "$CASO")/pid"
node -e 'require("fs").writeFileSync(process.argv[1], String(process.pid)); setTimeout(() => {}, 60000)' "$PIDF" &
LIMPAR_PIDS+=("$!")
for _ in $(seq 1 50); do [ -s "$CASO/pid" ] && break; sleep 0.1; done
grava_backup "$(cat "$CASO/pid")" 'module.exports = (a) => a + 1;
'
EX=$(roda "$CASO/v1" --no-lugar --de 'a + 1' --para 'a + 2' --bateria "$BAT_SONDA")
confere "V1 exit 4" "$EX" "4"
contem "V1 stderr nomeia a outra execucao viva" "$CASO/v1.err" "outra execução no lugar"
confere "V1 src.js intocado" "$(sha "$CASO/repo/src.js")" "$SHA0"
confere "V1 backup da outra execucao permanece" "$(backups)" "1"
confere "V1 a bateria nao rodou" "$(cat "$CASO/marca" 2>/dev/null || echo ausente)" "ausente"

echo
echo "-----------------------------------------"
echo "ok: $OK   falhou: $FALHOU"
[ "$FALHOU" -eq 0 ] && echo "== resultado: $OK ok, 0 falha(s) ==" || echo "== resultado: $OK ok, $FALHOU falha(s) =="
[ "$FALHOU" -eq 0 ]
