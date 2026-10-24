#!/bin/bash
# Bateria do `conferir-busca.cjs` (D7) e da fiação dele no `estado.cjs` e no `conferir-fluxo.cjs`.
# Uso: bash scripts/testa-conferir-busca.sh
#
# O que esta bateria prova: a tarefa que cria codigo novo sem `busca:` e recusada
# pelo numero (e pelo caminho), a forma do bloco (canal `repo`, resultado ou
# `pulado:`, `desfecho:` valido) e' conferida, e o que nao cria codigo novo passa.
# O `estado.cjs marcar --estagio plano` recusa o plano sem o bloco e aceita com ele,
# e a `cobertura` aceita o campo novo em vez de recusa-lo como campo desconhecido.
#
# Fixture: repositorio git temporario montado AQUI, com um unico arquivo commitado
# (scripts/existente.cjs). Planos sao escritos por `tarefa`, um bloco por tarefa,
# e cada caso mutila um campo por vez. Quase todo caso e' negativo de proposito:
# checagem que so se viu passando nao foi verificada.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$RAIZ/scripts/conferir-busca.cjs"
CHECADOR_FLUXO="$RAIZ/scripts/conferir-fluxo.cjs"
ESTADO="$RAIZ/scripts/estado.cjs"

for f in "$CHECADOR" "$CHECADOR_FLUXO" "$ESTADO"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

# Idioma das outras baterias (testa-conferir-fluxo.sh): cada sandbox criada com
# `mktemp -d` entra em SANDBOXES e o trap de EXIT varre todas.
SANDBOXES=()
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

# Repo git temporario. O commit sai com identidade e sem config global do usuario
# (GIT_CONFIG_GLOBAL=/dev/null): e' repositorio de fixture, descartavel, e nao
# depende de assinatura nem de hook da maquina de quem roda.
S="$(mktemp -d)"; SANDBOXES+=("$S")
W="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")"
(
  cd "$S" || exit 1
  git init -q
  mkdir -p scripts docs/rainforest/design docs/rainforest/planos
  echo "// existente" > scripts/existente.cjs
  git add scripts/existente.cjs
  GIT_CONFIG_GLOBAL=/dev/null git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "base da fixture"
)
D="$S/docs/rainforest/design/t.md"
P="$S/docs/rainforest/planos/t.md"

# Design minimo: so o que `cobertura` le (a secao de decisoes, com D1).
escreve_design() {
  cat > "$D" <<'EOF'
# Design: fixture de busca

## Decisões fechadas

- **D1 — fixture** — porque: a bateria precisa de uma decisão para as tarefas atenderem.

## Avaliado e descartado

- nada

## Fora de escopo

- nada
EOF
}

PLANO_CAB='# Plano: fixture de busca

Design: docs/rainforest/design/t.md

## Tarefas
'

# tarefa <numero> <tipo> <arquivos com crases> <linhas do busca, ou vazio> <linha desfecho, ou vazio>
# Campos fixos (atende, mutacao, prova-na-base) existem para que a cobertura e o
# fechamento do plano so recusem pelo campo que o caso mutila.
tarefa() {
  printf '### %s. Tarefa %s [tipo: %s]\natende: D1\narquivos: %s\ndepende de: nenhuma\nmutacao: n/a\n  motivo: fixture de bateria\nprova-na-base: verde — fixture de bateria\n' "$1" "$1" "$2" "$3"
  if [ -n "$4" ]; then printf 'busca:\n%s\n' "$4"; fi
  if [ -n "$5" ]; then printf '%s\n' "$5"; fi
  printf 'pronto quando: com entrada X, efeito Y — provado por `bash scripts/testa-conferir-busca.sh`\n\n'
}

BUSCA_OK='- repo | grep -E "novo" scripts | nada reaproveitável
- livro | pulado: sem repositório de terceiro para este caso'
DESF_OK='desfecho: enxertar'

total=0
vermelhas=()

# caso <nome> <exit-esperado> <regex da saida, ou vazio> <comando...>
# Conta o caso e, se algo nao bater, guarda o nome para o resumo final.
caso() {
  local nome="$1" esperado="$2" regex="$3"; shift 3
  local saida got
  saida="$("$@" 2>&1)"; got=$?
  total=$((total+1))
  if [ "$got" -ne "$esperado" ]; then
    vermelhas+=("$nome")
    printf '  FALHA %s: exit=%s, esperado=%s\n' "$nome" "$got" "$esperado"
    printf '%s\n' "$saida" | sed 's/^/      /'
    return
  fi
  if [ -n "$regex" ] && ! printf '%s\n' "$saida" | grep -q -- "$regex"; then
    vermelhas+=("$nome")
    printf '  FALHA %s: saida nao casa /%s/:\n' "$nome" "$regex"
    printf '%s\n' "$saida" | sed 's/^/      /'
    return
  fi
  printf '  ok    %s (exit=%s)\n' "$nome" "$got"
}

CHK() { RFM_ESTADO_ROOT="$W" node "$CHECADOR" "$@"; }

echo "(caixa de areia: $W)"
echo
echo "== 1. plano: tarefa que cria codigo novo precisa do bloco busca: =="
escreve_design

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '' ''; } > "$P"
caso "tarefa que cria scripts/novo.cjs sem busca: é recusada" 2 'tarefa 1\..*scripts/novo\.cjs' CHK plano --slug t --plano "$P"

echo
echo "== 2. plano: forma do bloco busca: =="

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '- livro | pulado: sem repositório de terceiro' "$DESF_OK"; } > "$P"
caso "busca sem canal repo é recusada" 2 'sem o canal `repo`' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '- repo | grep -E "novo" scripts' "$DESF_OK"; } > "$P"
caso "linha sem resultado nem pulado: é recusada" 2 'linha inválida' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' "$BUSCA_OK" ''; } > "$P"
caso "desfecho ausente é recusado" 2 'falta `desfecho:`' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' "$BUSCA_OK" 'desfecho: talvez'; } > "$P"
caso "desfecho fora da lista é recusado" 2 'fora de adotar' CHK plano --slug t --plano "$P"

echo
echo "== 3. plano: o que nao cria codigo novo passa =="

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/existente.cjs`' '' ''; } > "$P"
caso "tarefa que só edita scripts/existente.cjs passa" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/testa-novo.sh`, `test/x.test.js`, `docs/x.md`' '' ''; } > "$P"
caso "tarefa que só cria testa-*, test/ e .md passa" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo-*.cjs`' '' ''; } > "$P"
caso "arquivos com glob é ignorado" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 docs '`scripts/novo-docs.cjs`' '' ''; } > "$P"
caso "tipo docs não é cobrado" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 pesquisar '`scripts/novo-pesquisa.cjs`' '' ''; } > "$P"
caso "tipo pesquisar não é cobrado" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 configurar '`scripts/novo-config.cjs`' '' ''; } > "$P"
caso "tipo configurar não é cobrado" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' "$BUSCA_OK" "$DESF_OK"; } > "$P"
caso "bloco busca: válido e completo passa" 0 'ok:' CHK plano --slug t --plano "$P"

echo
echo "== 4. estado.cjs marcar --estagio plano: a trava usa o checador =="

ES="$(mktemp -d)"; SANDBOXES+=("$ES")
EW="$(cygpath -m "$ES" 2>/dev/null || printf '%s' "$ES")"
cp -r "$RAIZ/scripts" "$RAIZ/hooks" "$ES/"
mkdir -p "$ES/docs/rainforest/estado" "$ES/docs/rainforest/design" "$ES/docs/rainforest/planos"
touch "$ES/FOCO.md"
(
  cd "$ES" || exit 1
  git init -q
  echo "// existente" > scripts/existente.cjs
  git add scripts/existente.cjs
  GIT_CONFIG_GLOBAL=/dev/null git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "base da fixture"
)
escreve_design
cp "$D" "$ES/docs/rainforest/design/t.md"
cat > "$ES/docs/rainforest/estado/t.json" <<'EOF'
{
  "slug": "t",
  "design": { "status": "aprovado", "doc": "docs/rainforest/design/t.md" }
}
EOF
EP="$ES/docs/rainforest/planos/t.md"
E() { RFM_ESTADO_ROOT="$EW" HOME="$ES/home" USERPROFILE="$ES/home" node "$EW/scripts/estado.cjs" "$@"; }

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '' ''; } > "$EP"
caso "marcar plano ok recusa plano sem busca:" 2 'scripts/novo\.cjs' E marcar --slug t --estagio plano --status ok

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' "$BUSCA_OK" "$DESF_OK"; } > "$EP"
caso "marcar plano ok aceita plano com busca:" 0 '' E marcar --slug t --estagio plano --status ok

echo
echo "== 5. conferir-fluxo cobertura: aceita busca: e desfecho: como campos de tarefa =="

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' "$BUSCA_OK" "$DESF_OK"; } > "$P"
caso "cobertura aceita tarefa com busca: e desfecho:" 0 '' env RFM_ESTADO_ROOT="$W" node "$CHECADOR_FLUXO" cobertura --slug t --design "$D" --plano "$P"

echo
echo "== 6. achados do revisor (rodada 2) =="

# Achado 1: `pulado:` nao vale para o canal repo.
{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '- repo | pulado: sem tempo' "$DESF_OK"; } > "$P"
caso "achado 1: repo com pulado: nao conta como canal repo" 2 'o canal `repo` não aceita `pulado:`' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '- repo | pulado: sem tempo
- livro | pulado: sem repositório de terceiro' 'desfecho: construir'; } > "$P"
caso "achado 1: busca so com pulado: (nada encontrado sem canais) e recusada" 2 'o canal `repo` não aceita `pulado:`' CHK plano --slug t --plano "$P"

# Achado 2: git so e' exigido quando ha candidato a caminho novo.
ND="$(mktemp -d)"; SANDBOXES+=("$ND")
{ printf '%s' "$PLANO_CAB"; tarefa 1 docs '`docs/x.md`' '' ''; } > "$ND/p.md"
caso "achado 2: sem git, plano sem candidato a caminho novo sai 0" 0 'ok:' env RFM_ESTADO_ROOT="$ND" node "$CHECADOR" plano --slug t --plano "$ND/p.md"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '' ''; } > "$ND/p.md"
caso "achado 2: sem git, plano com candidato a caminho novo continua exit 69" 69 'nao-verificavel' env RFM_ESTADO_ROOT="$ND" node "$CHECADOR" plano --slug t --plano "$ND/p.md"

# Achado 7: tests/ em qualquer nivel, barra invertida normalizada.
{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`pkg/tests/foo.py`' '' ''; } > "$P"
caso "achado 7: tests/ aninhado nao e' codigo novo" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts\existente.cjs`' '' ''; } > "$P"
caso "achado 7: barra invertida de arquivo existente passa" 0 '' CHK plano --slug t --plano "$P"

{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts\novo.cjs`' '' ''; } > "$P"
caso "achado 7: barra invertida de arquivo novo e' recusada com barra normal" 2 'scripts/novo\.cjs' CHK plano --slug t --plano "$P"

# Caixa diferente: sensivel, como o git. Documentado na skill.
{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`Scripts/Existente.cjs`' '' ''; } > "$P"
caso "achado 7: caixa diferente do HEAD conta como caminho novo (sensivel, como o git)" 2 'Scripts/Existente\.cjs' CHK plano --slug t --plano "$P"

echo
echo "== 7. achado 1 (rodada 3): pulado: so no segundo campo; | entre aspas e' consulta =="

# `pulado:` com campo de resultado depois nao e' pulado valido: e' linha invalida.
{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '- repo | pulado: sem rede | offline' "$DESF_OK"; } > "$P"
caso "repo | pulado: sem rede | offline e' recusado" 2 'leva um campo só' CHK plano --slug t --plano "$P"

# `|` entre aspas e' consulta: sem resultado depois dela, a linha nao vale.
{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '- repo | grep -E "a|b"' "$DESF_OK"; } > "$P"
caso "repo | grep -E \"a|b\" sem resultado e' recusado" 2 'sem resultado' CHK plano --slug t --plano "$P"

# Mesma consulta com resultado depois: passa.
{ printf '%s' "$PLANO_CAB"; tarefa 1 implementar '`scripts/novo.cjs`' '- repo | grep -E "a|b" | 2 candidatos: x.cjs' "$DESF_OK"; } > "$P"
caso "repo | grep -E \"a|b\" | 2 candidatos: x.cjs passa" 0 'ok:' CHK plano --slug t --plano "$P"

echo "-----------------------------------------"
echo "total=$total vermelhas:[$(IFS=,; echo "${vermelhas[*]}")]"
[ "${#vermelhas[@]}" -eq 0 ]
