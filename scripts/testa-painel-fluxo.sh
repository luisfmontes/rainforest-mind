#!/bin/bash
# Bateria do painel do fluxo (D6 e D7 do design 2026-10-13-executar-dag-painel).
# Uso: bash scripts/testa-painel-fluxo.sh
#
# Cada cenario roda numa caixa nova (mktemp -d, fora do worktree): repo git com
# `origin` bare, branch fluxo/x, plano de 3 tarefas (1 e 2 sem dependencia, 3
# dependendo das duas) e `executar` aberto. O `estado.cjs` e o `painel-fluxo.cjs`
# que rodam sao a copia real. Todo teste confere o HTML gerado (o arquivo que o
# leitor abre), nunca o texto do fonte.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT

# GIT_* herdado (de um hook, de outro repo) apontaria as caixas para o repo errado.
for v in $(env | grep -o '^GIT_[A-Z_]*'); do unset "$v"; done
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID

ok=0; falhou=0
SLUG=2026-10-13-painel-teste

igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
tem() { # nome, trecho fixo, arquivo
  if grep -qF -- "$2" "$3"; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: trecho '$2' ausente em $3"; fi
}
nao_tem() { # nome, trecho fixo, arquivo
  if grep -qF -- "$2" "$3"; then falhou=$((falhou+1)); echo "  FALHA $1: trecho '$2' presente em $3"
  else ok=$((ok+1)); echo "  ok   $1"; fi
}
existe() { # nome, arquivo
  if [ -f "$2" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: $2 nao existe"; fi
}

# Cria uma caixa nova com o fluxo aberto em `executar`. Deixa em CX o caminho POSIX,
# em W o caminho Windows (o node le W), e em P o painel esperado em RFM_ROOT.
caixa_nova() {
  CX="$(mktemp -d)"; SANDBOXES+=("$CX")
  ORIG="$(mktemp -d)"; SANDBOXES+=("$ORIG")
  W="$(cygpath -m "$CX" 2>/dev/null || printf '%s' "$CX")"
  # Os dados (RFM_ROOT) ficam fora do repo da caixa: o que o revisor conta como mutacao
  # é o que muda dentro do repo.
  DADOS="$(mktemp -d)"; SANDBOXES+=("$DADOS")
  DW="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
  export HOME="$CX/casa" USERPROFILE="$CX/casa" CLAUDE_CONFIG_DIR="$CX/casa/.claude-personal"
  mkdir -p "$HOME" "$CX/scripts/lib" "$CX/hooks/lib" "$CX/docs/rainforest/planos" "$CX/docs/rainforest/estado"
  cp "$SRC/scripts/estado.cjs" "$SRC/scripts/conferir-fluxo.cjs" "$SRC/scripts/painel-fluxo.cjs" "$CX/scripts/"
  cp "$SRC/scripts/lib/camadas.cjs" "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SRC/scripts/lib/extrair-veredito.cjs" "$CX/scripts/lib/"
  for lib in raiz config trava-jsonl pastas-docs resolver-executavel contar-ocorrencias caminho-leve teto-despachos; do
    cp "$SRC/hooks/lib/$lib.cjs" "$CX/hooks/lib/"
  done
  touch "$CX/FOCO.md"
  mkdir -p "$CX/.rainforest" && printf '{"principal-livre": true}
' > "$CX/.rainforest/config.json"   # a caixa e um clone dedicado em fluxo/x
  export RFM_ESTADO_ROOT="$W"
  export RFM_ROOT="$DW"

  git init -q --bare "$ORIG/origin.git"
  git -C "$CX" init -q -b main
  git -C "$CX" config user.email "teste@exemplo.invalid"
  git -C "$CX" config user.name "teste"
  git -C "$CX" remote add origin "$ORIG/origin.git"
  printf '# teste\n' > "$CX/LEIA.md"
  git -C "$CX" add -- LEIA.md
  git -C "$CX" commit -q -m "base"
  git -C "$CX" push -q origin main
  git -C "$CX" checkout -q -b fluxo/x

  # A tarefa 1 tem `<script>` no titulo de propósito: o painel tem de sair escapado.
  cat > "$CX/docs/rainforest/planos/$SLUG.md" <<'EOF'
# Plano: teste do painel

## Tarefas

### 1. Primeira <script>alert(1)</script> [tipo: implementar]
arquivos: `a.txt`
depende de: nenhuma
prova: `true`

### 2. Segunda [tipo: implementar]
arquivos: `b.txt`
depende de: nenhuma
prova: `true`

### 3. Terceira [tipo: implementar]
arquivos: `c.txt`
depende de: 1, 2
prova: `true`
EOF

  cd "$CX" || exit 1
  node scripts/estado.cjs iniciar --slug "$SLUG" >/dev/null 2>"$CX/err.txt" || { echo "FALHA preparo: iniciar"; cat "$CX/err.txt"; exit 1; }
  node scripts/estado.cjs marcar --slug "$SLUG" --estagio design --status aprovado >/dev/null 2>&1 || { echo "FALHA preparo: design"; exit 1; }
  node scripts/estado.cjs marcar --slug "$SLUG" --estagio plano --status ok >/dev/null 2>&1 || { echo "FALHA preparo: plano"; exit 1; }
  node scripts/estado.cjs exigir --slug "$SLUG" --estagio executar >/dev/null 2>&1 || { echo "FALHA preparo: executar"; exit 1; }
  P="$DADOS/fluxos/$SLUG/painel.html"
}

# Commit real de uma tarefa, com o trailer do slug indicado (sem trailer se vazio).
commit_tarefa() { # arquivo, mensagem, slug#n ou ""
  printf 'x%s\n' "$RANDOM" >> "$CX/$1"
  git -C "$CX" add -- "$1"
  if [ -n "$3" ]; then
    git -C "$CX" commit -q -m "$2" --trailer "Rainforest-Tarefa: $3"
  else
    git -C "$CX" commit -q -m "$2"
  fi
}

E="node scripts/estado.cjs"

echo "== marcar executar gera o painel: um cartao por tarefa, tres estados como texto =="
caixa_nova
commit_tarefa "a.txt" "tarefa 1" "$SLUG#1"
esperado "marcar executar parcial com integradas [1] e em_voo [2] sai 0" 0 \
  $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[1],"em_voo":[{"tarefa":"2 segunda","agente":"a2"}]}'
existe "painel.html foi criado em <RFM_ROOT>/fluxos/<slug>/" "$P"
igual "um cartao por tarefa do plano" "3" "$(grep -c 'class="cartao"' "$P")"
tem "estado integrada aparece como texto" '>integrada</span>' "$P"
tem "estado em voo aparece como texto" '>em voo</span>' "$P"
tem "estado pendente aparece como texto" '>pendente</span>' "$P"
tem "camada 1 no cartao" 'camada 1</span>' "$P"
tem "camada 2 no cartao" 'camada 2</span>' "$P"
tem "agente da tarefa em voo" '<span class="agente">agente a2</span>' "$P"
tem "resumo: quem esta em voo" 'tarefa 2 Segunda (agente a2)' "$P"
tem "resumo: o que falta, com numeros" '<dd>2 (2, 3)</dd>' "$P"
tem "resumo: estagio atual" '<dd>executar</dd>' "$P"
tem "resumo: data do ultimo marcar" "<dd>$(date +%Y-%m-%d)</dd>" "$P"
tem "resumo: fluxo em andamento" '<dd>em andamento</dd>' "$P"
tem "resumo: veredito de revisar ainda nao" '<dd>ainda não</dd>' "$P"
# Iteracao do laco (D6): dois carimbos da tarefa 1 = iteracao 2 no cartao dela.
BASE1="$(git -C "$CX" rev-parse HEAD~1)"
for _ in 1 2; do
  $E marcar --slug "$SLUG" --estagio executar --status parcial --json "{\"carimbos\":[{\"tarefa\":1,\"hash_base\":\"$BASE1\"}]}" >/dev/null 2>&1 \
    || { echo "FALHA preparo: carimbo"; falhou=$((falhou+1)); }
done
tem "cartao da tarefa 1 traz a iteracao do laco" 'camada 1 · iteração 2</span>' "$P"

echo "== titulo com <script> sai escapado =="
caixa_nova
esperado "marcar executar parcial sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[]}'
tem "titulo com <script> sai como &lt;script&gt;" '&lt;script&gt;alert(1)&lt;/script&gt;' "$P"
nao_tem "nenhum <script> cru no HTML" '<script' "$P"
nao_tem "o HTML nao referencia URL externa (http)" 'http' "$P"

echo "== revisar regenera o painel e o veredito aparece =="
caixa_nova
# Escolha desta bateria: `revisar ok` exigiria um revisor real (transcrito de subagente).
# Esta caixa desliga so o contrato de veredito, para o painel ser o alvo. A trava tem
# bateria propria (testa-estado.sh); o painel nao depende dela para desenhar o veredito.
printf '{"principal-livre": true, "contrato-veredito": false}\n' > "$CX/.rainforest/config.json"
commit_tarefa "a.txt" "tarefa 1" "$SLUG#1"
commit_tarefa "b.txt" "tarefa 2" "$SLUG#2"
commit_tarefa "c.txt" "tarefa 3" "$SLUG#3"
esperado "marcar executar parcial com as 3 integradas sai 0" 0 \
  $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[1,2,3]}'
esperado "marcar executar ok sai 0" 0 \
  $E marcar --slug "$SLUG" --estagio executar --status ok --json '{"comando":"bash t.sh","saida":"ok","tarefas_ok":3,"tarefas":3,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste-1"},{"tarefa":2,"resultado":"vermelho","fixture":"teste-2"},{"tarefa":3,"resultado":"vermelho","fixture":"teste-3"}]}'
esperado "exigir revisar arma a janela e o instantaneo sai 0" 0 $E exigir --slug "$SLUG" --estagio revisar
# O `executar ok` acima também regenera o painel, então a mtime é zerada logo antes do
# `marcar revisar`: só o revisar pode trazê-la de volta para o presente.
touch -d 2000-01-01 "$P"
touch -d 2001-01-01 "$ORIG/ref"
esperado "marcar revisar ok sai 0" 0 \
  $E marcar --slug "$SLUG" --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'
if [ "$P" -nt "$ORIG/ref" ]; then ok=$((ok+1)); echo "  ok   revisar regenerou o painel (mtime maior)"
else falhou=$((falhou+1)); echo "  FALHA revisar nao regenerou o painel"; fi
tem "veredito de revisar aparece" '<dt>Veredito de revisar</dt><dd>ok</dd>' "$P"
tem "estagio atual avancou para verificar" '<dd>verificar</dd>' "$P"

echo "== fluxo parado aparece como texto =="
caixa_nova
esperado "marcar executar reprovado sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status reprovado
tem "resumo diz que o fluxo parou e onde" '<span class="parado">parado em executar: reprovado</span>' "$P"

echo "== RFM_ROOT apontando para arquivo: marcar sai 0 e avisa =="
caixa_nova
touch "$CX/no-lugar"
export RFM_ROOT="$W/no-lugar"
$E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[1]}' >/dev/null 2>"$CX/err.txt"
rc=$?
igual "marcar com RFM_ROOT em arquivo sai 0" "0" "$rc"
tem "stderr traz aviso: painel" 'aviso: painel' "$CX/err.txt"
export RFM_ROOT="$DW"

echo "== gerar sozinho imprime o caminho do painel =="
caixa_nova
node scripts/painel-fluxo.cjs gerar --slug "$SLUG" >"$CX/gerar.txt" 2>"$CX/gerar-err.txt"
rc=$?
igual "gerar sai 0" "0" "$rc"
saida_gerar="$(cat "$CX/gerar.txt")"
esperado "o caminho impresso existe" 0 node -e 'require("fs").statSync(process.argv[1])' "$saida_gerar"
esperado "gerar sem slug sai 1" 1 node scripts/painel-fluxo.cjs gerar

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
