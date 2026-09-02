#!/bin/bash
# Bateria dos ganchos de portoes no `estado.cjs`, e do resolvedor de caminho de doc.
# Uso: bash scripts/testa-portoes-gate.sh
#
# Tarefas 4 e 6 do plano `docs/rainforest/planos/2026-09-02-fluxo-6-portoes.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR:
#
#   1. Que o `verificar` feche com evidencia colada quando ha portoes. E' o gate
#      que o fluxo 6 inteiro existe para instalar: com `portoes.md` presente, o
#      `ok` so grava se os oraculos re-executarem e passarem AGORA. Casos G7/G8.
#
#   2. Que o `plano` feche com portoes mal autorados. Portao ruim e' defeito de
#      planejamento — pega na origem, nao na entrega. Casos G4/G5.
#
#   3. QUE O GANCHO NOVO TORNE O FLUXO OBRIGATORIO. Projeto sem `portoes.md`
#      fecha exatamente como antes. Esta e' a invariante que o proprio
#      `estado.cjs` ja documenta para design/cobertura/creep, e quebra-la seria
#      pior que nao ter o gancho. Casos G1/G2.
#
#   4. Que a `cobertura` continue INERTE. Tarefa 6: ate 2026-09-02 o
#      `conferirFechamento` derivava o caminho do design de `<slug>.md` e
#      ignorava o `design.arquivo` gravado no estado. Como nenhum design deste
#      repo se chama `<slug>.md`, a checagem nunca disparou — passou o fluxo 9
#      inteiro sem rodar uma vez. Casos G9/G10.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E="$RAIZ/scripts/estado.cjs"
PORT="$RAIZ/scripts/portoes.cjs"
FIX="$RAIZ/test/fixtures/portoes"

for f in "$E" "$PORT" "$FIX/portoes-echo.md" "$FIX/portoes-falha.md"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/docs/rainforest/design" "$S/docs/rainforest/planos" \
         "$S/docs/rainforest/portoes" "$S/docs/rainforest/estado"

afirma() {
  local nome="$1" cond="$2"
  if [ "$cond" = "1" ]; then echo "  ok   $nome"; ok=$((ok+1));
  else echo "  FALHA $nome"; falhou=$((falhou+1)); fi
}

# Roda o estado.cjs numa raiz-sandbox. `cd "$RAIZ"` de proposito: o CHECK dos
# portoes usa caminho relativo a raiz REAL do repo, e e' assim que ele roda em
# producao — o gate nao muda o cwd de quem o chamou.
est() { (cd "$RAIZ" && RFM_ESTADO_ROOT="$S" node "$E" "$@" 2>&1); }

novo_fluxo() {
  local slug="$1"
  est iniciar --slug "$slug" --titulo "sandbox" >/dev/null
  est marcar --slug "$slug" --estagio design --status aprovado >/dev/null
}

echo "== SEM portoes.md: nada muda (a invariante do opt-in) =="
novo_fluxo sem-portoes
SAIDA="$(est marcar --slug sem-portoes --estagio plano --status ok)"; C=$?
afirma "G1. plano fecha normalmente sem portoes.md" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
est exigir --slug sem-portoes --estagio executar >/dev/null
est marcar --slug sem-portoes --estagio executar --status ok \
  --json '{"comando":"bash x.sh","saida":"ok","tarefas_ok":1,"tarefas":1,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-sandbox"}]}' >/dev/null
est marcar --slug sem-portoes --estagio revisar --status ok \
  --json '{"achados":0,"base":"HEAD","head":"HEAD"}' >/dev/null
SAIDA="$(est marcar --slug sem-portoes --estagio verificar --status ok --json '{"comando":"bash x.sh","saida":"ok"}')"; C=$?
afirma "G2. verificar fecha com evidencia colada quando NAO ha portoes" \
  "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

echo "== plano: o lint dos portoes barra portao mal autorado =="
novo_fluxo lint-ruim
cp "$FIX/portoes-echo.md" "$S/docs/rainforest/portoes/lint-ruim.md"
SAIDA="$(est marcar --slug lint-ruim --estagio plano --status ok)"; C=$?
afirma "G3. plano com portao 'echo ok' RECUSA" "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "G4. e a recusa cita o motivo do lint, nao so 'falhou'" \
  "$(printf '%s' "$SAIDA" | grep -q 'saída fixa' && echo 1 || echo 0)"

novo_fluxo lint-bom
cat > "$S/docs/rainforest/portoes/lint-bom.md" <<FIM
# Portões: sandbox

- [ ] P1: o verificador de exemplo devolve o marcador de sucesso
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente
FIM
SAIDA="$(est marcar --slug lint-bom --estagio plano --status ok)"; C=$?
afirma "G5. plano com portoes bem autorados FECHA" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

echo "== verificar: a evidencia colada deixa de bastar =="
prepara_ate_revisar() {
  local slug="$1"
  # `exigir` ARMA a catraca de mutacao — sem ele o `executar ok` e' recusado.
  # Nao e' burocracia da bateria: e' a propria trava do fluxo 1, e pula-la aqui
  # faria os casos abaixo testarem um caminho que producao nunca percorre.
  est exigir --slug "$slug" --estagio executar >/dev/null
  est marcar --slug "$slug" --estagio executar --status ok \
    --json '{"comando":"bash x.sh","saida":"ok","tarefas_ok":1,"tarefas":1,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-sandbox"}]}' >/dev/null
  est marcar --slug "$slug" --estagio revisar --status ok \
    --json '{"achados":0,"base":"HEAD","head":"HEAD"}' >/dev/null
}

novo_fluxo check-falho
cat > "$S/docs/rainforest/portoes/check-falho.md" <<FIM
# Portões: sandbox com CHECK que reprova

- [ ] P1: o modulo de cobranca passa em todas as assercoes
  CHECK: node test/fixtures/portoes/scripts/sempre-falha.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente
FIM
est marcar --slug check-falho --estagio plano --status ok >/dev/null
prepara_ate_revisar check-falho
SAIDA="$(est marcar --slug check-falho --estagio verificar --status ok --json '{"comando":"bash x.sh","saida":"tudo verde"}')"; C=$?
afirma "G6. verificar RECUSA com CHECK falho, mesmo com evidencia colada bonita" \
  "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "G7. e o motivo vem do portao, nao um erro generico" \
  "$(printf '%s' "$SAIDA" | grep -q 'NAO CUMPRIDO' && echo 1 || echo 0)"

novo_fluxo check-bom
cat > "$S/docs/rainforest/portoes/check-bom.md" <<FIM
# Portões: sandbox com CHECK que passa

- [ ] P1: o verificador de exemplo devolve o marcador de sucesso
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente
FIM
est marcar --slug check-bom --estagio plano --status ok >/dev/null
prepara_ate_revisar check-bom
SAIDA="$(est marcar --slug check-bom --estagio verificar --status ok --json '{"comando":"bash x.sh","saida":"ok"}')"; C=$?
afirma "G8. verificar FECHA quando os portoes re-executam e passam" \
  "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

echo "== TAREFA 6: a cobertura deixa de ser inerte =="
# Design com nome que NAO e' <slug>.md — o caso real de todo fluxo deste repo.
novo_fluxo cobertura-viva
cat > "$S/docs/rainforest/design/fluxo-x-design.md" <<'FIM'
# Design

## Objetivo
Sandbox.

## Decisões fechadas
- **D1 — a coisa acontece de um jeito e nao de outro**

## Avaliado e descartado
Nada.

## Fora de escopo
Nada.

## Em aberto
Nada.
FIM
# Plano SEM tarefa citando D1: a cobertura tem de recusar por decisao orfa.
cat > "$S/docs/rainforest/planos/cobertura-viva.md" <<'FIM'
# Plano

### 1. Faz outra coisa [tipo: implementar]
atende: nada
arquivos: `a/**`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `a`
  de: x
  para: y
  bateria: z
pronto quando: sai 0
FIM

# Sem `design.arquivo`, o gate procura design/<slug>.md, nao acha, e NAO roda.
SAIDA="$(est marcar --slug cobertura-viva --estagio plano --status ok)"; C=$?
afirma "G9. sem design.arquivo no estado, a cobertura nao dispara (o defeito)" \
  "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

# Com `design.arquivo` gravado, o gate acha o design real e a cobertura RODA.
novo_fluxo cobertura-viva2
est marcar --slug cobertura-viva2 --estagio design --status aprovado \
  --json '{"arquivo":"docs/rainforest/design/fluxo-x-design.md"}' >/dev/null
cp "$S/docs/rainforest/planos/cobertura-viva.md" "$S/docs/rainforest/planos/cobertura-viva2.md"
SAIDA="$(est marcar --slug cobertura-viva2 --estagio plano --status ok)"; C=$?
afirma "G10. COM design.arquivo, a cobertura dispara e RECUSA a decisao orfa" \
  "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "G11. e a recusa nomeia a decisao que ficou sem tarefa" \
  "$(printf '%s' "$SAIDA" | grep -qi 'D1' && echo 1 || echo 0)"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
