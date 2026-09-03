#!/bin/bash
# Bateria do gancho de recibo no `fechar` de `estado.cjs`.
# Uso: bash scripts/testa-recibo-fechar.sh
#
# Tarefa 5 do plano `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR:
#
#   1. Que fluxo sem plano.entregaveis feche `fechar` diferentemente de hoje (D3).
#      Opt-in mora dentro de recibo.cjs, e o gancho nunca decide de antemao.
#
#   2. Que recibo seja gravado quando entregaveis estao ausentes ou `nao_provado`
#      nao foi fornecido. O `fechar` recusa ambos os casos (D4, D7).
#
#   3. Que portoes NAO sejam re-executados antes de congelar o recibo. D5 exige
#      re-verificacao com --reverificar antes de gravar.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E="$RAIZ/scripts/estado.cjs"
REC="$RAIZ/scripts/recibo.cjs"
FIX="$RAIZ/test/fixtures/portoes"

for f in "$E" "$REC"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/docs/rainforest/design" "$S/docs/rainforest/planos" \
         "$S/docs/rainforest/portoes" "$S/docs/rainforest/estado"

# R1: Copia os oráculos para a sandbox (portoes.cjs roda com cwd: RAIZ da sandbox)
mkdir -p "$S/test/fixtures/portoes/scripts"
cp "$FIX/scripts/sempre-ok.cjs" "$S/test/fixtures/portoes/scripts/"
cp "$FIX/scripts/sempre-falha.cjs" "$S/test/fixtures/portoes/scripts/"

# Inicializar sandbox como repo git para permitir git diff no revisar
(cd "$S" && git init >/dev/null 2>&1 && \
 git config user.email "test@example" >/dev/null 2>&1 && \
 git config user.name "Test" >/dev/null 2>&1)

afirma() {
  local nome="$1" cond="$2"
  if [ "$cond" = "1" ]; then echo "  ok   $nome"; ok=$((ok+1));
  else echo "  FALHA $nome"; falhou=$((falhou+1)); fi
}

# Roda o estado.cjs numa raiz-sandbox
est() { (cd "$RAIZ" && RFM_ESTADO_ROOT="$S" node "$E" "$@" 2>&1); }

novo_fluxo() {
  local slug="$1"
  est iniciar --slug "$slug" --titulo "sandbox" >/dev/null
  est marcar --slug "$slug" --estagio design --status aprovado >/dev/null
}

prepara_ate_verificar() {
  local slug="$1"
  est exigir --slug "$slug" --estagio executar >/dev/null
  est marcar --slug "$slug" --estagio executar --status ok \
    --json '{"comando":"bash x.sh","saida":"ok","tarefas_ok":1,"tarefas":1,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-sandbox"}]}' >/dev/null
  est marcar --slug "$slug" --estagio revisar --status ok \
    --json '{"achados":0,"base":"HEAD","head":"HEAD"}' >/dev/null
  est marcar --slug "$slug" --estagio verificar --status ok \
    --json '{"comando":"bash x.sh","saida":"ok"}' >/dev/null
}

echo "== SEM plano.entregaveis: fechar funciona como hoje (D3) =="
novo_fluxo sem-entregaveis
est marcar --slug sem-entregaveis --estagio plano --status ok >/dev/null
prepara_ate_verificar sem-entregaveis
SAIDA="$(est marcar --slug sem-entregaveis --estagio fechar --status ok)"; C=$?
afirma "F1. fechar OK sem plano.entregaveis (opt-in, nao trancafiado)" \
  "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

echo "== COM plano.entregaveis: validacoes obrigatorias =="

# F2: arquivo ausente
novo_fluxo entregaveis-ausentes
cat > "$S/docs/rainforest/estado/entregaveis-ausentes.json" <<'FIM'
{
  "slug": "entregaveis-ausentes",
  "design": {"status": "aprovado"},
  "plano": {"status": "ok", "entregaveis": ["arquivo-que-nao-existe.txt"]},
  "executar": {"status": "ok"},
  "revisar": {"status": "ok"},
  "verificar": {"status": "ok"}
}
FIM
prepara_ate_verificar entregaveis-ausentes
SAIDA="$(est marcar --slug entregaveis-ausentes --estagio fechar --status ok \
  --json '{"nao_provado":["algo"]}' 2>&1)"; C=$?
afirma "F2. arquivo ausente RECUSA com exit 2" \
  "$([ "$C" -eq 2 ] && echo 1 || echo 0)"
afirma "F2b. mensagem cita o caminho do arquivo" \
  "$(printf '%s' "$SAIDA" | grep -q 'arquivo-que-nao-existe' && echo 1 || echo 0)"

# F3: nao_provado ausente no json
novo_fluxo entregaveis-sem-nao-provado
mkdir -p "$S/docs/rainforest"
echo "conteudo do entregavel" > "$S/docs/rainforest/arquivo-teste.txt"
(cd "$S" && git add "docs/rainforest/arquivo-teste.txt" >/dev/null 2>&1 && \
 git commit -m "arquivo" >/dev/null 2>&1)
cat > "$S/docs/rainforest/estado/entregaveis-sem-nao-provado.json" <<'FIM'
{
  "slug": "entregaveis-sem-nao-provado",
  "design": {"status": "aprovado"},
  "plano": {"status": "ok", "entregaveis": ["docs/rainforest/arquivo-teste.txt"]},
  "executar": {"status": "ok"},
  "revisar": {"status": "ok"},
  "verificar": {"status": "ok"}
}
FIM
prepara_ate_verificar entregaveis-sem-nao-provado
# Sem --json ou com --json sem nao_provado
SAIDA="$(est marcar --slug entregaveis-sem-nao-provado --estagio fechar --status ok 2>&1)"; C=$?
afirma "F3. nao_provado ausente RECUSA com exit 2" \
  "$([ "$C" -eq 2 ] && echo 1 || echo 0)"
afirma "F3b. mensagem cita nao_provado" \
  "$(printf '%s' "$SAIDA" | grep -qi 'nao_provado' && echo 1 || echo 0)"

echo "== Caminho feliz: recibo gravado =="

novo_fluxo sucesso
echo "conteudo do entregavel" > "$S/docs/rainforest/arquivo-sucesso.txt"
(cd "$S" && git add "docs/rainforest/arquivo-sucesso.txt" >/dev/null 2>&1 && \
 git commit -m "arquivo" >/dev/null 2>&1)
cat > "$S/docs/rainforest/estado/sucesso.json" <<'FIM'
{
  "slug": "sucesso",
  "design": {"status": "aprovado"},
  "plano": {"status": "ok", "entregaveis": ["docs/rainforest/arquivo-sucesso.txt"]},
  "executar": {"status": "ok"},
  "revisar": {"status": "ok"},
  "verificar": {"status": "ok"}
}
FIM
prepara_ate_verificar sucesso
SAIDA="$(est marcar --slug sucesso --estagio fechar --status ok \
  --json '{"nao_provado":["revisao visual"]}')"; C=$?
afirma "F4. fechar com nao_provado valido EXIT 0" \
  "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
afirma "F4b. recibo foi gravado em .rainforest/colheita/" \
  "$([ -f "$S/.rainforest/colheita/sucesso-recibo.json" ] && echo 1 || echo 0)"

echo "== Portoes: re-verificacao antes de congelar (D5) =="

novo_fluxo com-portao-falho
echo "conteudo" > "$S/docs/rainforest/arquivo-portao.txt"
(cd "$S" && git add "docs/rainforest/arquivo-portao.txt" >/dev/null 2>&1 && \
 git commit -m "arquivo" >/dev/null 2>&1)
cat > "$S/docs/rainforest/estado/com-portao-falho.json" <<'FIM'
{
  "slug": "com-portao-falho",
  "design": {"status": "aprovado"},
  "plano": {"status": "ok", "entregaveis": ["docs/rainforest/arquivo-portao.txt"]},
  "executar": {"status": "ok"},
  "revisar": {"status": "ok"},
  "verificar": {"status": "ok"}
}
FIM
cat > "$S/docs/rainforest/portoes/com-portao-falho.md" <<FIM
# Portões: sandbox com CHECK que reprova

- [ ] P1: o verificador falha
  CHECK: node test/fixtures/portoes/scripts/sempre-falha.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente
FIM
prepara_ate_verificar com-portao-falho
SAIDA="$(est marcar --slug com-portao-falho --estagio fechar --status ok \
  --json '{"nao_provado":["revisao visual"]}' 2>&1)"; C=$?
afirma "F5. fechar RECUSA quando portao CHECK falha (exit != 0)" \
  "$([ "$C" -ne 0 ] && echo 1 || echo 0)"
afirma "F5b. nenhum recibo foi gravado quando portao reprova" \
  "$([ ! -f "$S/.rainforest/colheita/com-portao-falho-recibo.json" ] && echo 1 || echo 0)"

echo "== F6: CHECK com sempre-ok.cjs passa e grava recibo com portoes =="
novo_fluxo com-portao-ok
echo "conteudo" > "$S/docs/rainforest/arquivo-portao-ok.txt"
(cd "$S" && git add "docs/rainforest/arquivo-portao-ok.txt" >/dev/null 2>&1 && \
 git commit -m "arquivo" >/dev/null 2>&1)
cat > "$S/docs/rainforest/estado/com-portao-ok.json" <<'FIM'
{
  "slug": "com-portao-ok",
  "design": {"status": "aprovado"},
  "plano": {"status": "ok", "entregaveis": ["docs/rainforest/arquivo-portao-ok.txt"]},
  "executar": {"status": "ok"},
  "revisar": {"status": "ok"},
  "verificar": {"status": "ok"}
}
FIM
cat > "$S/docs/rainforest/portoes/com-portao-ok.md" <<FIM
# Portões: sandbox com CHECK que passa

- [ ] P1: o verificador passa
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente
FIM
prepara_ate_verificar com-portao-ok
SAIDA="$(est marcar --slug com-portao-ok --estagio fechar --status ok \
  --json '{"nao_provado":["revisao visual"]}')"; C=$?
afirma "F6. fechar com portao sempre-ok EXIT 0" \
  "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
afirma "F6b. recibo foi gravado em .rainforest/colheita/" \
  "$([ -f "$S/.rainforest/colheita/com-portao-ok-recibo.json" ] && echo 1 || echo 0)"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
