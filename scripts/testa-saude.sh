#!/bin/bash
# Bateria do scripts/saude.cjs — por ora, so a checagem do PLUGIN INSTALADO.
#
# Ela existe porque essa checagem ja enganou duas vezes, e nas duas o defeito foi o
# mesmo em forma diferente: o medidor respondeu com confianca uma pergunta que nao
# conseguia fazer.
#
#   1a vez (2026-08-11, manha): comparava so o COMMIT do clone. Clone no commit certo
#      com conteudo faltando passava como ok — e foi assim que tres skills novas nao
#      valiam em sessao nenhuma sem ninguem notar. Consertado olhando o CONTEUDO
#      (nome de skill presente la e aqui), que e o que o usuario ve na paleta;
#   2a vez (mesmo dia, noite): depois de o historico ser reescrito para publicar, o
#      commit do clone deixou de existir aqui. `rev-list --count` falhou e a saida
#      virou "? commit(s) atras" — muda justamente no caso em que a resposta era mais
#      util, e apontando para um `marketplace update` que NAO reconcilia historias
#      sem parentesco.
#
# As quatro situacoes que a checagem tem que separar:
#   A. clone atras         -> aviso, com a contagem
#   B. sem parentesco      -> ALERTA, e o conserto NAO e o update
#   C. commit so no clone  -> aviso, e nao "atraso": ha trabalho que o update atropela
#   D. clone em dia        -> ok
#
# O discriminador e o COMMIT RAIZ, e a primeira tentativa errou: perguntava se o
# commit do clone existia aqui, e concluia "sem parentesco" quando nao existia. Mas
# clone que fez commit proprio TAMBEM tem objeto que este repo nao conhece — e ali o
# parentesco existe. Ausencia de objeto nao e ausencia de parentesco. A raiz responde
# sem os dois lados precisarem compartilhar objeto nenhum.
#
# A ultima secao e MUTACAO: iguala as raizes e exige que B pare de ser detectado.
#
# D5 (2026-08-15): a situacao A rodava contra um CLONE DO REPO REAL, recuado com
# `git reset --hard HEAD~3`. `HEAD~3` anda por PRIMEIRO-PAI; o `saude.cjs` conta
# atraso com `rev-list --count`, que percorre o DAG INTEIRO. Os dois so combinam
# em historico sem merge — e este repo tem merge. Medido nos dez ancestrais do
# HEAD da branch de trabalho: 0, 1, 2, 4, 4, 5, 7, 8, 8, 9 commits de distancia
# por DAG. O "3" foi pulado; nao existe commit 3 atras, e a situacao A falhava
# por ausencia, nao por defeito do `saude.cjs`. A partir daqui, a situacao A
# monta uma fonte SINTETICA com historico linear proprio (ver `criar_fonte_
# sintetica`) e clona, depois avanca, essa fonte — o atraso de 3 fica garantido
# por CONSTRUCAO, nao pela sorte do historico da semana.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
checa() { # nome, esperado(nivel), esperado(trecho), obtido
  if echo "$4" | grep -q "^$2" && echo "$4" | grep -qF "$3"; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1"; echo "       esperava $2 com '$3'"; echo "       veio: $4"
  fi
}

M="$SBP/cfg/plugins/marketplaces/$(basename "$SRC")"
mkdir -p "$SBP/cfg/plugins/marketplaces" "$SBP/dados"

ver() { # opcional: caminho da fonte a rodar (default: $SRC, o repo real)
  local fonte="${1:-$SRC}"
  ( cd "$fonte" && CLAUDE_CONFIG_DIR="$SBP/cfg" RFM_ROOT="$SBP/dados" \
    node "$fonte/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        const a=JSON.parse(d).find(x=>x.item==='plugin instalado');
        console.log(a ? a.nivel+' '+a.detalhe : 'ausente');
      })"
}
git_clone() { rm -rf "$M"; git clone -q "$SRC" "$M" 2>/dev/null; }
commit_no_clone() { git -C "$M" -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }

echo "== as quatro situacoes =="

# Situacao A: fonte sintetica com historico LINEAR, montada por esta bateria —
# ver a nota D5 la em cima. `saude.cjs` so precisa achar, a partir da propria
# pasta (RAIZ_CODIGO = dirname(__dirname) do script rodado), `scripts/` (para o
# require nao quebrar o proprio node ao carregar o arquivo) e `skills/` (para o
# discriminador de conteudo ter algo pra listar). O resto das checagens do
# saude.cjs (raiz de dados, injecao, ideias, ...) so precisa nao ESTOURAR
# quando o que consultam nao existe — e ja nao estoura, cada uma cai no seu
# proprio "ausente"/"alerta" com try/catch ou fs.existsSync antes de agir.
FONTE="$SBP/fonte-sintetica"
MF="$SBP/cfg/plugins/marketplaces/$(basename "$FONTE")"

criar_fonte_sintetica() {
  rm -rf "$FONTE"
  mkdir -p "$FONTE/scripts" "$FONTE/skills/exemplo" "$FONTE/.claude-plugin"
  cp "$SRC/scripts/saude.cjs" "$FONTE/scripts/saude.cjs"
  echo "# skill de exemplo, so para skills/ nao ficar vazio" > "$FONTE/skills/exemplo/SKILL.md"
  # Manifesto com o nome IGUAL ao basename da pasta: as situacoes A-D ja assumiam
  # o basename, e o nome agora sai daqui (ver `manifestoDoPlugin`). Igualar os dois
  # mantem A-D medindo o que sempre mediram e libera E-G para usar o manifesto.
  printf '{"name":"fonte-sintetica","version":"1.0.0"}' > "$FONTE/.claude-plugin/plugin.json"
  git init -q "$FONTE"
  git -C "$FONTE" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$FONTE" -c user.email=t@t -c user.name=t commit -qm "inicial" >/dev/null 2>&1
}

criar_fonte_sintetica
rm -rf "$MF"; git clone -q "$FONTE" "$MF" 2>/dev/null
for i in 1 2 3; do
  git -C "$FONTE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "commit sintetico $i" >/dev/null 2>&1
done
checa "A. clone atras vira aviso com a contagem"   "aviso" "3 commit(s) atras"   "$(ver "$FONTE")"

# Historia paralela COM todas as skills no lugar: o parentesco tem que ser checado
# antes do conteudo, senao um clone completo porem orfao passa como saudavel.
rm -rf "$M"; mkdir -p "$M"; git init -q "$M"; cp -r "$SRC/skills" "$M/"
commit_no_clone add -A; commit_no_clone commit -qm "historia paralela"
S="$(ver)"
checa "B. sem parentesco vira ALERTA"              "alerta" "sem parentesco"     "$S"
checa "B. e diz que o update NAO resolve"          "alerta" "sem parentesco"     "$S"

git_clone && echo x > "$M/extra.txt" && commit_no_clone add extra.txt && commit_no_clone commit -qm "editado no clone"
checa "C. commit so no clone nao vira 'atraso'"    "aviso" "commit proprio"      "$(ver)"

git_clone
checa "D. clone em dia vira ok"                    "ok"    "skills do repo"      "$(ver)"

echo
echo "== o falso verde de 2026-08-17 =="
# A checagem respondia "rodando direto do repo (nenhuma copia instalada nesta
# config)" — a linha MAIS saudavel do painel — justamente quando rodava da copia
# instalada, com 6 commits de codigo novo parados. Dois defeitos somados:
# o nome do plugin vinha de `basename(RAIZ_CODIGO)`, que no cache versionado e a
# VERSAO ("0.65.0"), e o ramo "clone nao existe" caia em `ok`.
#
# Aqui a pasta tem manifesto (nome de verdade) e NAO e repo git — a forma exata do
# cache. A resposta certa e dizer que a pergunta nao pode ser feita dali.
NOGIT="$SBP/cache-falso/0.65.0"
mkdir -p "$NOGIT/scripts" "$NOGIT/.claude-plugin" "$NOGIT/skills/exemplo"
cp "$SRC/scripts/saude.cjs" "$NOGIT/scripts/saude.cjs"
printf '{"name":"rainforest-mind","version":"0.65.0"}' > "$NOGIT/.claude-plugin/plugin.json"
echo "# exemplo" > "$NOGIT/skills/exemplo/SKILL.md"
E="$(ver "$NOGIT")"
checa "E. de pasta que nao e repo git, vira aviso"  "aviso" "nao e repo git"      "$E"
if echo "$E" | grep -qF "rodando direto do repo"; then
  falhou=$((falhou+1)); echo "  FALHA voltou o falso verde 'rodando direto do repo'"
else
  ok=$((ok+1)); echo "  ok   nao diz mais 'rodando direto do repo'"
fi

echo
echo "== o que EXECUTA e o cache, e ele atrasa sozinho =="
# Clone e install sao artefatos independentes: em 2026-08-17 o clone do marketplace
# foi atualizado as 13:41 e o install continuou onde estava. Com o clone EM DIA, a
# checagem antiga nao tinha nada a dizer — e o codigo que rodava seguia velho.
criar_fonte_sintetica
SHA_VELHO="$(git -C "$FONTE" rev-parse HEAD)"
for i in 1 2; do
  git -C "$FONTE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "depois do install $i" >/dev/null 2>&1
done
rm -rf "$MF"; git clone -q "$FONTE" "$MF" 2>/dev/null   # clone EM DIA com a fonte
cat > "$SBP/cfg/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"fonte-sintetica@teste":[{"scope":"user",
 "installPath":"$SBP/cfg/plugins/cache/teste/fonte-sintetica/0.9.0",
 "version":"0.9.0","gitCommitSha":"$SHA_VELHO"}]}}
JSON
F="$(ver "$FONTE")"
checa "F. install atras e acusado com o clone em dia" "aviso" "o que EXECUTA esta atras" "$F"
checa "F. e nomeia a versao instalada"                "aviso" "0.9.0 instalada contra 1.0.0" "$F"
rm -f "$SBP/cfg/plugins/installed_plugins.json"

echo
echo "== as duas config dirs, nao so uma =="
# `CLAUDE_CONFIG_DIR || ~/.claude` olhava UMA. Esta maquina tem duas com o plugin
# habilitado, e elas divergem em silencio — foi o que ja custou as regras da
# CLAUDE.md uma vez. Sem a variavel declarada, a varredura tem que achar as duas e
# NOMEAR qual esta atras.
#
# `CLAUDE_CONFIG_DIR` vazio de proposito: com ele posto, a varredura para nele (e
# e isso que mantem A-F hermeticas). Aqui a home e o sandbox, nunca a do dono.
HOMEFALSA="$SBP/home"
mkdir -p "$HOMEFALSA/.claude/plugins/marketplaces" "$HOMEFALSA/.claude-teste/plugins/marketplaces"
criar_fonte_sintetica
rm -rf "$HOMEFALSA/.claude-teste/plugins/marketplaces/fonte-sintetica"
git clone -q "$FONTE" "$HOMEFALSA/.claude-teste/plugins/marketplaces/fonte-sintetica" 2>/dev/null
for i in 1 2 3 4; do
  git -C "$FONTE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "so na fonte $i" >/dev/null 2>&1
done
rm -rf "$HOMEFALSA/.claude/plugins/marketplaces/fonte-sintetica"
git clone -q "$FONTE" "$HOMEFALSA/.claude/plugins/marketplaces/fonte-sintetica" 2>/dev/null
G="$( ( cd "$FONTE" && CLAUDE_CONFIG_DIR= USERPROFILE="$HOMEFALSA" HOME="$HOMEFALSA" RFM_ROOT="$SBP/dados" \
  node "$FONTE/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
    let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
      const a=JSON.parse(d).find(x=>x.item==='plugin instalado');
      console.log(a ? a.nivel+' '+a.detalhe : 'ausente');
    })")"
checa "G. acha a segunda config dir e a nomeia"      "aviso" "[.claude-teste]"     "$G"
checa "G. e conta o atraso so dela"                  "aviso" "4 commit(s) atras"   "$G"
if echo "$G" | grep -qF "[.claude]"; then
  falhou=$((falhou+1)); echo "  FALHA a config dir em dia entrou no aviso"
else
  ok=$((ok+1)); echo "  ok   a config dir em dia nao vira achado"
fi

echo
echo "== o nome do plugin sai do manifesto, nao da pasta =="
# `basename(RAIZ_CODIGO)` so acerta enquanto a pasta se chama como o plugin. Ela nao
# se chama: no cache versionado o basename e a VERSAO, e num worktree deste proprio
# repo e o nome da branch. Nos dois casos o clone procurado nao existe e a checagem
# devolvia o ramo de sucesso. O nome esta declarado no manifesto — e de la que sai.
criar_fonte_sintetica
RENOMEADA="$SBP/pasta-com-outro-nome"
rm -rf "$RENOMEADA"; cp -r "$FONTE" "$RENOMEADA"
rm -rf "$MF"; git clone -q "$RENOMEADA" "$MF" 2>/dev/null   # clone em marketplaces/fonte-sintetica
for i in 1 2 3 4 5; do
  git -C "$RENOMEADA" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "so na fonte $i" >/dev/null 2>&1
done
H="$(ver "$RENOMEADA")"
checa "H. pasta com outro nome ainda acha o clone"   "aviso" "5 commit(s) atras"   "$H"

echo
echo "== a saida nunca imprime interrogacao =="
# O sintoma exato de 2026-08-11: `? commit(s) atras`. Se ele voltar, e porque alguem
# reintroduziu a contagem sem checar se ela e possivel.
rm -rf "$M"; mkdir -p "$M"; git init -q "$M"; cp -r "$SRC/skills" "$M/"
commit_no_clone add -A; commit_no_clone commit -qm p
if ver | grep -q "? commit"; then
  falhou=$((falhou+1)); echo "  FALHA a saida voltou a imprimir '? commit(s)'"
else
  ok=$((ok+1)); echo "  ok   nenhuma interrogacao na saida"
fi

echo
echo "== MUTACAO: cegar o discriminador de raiz =="
# Se as raizes forem sempre iguais, B deixa de ser detectado e volta a cair na
# contagem impossivel — que era exatamente o estado anterior ao conserto.
cp "$SRC/scripts/saude.cjs" "$SBP/original.cjs"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8'), a='raizAqui !== raizLa';
  if(!s.includes(a)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  fs.writeFileSync(p, s.replace(a, 'false'));
" "$SRC/scripts/saude.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  S="$(ver)"
  if echo "$S" | grep -q "sem parentesco"; then
    falhou=$((falhou+1)); echo "  FALHA com a mutacao, B continuou detectado — o teste nao prova nada"
  else
    ok=$((ok+1)); echo "  ok   cegado o discriminador, B deixa de ser detectado (era ele mesmo)"
  fi
fi
cp "$SBP/original.cjs" "$SRC/scripts/saude.cjs"
checa "e restaurado, B volta a ser ALERTA"         "alerta" "sem parentesco"     "$(ver)"

echo
echo "== esquema de banco: detecta falta de UNIQUE (Tarefa 23 - item 6) =="
# Teste I: banco com esquema legado (sem UNIQUE constraint em observacoes)
DADOS_LEGADO=".rainforest-saude-legado"
rm -rf "$DADOS_LEGADO" && mkdir -p "$DADOS_LEGADO"
( cd "$DADOS_LEGADO" && node << 'MKLEGACY'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('./rainforest.db');

db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER DEFAULT 0,
    offset_processado INTEGER DEFAULT 0
  );
  CREATE TABLE resumos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
  CREATE TABLE prompts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
`);

db.close();
MKLEGACY
)

DADOS_LEGADO_ABS="$(cd "$DADOS_LEGADO" && pwd)"
I="$(RFM_ROOT="$DADOS_LEGADO_ABS" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "esquema de banco"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
checa "I. banco legado acusa falta de UNIQUE"     "alerta" "UNIQUE" "$I"

# Mutação de verdade: o alerta do teste I tem que vir da checagem, e não de
# outro caminho do /saude que por acaso mencione UNIQUE. A versão anterior
# deste bloco greppava o nome da função no fonte — o que continua verde se a
# chamada existir e não fizer efeito, que é o defeito exato que a tarefa 22
# passou o dia extinguindo. Aqui a checagem é removida numa CÓPIA e o /saude
# roda contra o mesmo banco legado: se ainda acusar, o teste I não prova nada.
echo
echo "== MUTACAO: desabilitar a checagem de UNIQUE numa copia =="
MUT="$(mktemp -d)"
cp -r "$SRC/scripts" "$MUT/scripts"
sed -i 's/if (!verificarConstraintUniqueProjetoOrigem(db)) {/if (false) { \/* MUTACAO *\//' "$MUT/scripts/saude.cjs"

if grep -q "MUTACAO" "$MUT/scripts/saude.cjs"; then
  J="$(RFM_ROOT="$DADOS_LEGADO_ABS" node "$MUT/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "esquema de banco"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
  case "$J" in
    *UNIQUE*)
      falhou=$((falhou+1))
      echo "  FALHA J. copia sem a checagem AINDA acusa UNIQUE — o alerta do teste I vem de outro lugar"
      echo "        saida: $J" ;;
    *)
      ok=$((ok+1))
      echo "  ok   J. copia sem a checagem para de acusar (o alerta do I vem mesmo da checagem)" ;;
  esac
else
  falhou=$((falhou+1))
  echo "  FALHA J. a mutacao nao casou com o fonte — o alvo do sed mudou, e este teste virou decorativo"
fi
rm -rf "$MUT"

rm -rf "$DADOS_LEGADO"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
