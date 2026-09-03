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
TEMPS=("$SBP")
trap 'rm -rf "${TEMPS[@]}"' EXIT

ok=0; falhou=0
checa() { # nome, esperado(nivel), esperado(trecho), obtido
  if echo "$4" | grep -q "^$2" && echo "$4" | grep -qF "$3"; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1"; echo "       esperava $2 com '$3'"; echo "       veio: $4"
  fi
}

# Espelha `manifestoDoPlugin` do saude.cjs: quem nomeia a pasta do clone e o
# MANIFESTO, e o basename e so o ultimo recurso. A bateria PRECISA nomear igual ao
# produto — se ela montar o clone num lugar onde o `saude.cjs` nao vai olhar, as
# situacoes B/C/D caem sem que haja defeito nenhum no codigo. Ver o cenario K.
nome_do_manifesto() {
  node -e '
    const fs = require("fs"), path = require("path"), raiz = process.argv[1];
    let nome = path.basename(raiz);
    try {
      const m = JSON.parse(fs.readFileSync(path.join(raiz, ".claude-plugin", "plugin.json"), "utf8"));
      if (m && typeof m.name === "string" && m.name.trim()) nome = m.name.trim();
    } catch { /* sem manifesto legivel: fica o basename, igual ao produto */ }
    console.log(nome);
  ' "$1"
}

M="$SBP/cfg/plugins/marketplaces/$(nome_do_manifesto "$SRC")"
mkdir -p "$SBP/cfg/plugins/marketplaces" "$SBP/dados"
# Os casos gerais nao sao da poda: desligar a chave (padrao true) para o
# checarPoda nao injetar aviso em cenario alheio. Os casos da poda criam
# a propria raiz com a chave ligada.
printf '{"poda": false}' > "$SBP/dados/config.json"

ver() { # opcional: caminho da fonte a rodar (default: $SRC, o repo real)
  local fonte="${1:-$SRC}"
  ( cd "$fonte" && CLAUDE_CONFIG_DIR="$SBP/cfg" RFM_ROOT="$SBP/dados" \
    node "$fonte/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        const a=JSON.parse(d).find(x=>x.item==='plugin instalado');
        console.log(a ? a.nivel+' '+a.detalhe : 'ausente');
      })"
}
ver_acao() { # igual ao ver(), mas devolve a ACAO — o ver() so traz nivel+detalhe
  local fonte="${1:-$SRC}"
  ( cd "$fonte" && CLAUDE_CONFIG_DIR="$SBP/cfg" RFM_ROOT="$SBP/dados" \
    node "$fonte/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        const a=JSON.parse(d).find(x=>x.item==='plugin instalado');
        console.log(a && a.acao ? a.acao : 'sem acao');
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
  # O nome sai do proprio basename em vez de literal: assim a igualdade e estrutural
  # — renomear $FONTE nao pode deixar $MF apontando para uma pasta que o produto
  # nunca vai procurar, que e o defeito que o cenario K guarda.
  printf '{"name":"%s","version":"1.0.0"}' "$(basename "$FONTE")" > "$FONTE/.claude-plugin/plugin.json"
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
echo "== gitCommitSha AUSENTE do registro nao pode virar ok silencioso (Issue: sha ausente) =="
# O campo pode faltar de tres jeitos, e so dois tinham tratamento antes deste
# bloco: desconhecido (F, acima: aviso "nao conhece") e ausencia estrutural do
# proprio registro (config dir/instalacao inexistente, tratada como "nao ha
# achado" em avaliarConfigDir). O terceiro — o campo `gitCommitSha` simplesmente
# nao existe no item — caia no `if (i.gitCommitSha)` como falso e nao deixava
# rastro nenhum: virava `ok` calado, um ok que nao conferiu nada.
criar_fonte_sintetica
rm -rf "$MF"; git clone -q "$FONTE" "$MF" 2>/dev/null   # clone em dia, irrelevante aqui
cat > "$SBP/cfg/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"fonte-sintetica@teste":[{"scope":"user",
 "installPath":"$SBP/cfg/plugins/cache/teste/fonte-sintetica/1.0.0",
 "version":"1.0.0"}]}}
JSON
F2="$(ver "$FONTE")"
checa "F2. gitCommitSha ausente vira aviso de indeterminacao" "aviso" "nao da para saber se o que EXECUTA esta em dia" "$F2"
checa "F2. e diz QUAL campo falta"                            "aviso" "sem 'gitCommitSha' no registro" "$F2"

# Caminho feliz: sha presente e IGUAL ao HEAD nao pode ganhar ruido por causa do
# conserto acima — regressao aqui e o risco real desta mudanca.
HEAD_FONTE="$(git -C "$FONTE" rev-parse HEAD)"
cat > "$SBP/cfg/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"fonte-sintetica@teste":[{"scope":"user",
 "installPath":"$SBP/cfg/plugins/cache/teste/fonte-sintetica/1.0.0",
 "version":"1.0.0","gitCommitSha":"$HEAD_FONTE"}]}}
JSON
checa "F2. sha igual ao HEAD continua ok, sem ruido" "ok" "skills do repo" "$(ver "$FONTE")"
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
#
# Ate 2026-08-20 esta secao mutava "$SRC/scripts/saude.cjs" NO LUGAR e confiava
# no `cp` de volta, algumas linhas depois, para restaurar. Mas o unico
# `trap ... EXIT` do arquivo (la em cima) apaga $SBP — e era em $SBP que a copia
# do original ficava guardada. Um Ctrl-C, um timeout de ferramenta ou um crash
# na janela entre a mutacao e a restauracao deixava o saude.cjs do REPO DE
# VERDADE com o discriminador de parentesco cego, em silencio: nada quebra
# visivelmente, o /saude so para de detectar clone sem parentesco. Troca pelo
# padrao que os dois blocos abaixo (mutacao J e mutacao do CLAUDE_CONFIG_DIR)
# ja usavam: mutar uma COPIA, nunca o fonte do repo. Isso dispensa restauracao
# e torna a interrupcao inofensiva — nao ha mais janela nenhuma para vazar.
#
# A copia precisa ser repo git COM manifesto, senao a checagem nem chega no
# ramo de parentesco: saude.cjs parte de RAIZ_CODIGO (dirname do dirname do
# script rodado), usa manifestoDoPlugin(RAIZ_CODIGO) para achar o nome, procura
# o clone em marketplaces/<nome> dentro da config dir, confere
# `git rev-parse --is-inside-work-tree` e so entao calcula raizDe(RAIZ_CODIGO).
# Por isso a copia leva scripts/, skills/ e .claude-plugin/plugin.json, e vira
# commit proprio com `git init` — a raiz dela fica propria e diferente da de
# $M (o clone sem parentesco montado la em cima, linhas 236-237), que e
# exatamente o que a situacao B precisa para ser detectada.
MUTR="$(mktemp -d)"
TEMPS+=("$MUTR")
cp -r "$SRC/scripts" "$MUTR/scripts"
cp -r "$SRC/skills" "$MUTR/skills"
mkdir -p "$MUTR/.claude-plugin"
cp "$SRC/.claude-plugin/plugin.json" "$MUTR/.claude-plugin/plugin.json"
git init -q "$MUTR"
git -C "$MUTR" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$MUTR" -c user.email=t@t -c user.name=t commit -qm "copia para a mutacao de raiz" >/dev/null 2>&1
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8'), a='raizAqui !== raizLa';
  if(!s.includes(a)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  fs.writeFileSync(p, s.replace(a, 'false'));
" "$MUTR/scripts/saude.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  S="$(ver "$MUTR")"
  if echo "$S" | grep -q "sem parentesco"; then
    falhou=$((falhou+1)); echo "  FALHA com a mutacao, B continuou detectado — o teste nao prova nada"
  else
    ok=$((ok+1)); echo "  ok   cegado o discriminador, B deixa de ser detectado (era ele mesmo)"
  fi
fi
rm -rf "$MUTR"
checa "controle: fonte intacta (nunca mutada) continua acusando B" "alerta" "sem parentesco" "$(ver)"

echo
echo "== esquema de banco: detecta falta de UNIQUE (Tarefa 23 - item 6) =="
# Teste I: banco com esquema legado (sem UNIQUE constraint em observacoes)
DADOS_LEGADO=".rainforest-saude-legado"
rm -rf "$DADOS_LEGADO" && mkdir -p "$DADOS_LEGADO"
printf '{"poda": false}' > "$DADOS_LEGADO/config.json"
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
TEMPS+=("$MUT")
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
echo "== banco de memoria: observacoes, indice vivo e pipeline (Tarefa 5) =="
# Teste Q: banco ok com observacoes e fts sincronizados
DADOS_OK=".rainforest-saude-ok"
rm -rf "$DADOS_OK" && mkdir -p "$DADOS_OK"
printf '{"poda": false}' > "$DADOS_OK/config.json"
( cd "$DADOS_OK" && node << 'MKBANCO_OK'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('./rainforest.db');

db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT,
    UNIQUE(projeto, origem)
  );

  CREATE VIRTUAL TABLE observacoes_fts USING fts5(
    conteudo,
    content='observacoes',
    content_rowid='id'
  );

  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER NOT NULL DEFAULT 0,
    offset_processado INTEGER NOT NULL DEFAULT 0,
    processada_em TEXT NOT NULL,
    UNIQUE(projeto, sessao)
  );

  INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
  VALUES ('test', 'obs1', datetime('now'), 'orig1');

  INSERT INTO observacoes_fts(rowid, conteudo)
  VALUES (1, 'obs1');

  INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em)
  VALUES ('test', 'sess1', '/tmp/t.jsonl', 100, 100, datetime('now'));
`);

db.close();
MKBANCO_OK
)

DADOS_OK_ABS="$(cd "$DADOS_OK" && pwd)"
Q="$(RFM_ROOT="$DADOS_OK_ABS" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "banco de memoria"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
checa "Q. banco ok com fts sincronizado vira ok"         "ok" "schema valido" "$Q"

# Teste Q2: banco ausente vira ok com nota
Q2="$(RFM_ROOT="$DADOS_OK_ABS/../inexistente" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "banco de memoria"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
checa "Q2. banco ausente vira ok"                         "ok" "ausente" "$Q2"

# Teste Q3: counts divergentes fabricados
# Usar FTS sem content= para ter controle total sobre sincronizacao
DADOS_DIVERGE=".rainforest-saude-diverge"
rm -rf "$DADOS_DIVERGE" && mkdir -p "$DADOS_DIVERGE"
printf '{"poda": false}' > "$DADOS_DIVERGE/config.json"
( cd "$DADOS_DIVERGE" && node << 'MKBANCO_DIVERGE'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('./rainforest.db');

db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT,
    UNIQUE(projeto, origem)
  );

  -- FTS independente (sem content=) para poder dessincaronizar
  CREATE VIRTUAL TABLE observacoes_fts USING fts5(
    conteudo
  );

  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER NOT NULL DEFAULT 0,
    offset_processado INTEGER NOT NULL DEFAULT 0,
    processada_em TEXT NOT NULL,
    UNIQUE(projeto, sessao)
  );

  -- Inserir 2 observacoes
  INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
  VALUES ('test', 'obs1', datetime('now'), 'orig1');
  INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
  VALUES ('test', 'obs2', datetime('now'), 'orig2');

  -- Inserir SO 1 no FTS (divergencia: 2 vs 1)
  INSERT INTO observacoes_fts(conteudo)
  VALUES ('obs1');
`);

db.close();
MKBANCO_DIVERGE
)

DADOS_DIVERGE_ABS="$(cd "$DADOS_DIVERGE" && pwd)"
Q3="$(RFM_ROOT="$DADOS_DIVERGE_ABS" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "banco de memoria"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
checa "Q3. counts divergentes viram aviso"               "aviso" "indice vivo" "$Q3"
checa "Q3. e sugerem reindexar"                          "aviso" "reindexar" "$Q3"

# Teste Q4: pendencia de 72h (mais que 48h)
DADOS_PENDENTE_72H=".rainforest-saude-pendente-72h"
rm -rf "$DADOS_PENDENTE_72H" && mkdir -p "$DADOS_PENDENTE_72H"
printf '{"poda": false}' > "$DADOS_PENDENTE_72H/config.json"
( cd "$DADOS_PENDENTE_72H" && node << 'MKBANCO_PENDENTE_72H'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('./rainforest.db');

// Data de 72 horas atras
const data72hAtras = new Date(Date.now() - 72 * 60 * 60 * 1000).toISOString();

db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT,
    UNIQUE(projeto, origem)
  );

  CREATE VIRTUAL TABLE observacoes_fts USING fts5(
    conteudo,
    content='observacoes',
    content_rowid='id'
  );

  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER NOT NULL DEFAULT 0,
    offset_processado INTEGER NOT NULL DEFAULT 0,
    processada_em TEXT NOT NULL,
    UNIQUE(projeto, sessao)
  );

  -- offset > offset_processado (100 > 50 = ha pendencia)
  -- processada_em = 72h atras
  INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em)
  VALUES ('test', 'sess1', '/tmp/t.jsonl', 100, 50, '${data72hAtras}');
`);

db.close();
MKBANCO_PENDENTE_72H
)

DADOS_PENDENTE_72H_ABS="$(cd "$DADOS_PENDENTE_72H" && pwd)"
Q4="$(RFM_ROOT="$DADOS_PENDENTE_72H_ABS" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "banco de memoria"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
checa "Q4. pendencia de 72h vira aviso"                  "aviso" "pipeline parado" "$Q4"
checa "Q4. e sugere observar"                            "aviso" "observar" "$Q4"

# Teste Q5: pendencia de 1h (menos que 48h) - NAO acusa
DADOS_PENDENTE_1H=".rainforest-saude-pendente-1h"
rm -rf "$DADOS_PENDENTE_1H" && mkdir -p "$DADOS_PENDENTE_1H"
printf '{"poda": false}' > "$DADOS_PENDENTE_1H/config.json"
( cd "$DADOS_PENDENTE_1H" && node << 'MKBANCO_PENDENTE_1H'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('./rainforest.db');

// Data de 1 hora atras
const data1hAtras = new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString();

db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT,
    UNIQUE(projeto, origem)
  );

  CREATE VIRTUAL TABLE observacoes_fts USING fts5(
    conteudo,
    content='observacoes',
    content_rowid='id'
  );

  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER NOT NULL DEFAULT 0,
    offset_processado INTEGER NOT NULL DEFAULT 0,
    processada_em TEXT NOT NULL,
    UNIQUE(projeto, sessao)
  );

  -- offset > offset_processado (100 > 50 = ha pendencia)
  -- processada_em = 1h atras (MENOS que 48h, NAO deve acusar)
  INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em)
  VALUES ('test', 'sess1', '/tmp/t.jsonl', 100, 50, '${data1hAtras}');
`);

db.close();
MKBANCO_PENDENTE_1H
)

DADOS_PENDENTE_1H_ABS="$(cd "$DADOS_PENDENTE_1H" && pwd)"
Q5="$(RFM_ROOT="$DADOS_PENDENTE_1H_ABS" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "banco de memoria"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
if echo "$Q5" | grep -qF "pipeline parado"; then
  falhou=$((falhou+1)); echo "  FALHA Q5. pendencia recente (1h) nao deve acusar pipeline parado"
else
  ok=$((ok+1)); echo "  ok   Q5. pendencia recente nao acusa pipeline parado"
fi

# Teste Q6 (C2 da revisao): erro imprevisto nao vira ok
# Banco com marca_dagua SEM offset_processado (schema pre-migracao): a checagem 3
# lanca "no such column", o erro nao casa com nenhuma substring conhecida, e a
# versao anterior caia no ok final — o alarme mentia exatamente no caso imprevisto.
DADOS_IMPREVISTO=".rainforest-saude-imprevisto"
rm -rf "$DADOS_IMPREVISTO" && mkdir -p "$DADOS_IMPREVISTO"
printf '{"poda": false}' > "$DADOS_IMPREVISTO/config.json"
( cd "$DADOS_IMPREVISTO" && node << 'MKBANCO_IMPREVISTO'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('./rainforest.db');
db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT,
    UNIQUE(projeto, origem)
  );
  CREATE VIRTUAL TABLE observacoes_fts USING fts5(
    conteudo,
    content='observacoes',
    content_rowid='id'
  );
  -- marca_dagua SEM offset_processado: estado real pre-migracao
  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER NOT NULL DEFAULT 0,
    processada_em TEXT NOT NULL,
    UNIQUE(projeto, sessao)
  );
  INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em)
  VALUES ('test', 'sess1', '/tmp/t.jsonl', 100, '2026-08-20T10:00:00Z');
`);
db.close();
MKBANCO_IMPREVISTO
)
DADOS_IMPREVISTO_ABS="$(cd "$DADOS_IMPREVISTO" && pwd)"
Q6="$(RFM_ROOT="$DADOS_IMPREVISTO_ABS" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e 'let d=""; process.stdin.on("data", c => d += c).on("end", () => { try { const a = JSON.parse(d).find(x => x.item === "banco de memoria"); console.log(a ? a.nivel + " " + a.detalhe : "ausente"); } catch(e) { console.log("erro"); } })')"
# "Nao ser ok" nao basta: um aviso de indice por acaso tambem passaria. O que o
# C2 promete e ALERTA vindo do ramo novo ("erro imprevisto"), carregando a
# mensagem original — e o fixture mantem o resto do banco SAUDAVEL (FTS com
# content= e contagens iguais) para nenhum outro padrao poder produzir o achado.
checa "Q6. erro nao classificado vira ALERTA (nao ok, nao silencio)" "alerta" "erro imprevisto" "$Q6"
checa "Q6. e o alerta carrega a mensagem original do erro"           "alerta" "erro ao verificar marca dagua" "$Q6"

# Limpeza
rm -rf "$DADOS_OK" "$DADOS_DIVERGE" "$DADOS_PENDENTE_72H" "$DADOS_PENDENTE_1H" "$DADOS_IMPREVISTO"

echo
echo "== contas do harness em versoes diferentes do mesmo plugin =="
# 2026-08-20: depois de quatro PRs e de um `claude plugin update`, a config
# pessoal estava em 0.71.0 e a de trabalho em 0.70.0 — e o painel dizia `ok`,
# porque a checagem 6 obedece (corretamente) a declaracao do CLAUDE_CONFIG_DIR e
# para na config ativa. A pergunta de inventario nao tem quem a faca.
#
# A HOME e falsa aqui, como na secao G: sem isso a bateria leria as config dirs
# reais de quem roda, e o resultado passaria a depender da maquina do dono.
# Repare que o CLAUDE_CONFIG_DIR e apontado para OUTRO lugar de proposito — e
# exatamente isso que o cenario prova: a varredura de inventario ignora a
# declaracao, enquanto o resto do painel continua obedecendo a ela.
HOMEDIVERGE="$SBP/home-diverge"
monta_conta() { # $1 = nome da config dir, $2 = versao, $3 = sha
  mkdir -p "$HOMEDIVERGE/$1/plugins"
  cat > "$HOMEDIVERGE/$1/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"rainforest-mind@rainforest-mind":[{"scope":"user",
 "installPath":"$HOMEDIVERGE/$1/plugins/cache/rainforest-mind/$2",
 "version":"$2","gitCommitSha":"$3"}]}}
JSON
}
contas() { # roda o saude.cjs indicado ($1) contra a home falsa e devolve o item
  ( cd "$SRC" && CLAUDE_CONFIG_DIR="$SBP/cfg" USERPROFILE="$HOMEDIVERGE" HOME="$HOMEDIVERGE" \
    RFM_ROOT="$SBP/dados" node "$1" --json 2>/dev/null ) | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        const a=JSON.parse(d).find(x=>x.item==='config dirs');
        console.log(a ? a.nivel+' '+a.detalhe : 'ausente');
      })"
}

rm -rf "$HOMEDIVERGE"
monta_conta ".claude"       "0.70.0" "df1b135aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
monta_conta ".claude-outra" "0.71.0" "1369ca5bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
M1="$(contas "$SRC/scripts/saude.cjs")"
checa "M. duas contas em versoes diferentes viram aviso" "aviso" "versoes diferentes" "$M1"
checa "M. e nomeia as duas, com versao e sha"            "aviso" "[.claude] 0.70.0 (df1b135), [.claude-outra] 0.71.0 (1369ca5)" "$M1"

# Silencio quando batem: uma linha dizendo "estao iguais" e inventario 364 dias
# por ano, e o evento e a divergencia. Sem esta metade, bastaria imprimir sempre.
monta_conta ".claude-outra" "0.70.0" "df1b135aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
M2="$(contas "$SRC/scripts/saude.cjs")"
checa "M. contas iguais nao viram achado nenhum" "ausente" "ausente" "$M2"

# Uma conta so nao diverge de ninguem.
rm -rf "$HOMEDIVERGE/.claude-outra"
checa "M. com uma conta so, nada a dizer" "ausente" "ausente" "$(contas "$SRC/scripts/saude.cjs")"

echo
echo "== MUTACAO: fazer o inventario obedecer o CLAUDE_CONFIG_DIR =="
# A decisao de desenho inteira desta checagem e ignorar a declaracao de sessao,
# porque declaracao de sessao nao responde pergunta de inventario. Se alguem
# "consertar" a incoerencia aparente igualando as duas varreduras, a divergencia
# volta a passar em silencio. A mutacao roda numa COPIA — nunca no fonte do repo.
rm -rf "$HOMEDIVERGE"
monta_conta ".claude"       "0.70.0" "df1b135aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
monta_conta ".claude-outra" "0.71.0" "1369ca5bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
MUTCD="$(mktemp -d)"
TEMPS+=("$MUTCD")
cp -r "$SRC/scripts" "$MUTCD/scripts"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8'), a='const dirs = todasAsConfigDirsDaHome();';
  if(!s.includes(a)) { console.error('MUTACAO NAO APLICADA: alvo ausente'); process.exit(1); }
  fs.writeFileSync(p, s.replace(a, 'const dirs = configDirsDoHarness();'));
" "$MUTCD/scripts/saude.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  MM="$(contas "$MUTCD/scripts/saude.cjs")"
  if echo "$MM" | grep -qF "versoes diferentes"; then
    falhou=$((falhou+1)); echo "  FALHA obedecendo a declaracao, ainda acusou — o cenario M nao prova nada"
  else
    ok=$((ok+1)); echo "  ok   obedecendo a declaracao, a divergencia passa em silencio (ignorar a variavel era a trava)"
  fi
fi
rm -rf "$MUTCD" "$HOMEDIVERGE"

echo
echo "== o fluxo diz de QUEM e a branch, nao so que ha trabalho aberto (Issue #25) =="
# 2026-08-20: esta checagem imprimiu `1 trabalho(s) em aberto -> revisar` 20 minutos
# antes de a sessao commitar naquela mesma branch — que era de outra sessao. Ela tinha
# as duas metades do fato (o slug e `<data>-<branch>`) e publicou so uma, enquadrada
# como estado do fluxo. A correcao custou `rebase --onto` + `push --force-with-lease`
# porque a outra sessao ja tinha commitado por cima.
FLUXO="$SBP/repo-com-fluxo"
rm -rf "$FLUXO"; mkdir -p "$FLUXO/docs/rainforest/estado"
git init -q -b branch-de-outro "$FLUXO"
( cd "$FLUXO" && git config user.email t@t && git config user.name t \
  && echo x > x.txt && git add . && git commit -qm inicial ) >/dev/null 2>&1
printf '{"slug":"2026-01-02-branch-de-outro","titulo":"trabalho de outra sessao","design":{"status":"aprovado"}}' \
  > "$FLUXO/docs/rainforest/estado/2026-01-02-branch-de-outro.json"

fluxo_em() { # $1 = branch onde por o HEAD antes de medir
  ( cd "$FLUXO" \
    && { git checkout -q "$1" 2>/dev/null || git checkout -q -b "$1"; } \
    && CLAUDE_CONFIG_DIR="$SBP/cfg" RFM_ROOT="$SBP/dados" RFM_ESTADO_ROOT="$FLUXO" \
       node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        const a=JSON.parse(d).find(x=>x.item==='fluxo');
        console.log(a ? a.nivel+' '+a.detalhe : 'ausente');
      })"
}

L1="$(fluxo_em branch-de-outro)"
checa "L. na branch do trabalho, avisa que ela tem dono" "aviso" "ESTA branch tem dono" "$L1"
checa "L. e nomeia o trabalho e o estagio"               "aviso" "2026-01-02-branch-de-outro  -> plano" "$L1"

# O outro lado, que e o que impede o aviso de virar ruido permanente: fora da branch
# do trabalho, ele NAO aparece. Sem esta metade, bastaria imprimir o texto sempre.
L2="$(fluxo_em uma-branch-minha)"
if echo "$L2" | grep -qF "ESTA branch tem dono"; then
  falhou=$((falhou+1)); echo "  FALHA L. noutra branch, o aviso de dono apareceu assim mesmo"
else
  ok=$((ok+1)); echo "  ok   L. noutra branch, o aviso de dono nao aparece"
fi
checa "L. e o trabalho aberto continua sendo reportado"  "aviso" "1 trabalho(s) em aberto" "$L2"

echo
echo "== a BATERIA tambem nao pode depender do nome da propria pasta =="
# O cenario H cobra do PRODUTO a disciplina de tirar o nome do manifesto. Ninguem a
# cobrava do arnes, e em 2026-08-20 ele estava justamente sem ela: a mesma bateria,
# no mesmo commit, dava `18 ok` no checkout (pasta `rainforest-mind`) e
# `13 ok, 5 falha(s)` em qualquer copia com outro nome. O 2x2 que isolou a causa:
#
#   checkout principal | .git diretorio | pasta rainforest-mind | 18 ok
#   clone comum        | .git diretorio | pasta nome-qualquer   | 13 ok, 5 falhas
#   worktree linkado   | .git arquivo   | pasta wt-27           | 13 ok, 5 falhas
#   worktree linkado   | .git arquivo   | pasta rainforest-mind | 18 ok
#
# Ser worktree nao tinha nada a ver (era a suspeita do Issue #27, e estava errada):
# `basename "$SRC"` nomeava o clone do marketplace, o `saude.cjs` o procurava pelo
# nome do MANIFESTO, e nas pastas com outro nome ele nao achava nada e respondia
# "rodando direto do repo" — o ramo de sucesso. As 5 falhas pareciam defeito de
# codigo. Vermelho que nao e defeito e pior que vermelho nenhum: ensina a ignorar
# a bateria, e o fluxo deste plugin roda em pasta de outro nome por desenho.
#
# Custo: esta secao roda a bateria inteira mais uma vez (~20s). E o preco de provar
# o veredito na bancada de verdade em vez de deduzi-lo do fonte.
if [ -z "${RFM_TESTA_SAUDE_ANINHADA:-}" ]; then
  COPIA="$SBP/copia-com-outro-nome"
  rm -rf "$COPIA"; mkdir -p "$COPIA"
  # Sem o `.git`: copiar o diretorio e desperdicio, e copiar o `.git` ARQUIVO de um
  # worktree produziria uma copia apontando para o gitdir do original. A copia vira
  # repo proprio, de um commit so — e o que A-D precisam. E o conteudo vem da ARVORE
  # DE TRABALHO, nao de `git clone`, senao a bateria aninhada rodaria o codigo
  # COMMITADO e ficaria verde para uma edicao ainda por commitar.
  ( cd "$SRC" && tar -cf - --exclude=./.git . ) | ( cd "$COPIA" && tar -xf - )
  git init -q "$COPIA"
  git -C "$COPIA" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$COPIA" -c user.email=t@t -c user.name=t commit -qm "copia para a bateria aninhada" >/dev/null 2>&1
  K="$( cd "$COPIA" && RFM_TESTA_SAUDE_ANINHADA=1 bash "$COPIA/scripts/testa-saude.sh" 2>&1 | tail -1 )"
  case "$K" in
    *"0 falha(s)"*)
      ok=$((ok+1)); echo "  ok   K. de pasta com outro nome a bateria da o mesmo veredito" ;;
    *)
      falhou=$((falhou+1))
      echo "  FALHA K. de pasta com outro nome a bateria muda de veredito"
      echo "        veio: $K" ;;
  esac
  rm -rf "$COPIA"
else
  echo "  (K. pulado: esta e a execucao aninhada)"
fi

echo
echo
echo
echo "== acao de plugin update traz a chave qualificada do registro =="
# O comando `claude plugin update` recebe a chave `<plugin>@<marketplace>`, e ela
# sai do installed_plugins.json lido — nunca de literal no codigo, senao a linha
# mente na maquina de quem instalou o plugin de outra origem.
criar_fonte_sintetica
SHA_VELHO="$(git -C "$FONTE" rev-parse HEAD)"
for i in 1 2; do
  git -C "$FONTE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "depois do install $i" >/dev/null 2>&1
done
rm -rf "$MF"; git clone -q "$FONTE" "$MF" 2>/dev/null
cat > "$SBP/cfg/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"fonte-sintetica@marketplace-teste":[{"scope":"user",
 "installPath":"$SBP/cfg/plugins/cache/marketplace-teste/fonte-sintetica/0.9.0",
 "version":"0.9.0","gitCommitSha":"$SHA_VELHO"}]}}
JSON
ACAO_N="$(ver_acao "$FONTE")"
if [ -z "$ACAO_N" ] || [ "$ACAO_N" = "sem acao" ]; then
  falhou=$((falhou+1)); echo "  FALHA N. saida vazia — o cenario nao produziu acao nenhuma"
elif echo "$ACAO_N" | grep -qF "plugin update fonte-sintetica@marketplace-teste"; then
  ok=$((ok+1)); echo "  ok   N. acao de plugin update traz <plugin>@<marketplace> do registro"
else
  falhou=$((falhou+1)); echo "  FALHA N. acao sem a chave qualificada"; echo "       veio: $ACAO_N"
fi
rm -f "$SBP/cfg/plugins/installed_plugins.json"

echo
echo "== duas origens do mesmo plugin: nenhuma escolhida em silencio =="
# O mesmo plugin pode ter entrada de mais de um marketplace — o comentario de
# `instalacoesRegistradas` diz isso. Mandar atualizar so a primeira do registro e
# escolher no escuro: as duas que estao atras precisam aparecer na acao.
cat > "$SBP/cfg/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{
 "fonte-sintetica@marketplace-teste":[{"scope":"user",
  "installPath":"$SBP/cfg/plugins/cache/marketplace-teste/fonte-sintetica/0.9.0",
  "version":"0.9.0","gitCommitSha":"$SHA_VELHO"}],
 "fonte-sintetica@outro-marketplace":[{"scope":"user",
  "installPath":"$SBP/cfg/plugins/cache/outro-marketplace/fonte-sintetica/0.9.0",
  "version":"0.9.0","gitCommitSha":"$SHA_VELHO"}]}}
JSON
ACAO_O="$(ver_acao "$FONTE")"
if [ -z "$ACAO_O" ] || [ "$ACAO_O" = "sem acao" ]; then
  falhou=$((falhou+1)); echo "  FALHA O. saida vazia — o cenario nao produziu acao nenhuma"
elif echo "$ACAO_O" | grep -qF "marketplace-teste" && echo "$ACAO_O" | grep -qF "outro-marketplace"; then
  ok=$((ok+1)); echo "  ok   O. as duas origens aparecem, nenhuma escolhida em silencio"
else
  falhou=$((falhou+1)); echo "  FALHA O. so uma origem apareceu"; echo "       veio: $ACAO_O"
fi
rm -f "$SBP/cfg/plugins/installed_plugins.json"

echo
echo "== marketplace update recebe o MARKETPLACE, nao a chave inteira =="
# `claude plugin marketplace update` e outro comando: o argumento dele e o nome do
# marketplace, nao a chave `<plugin>@<marketplace>`. Cenario: clone atrasado (que e
# quem produz essa acao) com a instalacao EM DIA, para isolar a acao do clone.
criar_fonte_sintetica
rm -rf "$MF"; git clone -q "$FONTE" "$MF" 2>/dev/null   # clone em dia...
for i in 1 2 3; do
  git -C "$FONTE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "fonte andou $i" >/dev/null 2>&1
done                                                     # ...e agora atrasado
SHA_NOVO="$(git -C "$FONTE" rev-parse HEAD)"
cat > "$SBP/cfg/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"fonte-sintetica@outro-marketplace":[{"scope":"user",
 "installPath":"$SBP/cfg/plugins/cache/outro-marketplace/fonte-sintetica/1.0.0",
 "version":"1.0.0","gitCommitSha":"$SHA_NOVO"}]}}
JSON
ACAO_P="$(ver_acao "$FONTE")"
if [ -z "$ACAO_P" ] || [ "$ACAO_P" = "sem acao" ]; then
  falhou=$((falhou+1)); echo "  FALHA P. saida vazia — o cenario nao produziu acao nenhuma"
elif ! echo "$ACAO_P" | grep -qF "marketplace update"; then
  falhou=$((falhou+1)); echo "  FALHA P. o cenario nao produziu a acao de marketplace update"; echo "       veio: $ACAO_P"
elif echo "$ACAO_P" | grep -qF "marketplace update outro-marketplace" \
  && ! echo "$ACAO_P" | grep -qF "marketplace update fonte-sintetica@"; then
  ok=$((ok+1)); echo "  ok   P. marketplace update recebe so o marketplace"
else
  falhou=$((falhou+1)); echo "  FALHA P. usou a chave inteira no lugar do marketplace"; echo "       veio: $ACAO_P"
fi
rm -f "$SBP/cfg/plugins/installed_plugins.json"

echo ""
echo "== conselho: rodada-concluida-sem-aviso =="
SB_CONS_COMPLETA="$(mktemp -d)"
trap "rm -rf '$SB_CONS_COMPLETA'" RETURN
mkdir -p "$SB_CONS_COMPLETA/.rainforest/conselho/20260831-completa"
cat > "$SB_CONS_COMPLETA/.rainforest/conselho/20260831-completa/estado.json" <<'EOF'
{"id": "20260831-completa", "fases": {"pareceres": {"status": "ok"}, "revisao": {"status": "ok"}, "sintese": {"status": "ok"}}}
EOF
SAUDE_OUT_COMPLETA="$(cd "$SB_CONS_COMPLETA" && node "$SRC/scripts/saude.cjs" 2>&1 || true)"
if ! echo "$SAUDE_OUT_COMPLETA" | grep -q "conselho"; then
  ok=$((ok+1)); echo "  ok   rodada concluida (3 fases ok) nao gera secao do conselho"
else
  falhou=$((falhou+1)); echo "  FALHA rodada concluida ainda aparece no saude: $(echo "$SAUDE_OUT_COMPLETA" | grep conselho | head -1)"
fi

echo ""
echo "== conselho: seção ausente sem rodadas =="
SB_CONS1="$(mktemp -d)"
trap "rm -rf '$SB_CONS1'" RETURN
# Rodar /saude em diretório vazio - não deve ter seção conselho
SAUDE_OUT1="$(cd "$SB_CONS1" && node "$SRC/scripts/saude.cjs" 2>&1 || true)"
if ! echo "$SAUDE_OUT1" | grep -q "conselho"; then
  ok=$((ok+1)); echo "  ok   seção conselho ausente sem rodadas"
else
  falhou=$((falhou+1)); echo "  FALHA seção conselho apareceu sem rodadas"
fi

echo ""
echo "== conselho: aviso com rodada ABANDONA =="
SB_CONS2="$(mktemp -d)"
trap "rm -rf '$SB_CONS2'" RETURN
mkdir -p "$SB_CONS2/.rainforest/conselho/20260831-teste"
cat > "$SB_CONS2/.rainforest/conselho/20260831-teste/estado.json" <<'EOF'
{"id": "20260831-teste", "resultado": "ABANDONA", "fases": {"pareceres": {"status": "reprovada"}}}
EOF
# Rodar /saude - deve ter seção conselho com aviso sobre ABANDONA
SAUDE_OUT2="$(cd "$SB_CONS2" && node "$SRC/scripts/saude.cjs" 2>&1 || true)"
if echo "$SAUDE_OUT2" | grep -q "aviso.*conselho" && echo "$SAUDE_OUT2" | grep -q "ABANDONA"; then
  ok=$((ok+1)); echo "  ok   aviso quando rodada ABANDONA"
else
  falhou=$((falhou+1)); echo "  FALHA deveria ter aviso com ABANDONA"; echo "$SAUDE_OUT2" | grep "conselho" || echo "(nenhuma linha com conselho)"
fi

echo
echo "== integrações desligadas não geram item nenhum =="
# Sem ligação: node scripts/saude.cjs --json não deve ter item com 'integracao' no nome
R1="$( RFM_ROOT="$SBP/dados" \
  node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e '
    let d=""; process.stdin.on("data", c => d += c).on("end", () => {
      try {
        const items = JSON.parse(d).filter(x => x.item && x.item.startsWith("integracao")).length;
        console.log(items);
      } catch(e) { console.log("erro"); }
    })' )"
checa "R1. sem integracao ligada, zero items integracao*" "0" "0" "$R1"

echo
echo "== integracao-sabia ligada com pasta sem .venv vira aviso =="
# Setup: pasta sabia com sabia.py, mas SEM .venv
SABIA_DIR="$SBP/fixtures-sabia"
mkdir -p "$SABIA_DIR"
echo "def doutor(): pass" > "$SABIA_DIR/sabia.py"
# NÃO criar .venv

# Setup dados: integracao-sabia LIGADA + projeto registrado
# IMPORTANTE: config.json fica em RFM_ROOT, não em CLAUDE_CONFIG_DIR
mkdir -p "$SBP/dados-integracao"
cat > "$SBP/dados-integracao/config.json" <<EOF
{"integracao-sabia":true}
EOF
cat > "$SBP/dados-integracao/projetos.json" <<EOF
{"sabia":{"caminho":"$SABIA_DIR"}}
EOF

R2="$( RFM_ROOT="$SBP/dados-integracao" \
  node "$SRC/scripts/saude.cjs" 2>/dev/null )"

# Verify that integracao-sabia appears as aviso
if echo "$R2" | grep -q "aviso.*integracao-sabia"; then
  ok=$((ok+1)); echo "  ok   R2. integracao-sabia sem .venv vira aviso"
else
  falhou=$((falhou+1)); echo "  FALHA R2. integracao-sabia deveria virar aviso"
fi

# O aviso nao pode MUDAR o exit (D4). Exit absoluto seria fragil: o painel checa
# muito alem das integracoes (banco, plugin), e em ambiente copiado/aninhado outra
# checagem pode alertar por conta propria — foi exatamente assim que a secao K pegou
# a primeira versao deste caso. Mede-se o DELTA: mesmo RFM_ROOT, integracao
# desligada vs ligada-e-quebrada, e o exit tem de ser o MESMO.
cat > "$SBP/dados-integracao/config.json" <<EOF
{"integracao-sabia":false}
EOF
RFM_ROOT="$SBP/dados-integracao" \
  node "$SRC/scripts/saude.cjs" >/dev/null 2>&1
R2_EXIT_BASE=$?
cat > "$SBP/dados-integracao/config.json" <<EOF
{"integracao-sabia":true}
EOF
RFM_ROOT="$SBP/dados-integracao" \
  node "$SRC/scripts/saude.cjs" >/dev/null 2>&1
R2_EXIT=$?
if [ "$R2_EXIT" = "$R2_EXIT_BASE" ]; then
  ok=$((ok+1)); echo "  ok   R2b. integracao quebrada nao muda o exit (base $R2_EXIT_BASE, com aviso $R2_EXIT)"
else
  falhou=$((falhou+1)); echo "  FALHA R2b. exit mudou: sem integracao $R2_EXIT_BASE, com aviso $R2_EXIT"
fi

# Cleanup
rm -rf "$SBP/dados-integracao" "$SBP/fixtures-sabia"

echo
echo "== backup-externo (Tarefa 10) =="
# (a) zip de hoje no destino → ok
BACKUP_HOJE="$SBP/backup-hoje"
mkdir -p "$BACKUP_HOJE"
touch "$BACKUP_HOJE/rainforest-$(date +%Y-%m-%d).zip"
R_BACKUP_A="$( RFM_BACKUP_DESTINO="$BACKUP_HOJE" \
  node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e '
    let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
      try {
        const a=JSON.parse(d).find(x=>x.item==="backup-externo");
        console.log(a ? a.nivel+"|"+a.detalhe : "ausente");
      } catch { console.log("erro"); }
    })' )"
if echo "$R_BACKUP_A" | grep -q "^ok|"; then
  ok=$((ok+1)); echo "  ok   (a) zip de hoje no destino → ok"
else
  falhou=$((falhou+1)); echo "  FALHA (a) esperava ok, veio: $R_BACKUP_A"
fi

# (b) zip com mais de 2 dias → alerta nomeando a idade
BACKUP_VELHO="$SBP/backup-velho"
mkdir -p "$BACKUP_VELHO"
CINCO_DIAS_ATRAS="$(date -d '5 days ago' +%Y-%m-%d 2>/dev/null || date -v-5d +%Y-%m-%d 2>/dev/null)"
NOME_ZIP_VELHO="rainforest-${CINCO_DIAS_ATRAS}.zip"
touch "$BACKUP_VELHO/$NOME_ZIP_VELHO"
touch -d "5 days ago" "$BACKUP_VELHO/$NOME_ZIP_VELHO" 2>/dev/null || true
R_BACKUP_B="$( RFM_BACKUP_DESTINO="$BACKUP_VELHO" \
  node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e '
    let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
      try {
        const a=JSON.parse(d).find(x=>x.item==="backup-externo");
        console.log(a ? a.nivel+"|"+a.detalhe : "ausente");
      } catch { console.log("erro"); }
    })' )"
if echo "$R_BACKUP_B" | grep -q "^alerta|.*[4-9] dia[s]*"; then
  ok=$((ok+1)); echo "  ok   (b) zip com mais de 2 dias → alerta nomeando idade"
else
  falhou=$((falhou+1)); echo "  FALHA (b) esperava alerta com idade, veio: $R_BACKUP_B"
fi

# (c) destino inexistente → alerta
BACKUP_INEXISTENTE="$SBP/backup-nao-existe-mesmo"
R_BACKUP_C="$( RFM_BACKUP_DESTINO="$BACKUP_INEXISTENTE" \
  node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e '
    let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
      try {
        const a=JSON.parse(d).find(x=>x.item==="backup-externo");
        console.log(a ? a.nivel+"|"+a.detalhe : "ausente");
      } catch { console.log("erro"); }
    })' )"
if echo "$R_BACKUP_C" | grep -q "^alerta|" && echo "$R_BACKUP_C" | grep -qF "não existe"; then
  ok=$((ok+1)); echo "  ok   (c) destino inexistente → alerta"
else
  falhou=$((falhou+1)); echo "  FALHA (c) esperava alerta, veio: $R_BACKUP_C"
fi

# Cleanup
rm -rf "$BACKUP_HOJE" "$BACKUP_VELHO"

echo
echo "== MUTACAO: trocar aviso por alerta em checarIntegracoes =="
# Se as chamadas a aviso() forem trocadas por alerta(), os testes de integração
# devem falhar (exit != 0). A mutação roda numa cópia.
MUTINT="$(mktemp -d)"
TEMPS+=("$MUTINT")
cp -r "$SRC/scripts" "$MUTINT/scripts"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8');
  const target = 'aviso(\`integracao-';
  if(!s.includes(target)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  fs.writeFileSync(p, s.replace(/aviso\(\`integracao-/g, 'alerta(\`integracao-'));
" "$MUTINT/scripts/saude.cjs"
if [ $? -ne 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"
else
  # Setup para teste com integração ligada: com alerta, deve sair com exit 1
  SABIA_DIR_MUT="$MUTINT/fixtures-sabia"
  mkdir -p "$SABIA_DIR_MUT"
  echo "def doutor(): pass" > "$SABIA_DIR_MUT/sabia.py"

  # Config vai em RFM_ROOT, não em cfg
  mkdir -p "$MUTINT/dados"
  cat > "$MUTINT/dados/config.json" <<'JSON3'
{"integracao-sabia":true}
JSON3

  cat > "$MUTINT/dados/projetos.json" <<JSON4
{"sabia":{"caminho":"$SABIA_DIR_MUT"}}
JSON4

  RFM_ROOT="$MUTINT/dados" \
    node "$MUTINT/scripts/saude.cjs" >/dev/null 2>&1
  S_EXIT=$?

  if [ "$S_EXIT" = "1" ]; then
    ok=$((ok+1)); echo "  ok   S. com alerta no lugar de aviso, exit=1 (alerta bloqueia)"
  else
    falhou=$((falhou+1)); echo "  FALHA S. mutacao nao fez exit=1"; echo "       veio exit: $S_EXIT"
  fi
fi
rm -rf "$MUTINT"
echo "== poda: proxy de medição de custo =="

# R1: com poda desligada, não aparece no JSON
R1_TEST="$SBP/test-poda-off"
mkdir -p "$R1_TEST/.rainforest"
printf '{"poda":false}' > "$R1_TEST/.rainforest/config.json"
R1="$( ( cd "$R1_TEST" && node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
  let d=''; process.stdin.on('data', c => d += c).on('end', () => {
    try {
      const a = JSON.parse(d).find(x => x.item === 'poda');
      console.log(a ? 'ENCONTRADO' : 'ausente');
    } catch { console.log('erro'); }
  });
" )"
if [ "$R1" = "ausente" ]; then
  ok=$((ok+1)); echo "  ok   R1. com poda desligado, nao aparece item"
else
  falhou=$((falhou+1)); echo "  FALHA R1. esperava ausente, veio: $R1"
fi

# R2: com poda ligada e sem pidfile, aparece aviso
R2_TEST="$SBP/test-poda-on"
# Issue #160/#153: sem RFM_ROOT este caso lia a config de quem roda a bateria —
# verde na maquina do dono (config com poda), "ausente" no runner (sem config).
mkdir -p "$R2_TEST/.rainforest"
R2="$( ( cd "$R2_TEST" && RFM_ROOT="$R2_TEST/.rainforest" node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
  let d=''; process.stdin.on('data', c => d += c).on('end', () => {
    try {
      const a = JSON.parse(d).find(x => x.item === 'poda');
      console.log(a ? a.nivel : 'ausente');
    } catch { console.log('erro'); }
  });
" )"
if [ "$R2" = "aviso" ]; then
  ok=$((ok+1)); echo "  ok   R2. sem poda.pid, aparece aviso"
else
  falhou=$((falhou+1)); echo "  FALHA R2. esperava aviso, veio: $R2"
fi

# R3: com pidfile mas porta morta, aparece aviso (não alerta)
R3_TEST="$SBP/test-poda-dead-port"
mkdir -p "$R3_TEST/.rainforest/poda"
printf '{"pid":99999,"porta":19999}' > "$R3_TEST/.rainforest/poda/poda.pid"
R3="$( ( cd "$R3_TEST" && RFM_ROOT="$R3_TEST/.rainforest" node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
  let d=''; process.stdin.on('data', c => d += c).on('end', () => {
    try {
      const a = JSON.parse(d).find(x => x.item === 'poda');
      console.log(a ? a.nivel : 'ausente');
    } catch { console.log('erro'); }
  });
" )"
if [ "$R3" = "aviso" ]; then
  ok=$((ok+1)); echo "  ok   R3. porta morta vira aviso (nao alerta)"
else
  falhou=$((falhou+1)); echo "  FALHA R3. esperava aviso, veio: $R3"
fi

# R4: o item poda é aviso, nunca alerta — o exit global não pode virar 1 POR CAUSA
# DA PODA (medir o exit inteiro aqui seria frágil: na bateria aninhada do caso K a
# cópia é um repo recém-init e outras seções produzem alerta legítimo).
R4_NIVEIS="$( cd "$R3_TEST" && RFM_ROOT="$R3_TEST/.rainforest" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e '
  let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
    try {
      const a=JSON.parse(d).filter(x=>x.item==="poda");
      console.log(a.map(x=>x.nivel).join(",")||"ausente");
    } catch { console.log("erro"); }
  })' )"
if [ "$R4_NIVEIS" = "aviso" ]; then
  ok=$((ok+1)); echo "  ok   R4. item poda e exatamente um aviso (nunca alerta)"
else
  falhou=$((falhou+1)); echo "  FALHA R4. niveis do item poda: $R4_NIVEIS (esperava 'aviso')"
fi

# R5: caminho de SUCESSO com pidfile no formato REAL e porta viva — este caso
# existe porque a rodada 2 da revisao pegou o /saude lendo `port` enquanto o
# poda.cjs grava `porta`: o sucesso nunca tinha rodado, e o fixture antigo
# casava o defeito do consumidor (tautologia).
R5_TEST="$SBP/test-poda-viva"
mkdir -p "$R5_TEST/.rainforest/poda"
R5_PORTA=$((20000 + RANDOM % 40000))
node -e "
const http=require('http');
const s=http.createServer((req,res)=>{res.writeHead(200);res.end('ok');});
s.listen($R5_PORTA,'127.0.0.1',()=>console.log('pronto'));
setTimeout(()=>process.exit(0), 20000);
" &
R5_SRV_PID=$!
sleep 1
printf '{"pid":%s,"porta":%s,"iniciadoEm":"2026-08-31T00:00:00Z"}' "$R5_SRV_PID" "$R5_PORTA" > "$R5_TEST/.rainforest/poda/poda.pid"
printf '{"atualizadoEm":"2026-08-31T00:00:00Z","estagio":null,"usage":{},"requisicoes":7}' > "$R5_TEST/.rainforest/poda/contexto.json"
R5="$( cd "$R5_TEST" && RFM_ROOT="$R5_TEST/.rainforest" ANTHROPIC_BASE_URL="http://127.0.0.1:$R5_PORTA" node "$SRC/scripts/saude.cjs" --json 2>/dev/null | node -e '
  let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
    try {
      const a=JSON.parse(d).find(x=>x.item==="poda");
      console.log(a ? a.nivel+"|"+a.detalhe : "ausente");
    } catch { console.log("erro"); }
  })' )"
kill "$R5_SRV_PID" 2>/dev/null || true
case "$R5" in
  "ok|"*"7 requisi"*)
    ok=$((ok+1)); echo "  ok   R5. caminho de sucesso: ok com contagem do contexto.json" ;;
  *)
    falhou=$((falhou+1)); echo "  FALHA R5. esperava ok com 7 requisicoes, veio: $R5" ;;
esac

# MUTAÇÃO: mudar aviso→alerta faz exit ir para 1
MUTCOPIA="$(mktemp -d)"
TEMPS+=("$MUTCOPIA")
cp -r "$SRC/scripts" "$MUTCOPIA/scripts"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8');
  if(s.includes('nao responde')) {
    const nu=s.replace('aviso(\'poda\', \`porta', 'alerta(\'poda\', \`porta');
    fs.writeFileSync(p, nu);
  }
" "$MUTCOPIA/scripts/saude.cjs"
( cd "$R3_TEST" && node "$MUTCOPIA/scripts/saude.cjs" --json 2>/dev/null >/dev/null )
MUT_EXIT=$?
if [ $MUT_EXIT -ne 0 ]; then
  ok=$((ok+1)); echo "  ok   MUTACAO: aviso→alerta faz exit=1"
else
  falhou=$((falhou+1)); echo "  FALHA MUTACAO: exit deveria ser 1"
fi
rm -rf "$MUTCOPIA"

# Limpeza
rm -rf "$R1_TEST" "$R2_TEST" "$R3_TEST"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
