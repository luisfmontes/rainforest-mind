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

echo "== C1/C2: o gate enxerga o --json DA PROPRIA chamada =="
# Achados C1 e C2 da revisao independente de 2026-09-02, reproduzidos antes de
# consertar. `conferirFechamento` recebia o `estado` lido do DISCO, de antes da
# fusao com o `--json` desta chamada. Como `design` nao tem estado intermediario
# entre `pendente` e `aprovado`, a UNICA forma de anotar `arquivo` e' no mesmo
# `marcar` que fecha o estagio — e nesse instante o gate era cego para ele: caia
# no `docDe(tipo, slug)`, que nao existe, e a checagem nunca rodava. Exit 0, sem
# erro nem aviso. O `docDoEstagio` da tarefa 6 existia justamente para esse caso
# e nao alcancava o unico momento em que ele acontece.
printf 'isto nao e um design valido, sem secoes nem decisoes\n' \
  > "$S/docs/rainforest/design/malformado.md"
est iniciar --slug c1-mesma-chamada --titulo sandbox >/dev/null
SAIDA="$(est marcar --slug c1-mesma-chamada --estagio design --status aprovado \
  --json '{"arquivo":"docs/rainforest/design/malformado.md"}')"; C=$?
afirma "G12. design malformado declarado NA MESMA chamada e' RECUSADO" \
  "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "G13. e a recusa vem da checagem estrutural, nao de um erro generico" \
  "$(printf '%s' "$SAIDA" | grep -q 'seção obrigatória ausente' && echo 1 || echo 0)"

# C2: mesma causa, lado do plano. Design com D1 e D2; plano so atende D1.
cat > "$S/docs/rainforest/design/com-orfa.md" <<'FIM'
# Design

## Objetivo
Sandbox.

## Decisões fechadas
- **D1 — a primeira coisa**
- **D2 — a segunda coisa, que nenhuma tarefa vai atender**

## Avaliado e descartado
Nada.

## Fora de escopo
Nada.

## Em aberto
Nada.
FIM
cat > "$S/docs/rainforest/planos/com-orfa.md" <<'FIM'
# Plano

### 1. Faz a primeira coisa [tipo: implementar]
atende: D1
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
est iniciar --slug c2-plano --titulo sandbox >/dev/null
est marcar --slug c2-plano --estagio design --status aprovado \
  --json '{"arquivo":"docs/rainforest/design/com-orfa.md"}' >/dev/null
SAIDA="$(est marcar --slug c2-plano --estagio plano --status ok \
  --json '{"arquivo":"docs/rainforest/planos/com-orfa.md"}')"; C=$?
afirma "G14. plano declarado NA MESMA chamada dispara a cobertura e RECUSA a orfa" \
  "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "G15. e a recusa nomeia D2" \
  "$(printf '%s' "$SAIDA" | grep -q 'D2' && echo 1 || echo 0)"

echo "== A3: o arquivo declarado tem de viver na arvore do projeto =="
# Sem a cerca, um design bem formado mas NUNCA versionado (um rascunho no temp)
# era aceito como design "aprovado" do fluxo. Nao e' bypass de validacao — a
# checagem estrutural ainda roda — mas quebra a garantia que da sentido ao
# versionamento: quem vier depois nao consegue ler o que foi aprovado.
# O par DENTRO/FORA com o MESMO conteudo e' o que isola a variavel. Um teste que
# so olhasse o arquivo de estado nao mediria nada: o campo `arquivo` e' gravado
# de qualquer jeito — a cerca decide se ele e' ADOTADO pelo gate, o que so
# aparece no comportamento da checagem.
#
# O design usado tem D2 orfa, entao:
#   adotado     -> a cobertura roda no `plano ok` e RECUSA
#   nao adotado -> cai no fallback `<slug>.md`, que nao existe, e o plano FECHA
# A diferenca entre os dois casos e' SO a localizacao do arquivo.
# Diretorio IRMAO do sandbox, nao um subdiretorio dele: `$S` E' a raiz do
# projeto nesta bateria (`RFM_ESTADO_ROOT`), entao um arquivo em `$S/fora.md`
# esta DENTRO da arvore. A primeira versao deste caso errou exatamente isso e
# reprovava por medir o cenario errado.
EXTERNO="$(mktemp -d)"
trap 'rm -rf "$S" "$EXTERNO"' EXIT
FORA="$(cygpath -m "$EXTERNO" 2>/dev/null || printf '%s' "$EXTERNO")/fora-da-arvore.md"
cp "$S/docs/rainforest/design/com-orfa.md" "$FORA"
cp "$S/docs/rainforest/planos/com-orfa.md" "$S/docs/rainforest/planos/a3-fora.md"
est iniciar --slug a3-fora --titulo sandbox >/dev/null
est marcar --slug a3-fora --estagio design --status aprovado \
  --json "{\"arquivo\":\"$FORA\"}" >/dev/null
SAIDA="$(est marcar --slug a3-fora --estagio plano --status ok \
  --json '{"arquivo":"docs/rainforest/planos/a3-fora.md"}')"; C=$?
afirma "G16. design FORA da arvore nao e' adotado — a cobertura nao roda com ele" \
  "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

# O espelho: o MESMO conteudo, DENTRO da arvore, e' adotado e a cobertura recusa.
# Sem este caso, G16 passaria por qualquer motivo que impedisse a checagem.
cp "$S/docs/rainforest/planos/com-orfa.md" "$S/docs/rainforest/planos/a3-dentro.md"
est iniciar --slug a3-dentro --titulo sandbox >/dev/null
est marcar --slug a3-dentro --estagio design --status aprovado \
  --json '{"arquivo":"docs/rainforest/design/com-orfa.md"}' >/dev/null
SAIDA="$(est marcar --slug a3-dentro --estagio plano --status ok \
  --json '{"arquivo":"docs/rainforest/planos/a3-dentro.md"}')"; C=$?
afirma "G17. o MESMO design, DENTRO da arvore, e' adotado e a cobertura RECUSA" \
  "$([ "$C" -ne 0 ] && printf '%s' "$SAIDA" | grep -q 'D2' && echo 1 || echo 0)"

echo "== o gate do verificar RE-EXECUTA, nao aceita evidencia gravada =="
# Achado ao usar o gate no fechamento do proprio fluxo 6: sem `--reverificar`,
# `rodar` pula todo portao que ja tenha evidencia, e os seis sairam
# "cumprido (pulado)". O gate aprovou LENDO o arquivo em vez de executar —
# exatamente a evidencia colada que os portoes existem para substituir, so em
# JSON em vez de prosa. E' a decisao D2 do design ao contrario.
#
# O fixture e' o caso que so a re-execucao distingue: um portao com evidencia
# de SUCESSO gravada, mas cujo CHECK hoje REPROVA. Quem le o arquivo aprova;
# quem executa, recusa.
novo_fluxo evidencia-velha
cat > "$S/docs/rainforest/portoes/evidencia-velha.md" <<FIM
# Portões: evidencia de sucesso gravada, CHECK que hoje reprova

- [x] P1: o modulo de cobranca passa em todas as assercoes
  CHECK: node test/fixtures/portoes/scripts/sempre-falha.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: {"shell":"cmd.exe","cwd":".","exit":0,"match":true,"fingerprint":"deadbeef1234"}
FIM
est marcar --slug evidencia-velha --estagio plano --status ok >/dev/null
prepara_ate_revisar evidencia-velha
SAIDA="$(est marcar --slug evidencia-velha --estagio verificar --status ok --json '{"comando":"bash x.sh","saida":"ok"}')"; C=$?
afirma "G21. verificar RECUSA portao com evidencia velha cujo CHECK hoje reprova" \
  "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "G22. e a saida mostra que ele foi EXECUTADO, nao pulado" \
  "$(printf '%s' "$SAIDA" | grep -q 'pulado' && echo 0 || echo 1)"

echo "== as recusas se ACUMULAM, nao param na primeira =="
# Achado da auditoria cross-model de 2026-09-02: o retorno antecipado no lint
# fazia um plano com portao mal autorado E decisao orfa mostrar so o primeiro
# problema. Nada fechava indevidamente, mas "checagens independentes em
# sequencia" era promessa nao cumprida — continuava uma cadeia, so que maior, e
# custava duas idas para um fechamento.
est iniciar --slug dois-problemas --titulo sandbox >/dev/null
est marcar --slug dois-problemas --estagio design --status aprovado \
  --json '{"arquivo":"docs/rainforest/design/com-orfa.md"}' >/dev/null
cp "$FIX/portoes-echo.md" "$S/docs/rainforest/portoes/dois-problemas.md"
cp "$S/docs/rainforest/planos/com-orfa.md" "$S/docs/rainforest/planos/dois-problemas.md"
SAIDA="$(est marcar --slug dois-problemas --estagio plano --status ok \
  --json '{"arquivo":"docs/rainforest/planos/dois-problemas.md"}')"; C=$?
afirma "G18. plano com DOIS problemas recusa" "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "G19. e mostra os DOIS numa ida so (lint do portao E decisao orfa)" \
  "$(printf '%s' "$SAIDA" | grep -q 'saída fixa' \
    && printf '%s' "$SAIDA" | grep -q 'D2' && echo 1 || echo 0)"

echo "== a cerca e' por realpath, nao por comparacao de string =="
# `path.resolve` + `startsWith` e' teste LEXICO: uma junction dentro da raiz
# apontando para fora passa nele, e o checador acaba lendo o arquivo externo.
# No Windows qualquer usuario cria junction sem privilegio. Achado da auditoria
# cross-model sobre a primeira versao desta mesma cerca, escrita horas antes.
LINK="$S/docs/rainforest/design/atalho"
CRIOU=0
if [ "${OS:-}" = "Windows_NT" ]; then
  cmd //c mklink //J "$(cygpath -w "$LINK")" "$(cygpath -w "$EXTERNO")" >/dev/null 2>&1 && CRIOU=1
else
  ln -s "$EXTERNO" "$LINK" 2>/dev/null && CRIOU=1
fi
if [ "$CRIOU" -eq 1 ]; then
  cp "$S/docs/rainforest/planos/com-orfa.md" "$S/docs/rainforest/planos/via-link.md"
  est iniciar --slug via-link --titulo sandbox >/dev/null
  est marcar --slug via-link --estagio design --status aprovado \
    --json '{"arquivo":"docs/rainforest/design/atalho/fora-da-arvore.md"}' >/dev/null
  SAIDA="$(est marcar --slug via-link --estagio plano --status ok \
    --json '{"arquivo":"docs/rainforest/planos/via-link.md"}')"; C=$?
  afirma "G20. link DENTRO da raiz apontando para FORA nao e' adotado" \
    "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
else
  echo "  ok   G20. (pulado: nao consegui criar link nesta maquina)"
  ok=$((ok+1))
fi

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
