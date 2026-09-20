#!/usr/bin/env bash
# testa-conferir-invariantes.sh — bateria para validar conferir-invariantes.cjs
#
# Valida:
# 1. O script passa com o repositório íntegro
# 2. O script falha quando uma frase é movida para depois de <!-- detalhe --> (rainforest-mind)
# 3. O script detecta frases proibidas (tipo: nao_deve) quando presentes
# 4. O script passa quando frases proibidas estão ausentes
# 5. O script detecta quando frase obrigatória é removida (skills de ação)
# 6. O script detecta duplicação de frases
# 7. O script falha com exit ≠ 0 quando nenhum invariantes.json existe
# 8. O script falha com exit ≠ 0 quando tipo desconhecido é usado
# 9. O script falha com exit 1 quando o campo `frase` está ausente ou vazio
# 10. O `nao_deve` casa sem distinguir caixa, como o `/i` do enxerto (D5)
# 11. O script falha com exit 1 quando o `invariantes.json` é array vazio
# 12. O script falha com exit 1 quando o `invariantes.json` não é array, sem stack do Node
# 13. O script falha com exit 1 quando `onde` está presente sem degrau reconhecido
# 14. O script falha com exit 1 quando a invariante traz chave desconhecida
# 15. O script falha com exit 1 quando `nao_deve` traz `onde`
# 16. CADA bloco rotulado `# (n) MUTAÇÃO:` — mais o do degrau — sai 0 na sua
#     própria caixa ANTES de mutar, asserido por `assere_base`. Os blocos
#     rotulados `# Caso:` NÃO chamam `assere_base`; ver a nota dos dois rótulos
#     logo abaixo
# 17. O roster de skills protegidas continua o mesmo — a contagem e a etiqueta do
#     caso saem de `ROSTER_ESPERADO` e `ROSTER_INVARIANTES`, nunca de literal solto
# 18. O script falha com exit 1 quando `onde` traz degrau desconhecido AO LADO de
#     um válido, com a mutação canônica dentro da caixa
# 19. TODA frase `nao_deve` dos `skills/*/invariantes.json` DE PRODUÇÃO é
#     detectável quando plantada no corpo — e varredura que não acha entrada
#     nenhuma é VERMELHA, nunca verde silencioso
#
# Sobre o item 16, que é linha de base e não caso: até 2026-09-20 a `$CAIXA` das
# mutações era UMA, criada no setup e nunca restaurada entre os blocos. Duas
# coisas quebravam por causa disso. A primeira: ela não copiava
# `skills/rainforest-mind/references/`, então já saía **exit 2** antes da
# primeira mutação. A segunda, achada pela terceira revisão depois que a cópia
# entrou: do bloco (2) em diante cada bloco rodava sobre a árvore que o anterior
# estragou, e como todos só aferem `exit != 0`, qualquer um deles podia virar
# no-op — alvo de `replace` errado, frase renomeada, refactor — e continuar
# imprimindo `ok VERMELHO`. Medido sem aplicar nenhuma das mutações (2) a (5):
# todas as quatro continuavam verdes. O conserto é cada bloco montar a SUA caixa
# com `nova_caixa_rf` e asserir a linha de base dela antes de mutar; a asserção
# por bloco é o que impede esse vácuo de voltar em silêncio.
#
# A afirmação "CADA bloco" só passou a ser verdadeira em 2026-09-20. Sobrava um
# bloco (6), meta-teste sem `assere_base`, com caminho fixo `/tmp/meta-ref` no
# lugar de `mktemp -d` e com a saída engolida por `> /dev/null 2>&1` — e ele
# repetia a mutação do bloco (4). Foi apagado; o porquê, medido, está no lugar
# onde ele ficava, no fim deste arquivo.
#
# OS DOIS RÓTULOS, e de qual deles o item 16 fala — precisado em 2026-09-20, por
# achado da SEXTA revisão. O arquivo tem duas categorias de bloco, e só a
# primeira chama `assere_base`:
#
#   - `# (n) MUTAÇÃO:` — os cinco numerados, mais o do degrau desconhecido. Mutam
#     a árvore da `rainforest-mind` dentro de `nova_caixa_rf` e são os que o item
#     16 nomeia: cada um tem `assere_base` imediatamente antes da mutação.
#   - `# Caso:` — as caixas de areia montadas à mão, `CAIXA_LIMPAR` e `CAIXA_DUP`
#     entre elas. Elas também gravam `SKILL.md` mutado e NÃO chamam `assere_base`.
#     Não há perda de medição: as duas abortam explícito com `MUTACAO NAO
#     APLICADA` (ou com a frase-alvo não encontrada) e exigem `-eq 2` mais `grep`
#     nomeando a skill, então vermelho de vácuo não passa por elas. Ler "CADA
#     bloco de mutação" como se as cobrisse é que era falso.
#
#   A exceção declarada: o caso `VIVACIDADE`, que é `# Caso:` e mesmo assim
#   assere a SUA linha de base, uma por entrada varrida, porque o número de
#   caixas dele não é fixo no fonte — sai da árvore de produção.
#
# Autoria de `tipo: nao_deve`:
# - Frase proibida só vale se for vocabulário que o texto correto nunca usa
# - Exemplo: `--confirmo` é proibido no `fechar` e obrigatório no `limpar`, então
#   um `nao_deve: --confirmo` dispararia no texto certo — proibido
# - `CONFIRMO fechar issue` é seguro: não existe em nenhuma skill correta

set -u

cd "$(dirname "$0")/.." || exit 1

ok=0
falhou=0

marca() {
  if [ "$2" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1"
  fi
}

echo "== invariantes nao foram perdidas na extracao ===="
echo

# Caso 1: O repositório íntegro passa
node scripts/conferir-invariantes.cjs > /tmp/invariantes-check.log 2>&1
REPO_INTEGRO=$?
marca "repositorio integro passa no conferir" $REPO_INTEGRO

# Funções auxiliares
nova_caixa() {
  local tmp="$(mktemp -d)"
  mkdir -p "$tmp/skills/rainforest-mind" "$tmp/scripts"
  cp scripts/conferir-invariantes.cjs "$tmp/scripts/"
  cp -r hooks "$tmp/"
  echo "$tmp"
}

# Caixa completa da `rainforest-mind` — a única skill com a marca `<!-- detalhe -->`,
# então as mutações de núcleo e de referência só existem aqui. Cada bloco de
# mutação monta a SUA caixa: até 2026-09-20 havia uma só, nunca restaurada, e do
# bloco (2) em diante cada um rodava sobre a árvore estragada pelo anterior.
nova_caixa_rf() {
  local tmp="$(mktemp -d)"
  mkdir -p "$tmp/skills/rainforest-mind" "$tmp/scripts"
  cp scripts/conferir-invariantes.cjs "$tmp/scripts/"
  cp skills/rainforest-mind/invariantes.json "$tmp/skills/rainforest-mind/"
  cp skills/rainforest-mind/SKILL.md "$tmp/skills/rainforest-mind/SKILL.md"
  # A invariante da regra 15 exige o degrau `referencia`. Sem esta cópia a caixa
  # nasce exit 2 e a mutação do bloco vira no-op.
  cp -r skills/rainforest-mind/references "$tmp/skills/rainforest-mind/"
  cp -r hooks "$tmp/"
  echo "$tmp"
}

# Asserção de linha de base de UM bloco de mutação: a caixa íntegra tem de sair 0
# ANTES de mutar. Sem ela o bloco só afere `exit != 0`, e caixa que já sai != 0 dá
# vermelho de vácuo — a mutação pode não medir nada e o caso imprime `ok`.
# $1 = caixa   $2 = nome do caso (começa com LINHA DE BASE)
assere_base() {
  (cd "$1/scripts" && node conferir-invariantes.cjs > /tmp/caixa-linha-de-base.log 2>&1)
  local estado=$?
  if [ "$estado" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok   $2 (exit 0)"
  else
    falhou=$((falhou+1)); echo "  FALHA $2 — saiu $estado; a mutacao deste bloco NAO MEDE NADA"
    sed 's/^/    | /' /tmp/caixa-linha-de-base.log
  fi
}

# Roster: QUAIS skills estão protegidas. O checador pula em silêncio diretório de
# skill sem `invariantes.json` — e tem de continuar pulando, porque as caixas de
# areia acima dependem disso. A guarda "zero arquivos sai 1" é satisfeita para
# sempre pela `rainforest-mind` sozinha, então apagar os seis arquivos das skills
# de ação tirava dez frases da proteção com o CI verde (achado da revisão,
# 2026-09-20). Quem tranca isso é a asserção de roster + contagem abaixo.
#
# A contagem, o número de arquivos e a etiqueta do caso saem de UMA fonte só.
# Até 2026-09-20 eram três strings independentes — o literal `-eq 15` da
# `roster_verde` e a etiqueta `(7 arquivos, 15 invariantes)` repetida em três
# lugares —, e quem acrescentasse uma invariante mexeria no número e esqueceria a
# etiqueta: o placar diria "15" asserindo 16 (achado da quinta revisão).
ROSTER_ESPERADO="executar fechar limpar plano rainforest-mind revisar verificar"
ROSTER_INVARIANTES=15
ROSTER_ARQUIVOS="$(printf '%s\n' $ROSTER_ESPERADO | wc -l | tr -d ' ')"
ROSTER_ETIQUETA="ROSTER: as skills protegidas continuam as mesmas ($ROSTER_ARQUIVOS arquivos, $ROSTER_INVARIANTES invariantes)"
ROSTER_ATUAL=""
ROSTER_EXIT=-1
ROSTER_CONTAGEM=-1

# Preenche ROSTER_ATUAL / ROSTER_EXIT / ROSTER_CONTAGEM a partir da árvore em $1
avalia_roster() {
  ROSTER_ATUAL="$(cd "$1" && for f in skills/*/invariantes.json; do
    [ -e "$f" ] && basename "$(dirname "$f")"
  done | LC_ALL=C sort | tr '\n' ' ' | sed 's/ *$//')"
  (cd "$1/scripts" && node conferir-invariantes.cjs > /tmp/roster.log 2>&1)
  ROSTER_EXIT=$?
  ROSTER_CONTAGEM="$(sed -n 's/.*conferidas \([0-9][0-9]*\) invariantes.*/\1/p' /tmp/roster.log | head -1)"
  [ -n "$ROSTER_CONTAGEM" ] || ROSTER_CONTAGEM=-1
}

roster_verde() {
  if [ "$ROSTER_ESPERADO" = "$ROSTER_ATUAL" ] && [ "$ROSTER_EXIT" -eq 0 ] && [ "$ROSTER_CONTAGEM" -eq "$ROSTER_INVARIANTES" ]; then
    return 0
  fi
  return 1
}

ROSTER_OK=1
avalia_roster "."
if ! roster_verde; then
  ROSTER_OK=0
  echo "    (repo real: esperado [$ROSTER_ESPERADO])"
  echo "    (repo real: atual    [$ROSTER_ATUAL])"
  echo "    (repo real: conferir saiu $ROSTER_EXIT, conferiu $ROSTER_CONTAGEM invariantes)"
  echo "    (skill protegida a mais ou a menos, de proposito? atualize ROSTER_ESPERADO e ROSTER_INVARIANTES aqui neste arquivo — a contagem de arquivos e a etiqueta do caso saem deles)"
fi
# Controle da própria trava: com um `invariantes.json` a menos, o roster TEM de
# ficar vermelho. Sem este controle, `roster_verde` sempre-verdadeiro passaria
# despercebido — a trava existiria sem trancar nada.
CAIXA_ROSTER="$(mktemp -d)"
mkdir -p "$CAIXA_ROSTER/scripts"
cp scripts/conferir-invariantes.cjs "$CAIXA_ROSTER/scripts/"
cp -r hooks "$CAIXA_ROSTER/"
for f in skills/*/invariantes.json; do
  s="$(basename "$(dirname "$f")")"
  mkdir -p "$CAIXA_ROSTER/skills/$s"
  cp "skills/$s/invariantes.json" "skills/$s/SKILL.md" "$CAIXA_ROSTER/skills/$s/"
  if [ -d "skills/$s/references" ]; then cp -r "skills/$s/references" "$CAIXA_ROSTER/skills/$s/"; fi
done
rm -f "$CAIXA_ROSTER/skills/limpar/invariantes.json"
avalia_roster "$CAIXA_ROSTER"
if roster_verde; then
  ROSTER_OK=0
  echo "    (controle: apagar skills/limpar/invariantes.json NAO deixou o roster vermelho — a trava nao tranca nada)"
  echo "    (controle: atual [$ROSTER_ATUAL], conferir saiu $ROSTER_EXIT, conferiu $ROSTER_CONTAGEM invariantes)"
fi
rm -rf "$CAIXA_ROSTER"
if [ "$ROSTER_OK" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   $ROSTER_ETIQUETA"
else
  falhou=$((falhou+1)); echo "  FALHA $ROSTER_ETIQUETA"
fi

# Caso: nao_deve: frase proibida presente no corpo reprova
CAIXA_NAODEV="$(nova_caixa)"
mkdir -p "$CAIXA_NAODEV/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_NAODEV/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"CONFIRMO fechar issue","tipo":"nao_deve"}]' > "$CAIXA_NAODEV/skills/fechar/invariantes.json"
printf '%s\n' 'CONFIRMO fechar issue' >> "$CAIXA_NAODEV/skills/fechar/SKILL.md"
(cd "$CAIXA_NAODEV/scripts" && node conferir-invariantes.cjs > /tmp/naodev-presente.log 2>&1)
NAODEV_PRESENTE=$?
if [ "$NAODEV_PRESENTE" -eq 2 ] && grep -q "fechar" /tmp/naodev-presente.log && grep -q "CONFIRMO fechar issue" /tmp/naodev-presente.log; then
  ok=$((ok+1)); echo "  ok   VERDE: nao_deve: frase proibida presente no corpo reprova (exit $NAODEV_PRESENTE)"
else
  falhou=$((falhou+1)); echo "  FALHA: nao_deve deveria falhar com exit 2 (saiu $NAODEV_PRESENTE)"
fi
rm -rf "$CAIXA_NAODEV"

# Caso: nao_deve: frase proibida ausente no corpo passa
CAIXA_NAODEV_OK="$(nova_caixa)"
mkdir -p "$CAIXA_NAODEV_OK/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_NAODEV_OK/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"CONFIRMO fechar issue","tipo":"nao_deve"}]' > "$CAIXA_NAODEV_OK/skills/fechar/invariantes.json"
(cd "$CAIXA_NAODEV_OK/scripts" && node conferir-invariantes.cjs > /tmp/naodev-ausente.log 2>&1)
NAODEV_AUSENTE=$?
if [ "$NAODEV_AUSENTE" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok   VERDE: nao_deve: frase proibida ausente no corpo passa (exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA: nao_deve ausente deveria passar (saiu $NAODEV_AUSENTE)"
fi
rm -rf "$CAIXA_NAODEV_OK"

# Caso: VIVACIDADE das frases `nao_deve` de PRODUCAO.
#
# O que este caso existe para pegar, achado da SEXTA revisao em 2026-09-20: um
# `nao_deve` BEM-FORMADO cuja frase foi grafada errado. Ele aprova quando a frase
# NAO esta no corpo, entao um typo (`CONFIRM0` por `CONFIRMO`) faz o invariante
# procurar para sempre uma string que nunca vai existir — roster intacto, contagem
# intacta, CI verde, e uma das invariantes deixou de medir qualquer coisa.
#
# A varredura por frase-inexistente que fechou a classe da forma malformada na
# quinta rodada e' CEGA a este campo POR CONSTRUCAO: para um `nao_deve`,
# frase-que-nao-existe e' a condicao de APROVACAO, nao de recusa. As nove `deve`
# falham FECHADO sob o mesmo typo; so a `nao_deve` falha ABERTO.
#
# O conserto nao esta no sensor — nenhum sensor decide se uma frase proibida e'
# "significativa", porque ela legitimamente nao esta no corpo. O que este caso
# acrescenta e' controle de VIVACIDADE contra a arvore real, no mesmo padrao que a
# trava de roster acima usa com `avalia_roster "."`: para CADA entrada
# `tipo: "nao_deve"` dos `skills/*/invariantes.json` DE PRODUCAO, a frase e' LIDA
# do arquivo (nunca digitada aqui), plantada no `SKILL.md` daquela skill dentro de
# uma caixa de areia, e o checador tem de sair 2 nomeando a skill. `nao_deve`
# futuro fica coberto sem ninguem lembrar de escrever caso novo.
#
# LIMITE MEDIDO, para a setima revisao nao ler mais do que esta escrito: plantar a
# frase lida do arquivo prova que o caminho `nao_deve` MEDE a arvore de producao e
# que a varredura achou entrada; NAO distingue frase certa de frase com typo.
# Medido em 2026-09-20 com `CONFIRM0 fechar issue` no lugar de `CONFIRMO fechar
# issue`: plantada, ela tambem sai 2, e este caso fica VERDE. Distinguir as duas
# exige uma SEGUNDA fonte da frase (um pino no padrao de `ROSTER_ESPERADO`), que
# esta rodada NAO tem — a forma fica aberta e declarada, nunca dada por fechada.
#
# Tres coisas sao aferidas, e as tres tem de valer:
# 1. a varredura achou PELO MENOS uma entrada — laco vazio e' VERMELHO, nunca
#    verde silencioso, que seria o mesmo defeito outra vez;
# 2. a caixa integra sai 0 ANTES de plantar — sem isso o exit 2 depois do plantio
#    seria vermelho de vacuo, o defeito que `assere_base` existe para impedir;
# 3. depois de plantada, a saida e' exit 2 com a skill nomeada entre colchetes e a
#    mensagem de frase proibida. O `grep` nunca procura a frase em si: frase futura
#    pode trazer metacaractere de regex.
#
# A LINHA QUE DESLIGA ESTE CASO e' a condicao do `if` marcado `# DESLIGA` abaixo.
VIVACIDADE_OK=1
VIVACIDADE_N=0
VIVACIDADE_PARES="$(node -e "
const fs=require('fs');
const path=require('path');
for (const skill of fs.readdirSync('skills').sort()) {
  const alvo=path.join('skills',skill,'invariantes.json');
  if (!fs.existsSync(alvo)) continue;
  let inv;
  try { inv=JSON.parse(fs.readFileSync(alvo,'utf8')); } catch (e) { continue; }
  if (!Array.isArray(inv)) continue;
  inv.forEach((entrada,i) => {
    if (entrada && typeof entrada==='object' && entrada.tipo==='nao_deve') console.log(skill+' '+i);
  });
}
")"
while read -r VIVA_SKILL VIVA_IDX; do
  [ -n "$VIVA_SKILL" ] || continue
  VIVACIDADE_N=$((VIVACIDADE_N+1))
  CAIXA_VIVA="$(nova_caixa)"
  mkdir -p "$CAIXA_VIVA/skills/$VIVA_SKILL"
  cp "skills/$VIVA_SKILL/invariantes.json" "skills/$VIVA_SKILL/SKILL.md" "$CAIXA_VIVA/skills/$VIVA_SKILL/"
  if [ -d "skills/$VIVA_SKILL/references" ]; then cp -r "skills/$VIVA_SKILL/references" "$CAIXA_VIVA/skills/$VIVA_SKILL/"; fi

  # Linha de base DESTE plantio: a caixa integra tem de sair 0 antes de plantar.
  (cd "$CAIXA_VIVA/scripts" && node conferir-invariantes.cjs > /tmp/vivacidade-base.log 2>&1)
  VIVA_BASE=$?
  if [ "$VIVA_BASE" -ne 0 ]; then
    VIVACIDADE_OK=0
    echo "    ($VIVA_SKILL #$VIVA_IDX: caixa integra saiu $VIVA_BASE ANTES de plantar — o plantio nao mediria nada)"
    sed 's/^/    | /' /tmp/vivacidade-base.log
    rm -rf "$CAIXA_VIVA"
    continue
  fi

  # Planta a frase LIDA do invariantes.json daquela skill. A frase nunca atravessa
  # o shell: quem le e quem escreve e' o mesmo processo node.
  (cd "$CAIXA_VIVA/scripts" && VIVA_SKILL="$VIVA_SKILL" VIVA_IDX="$VIVA_IDX" node -e "
const fs=require('fs');
const skill=process.env.VIVA_SKILL;
const i=Number(process.env.VIVA_IDX);
const inv=JSON.parse(fs.readFileSync('../skills/'+skill+'/invariantes.json','utf8'));
const frase=inv[i] && inv[i].frase;
if (typeof frase!=='string' || frase.length===0) { console.error('frase ausente ou vazia na entrada '+i); process.exit(3); }
const arquivo='../skills/'+skill+'/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');
const depois=antes+String.fromCharCode(10)+frase+String.fromCharCode(10);
if (antes===depois) { console.error('MUTACAO NAO APLICADA'); process.exit(3); }
fs.writeFileSync(arquivo,depois);
" 2>&1)
  VIVA_PLANTIO=$?
  if [ "$VIVA_PLANTIO" -ne 0 ]; then
    VIVACIDADE_OK=0
    echo "    ($VIVA_SKILL #$VIVA_IDX: nao consegui plantar a frase lida do arquivo, saiu $VIVA_PLANTIO)"
    rm -rf "$CAIXA_VIVA"
    continue
  fi

  (cd "$CAIXA_VIVA/scripts" && node conferir-invariantes.cjs > /tmp/vivacidade.log 2>&1)
  VIVA_EXIT=$?
  # DESLIGA: esta condicao e' a unica afericao do caso. Neutraliza-la (trocar por
  # `if true; then`) desliga a vivacidade inteira sem mexer em mais nada.
  if [ "$VIVA_EXIT" -eq 2 ] && grep -q "\[$VIVA_SKILL\]" /tmp/vivacidade.log && grep -q "frase proibida encontrada" /tmp/vivacidade.log; then
    :
  else
    VIVACIDADE_OK=0
    echo "    ($VIVA_SKILL #$VIVA_IDX: com a frase de producao plantada no corpo, esperava exit 2 nomeando [$VIVA_SKILL], saiu $VIVA_EXIT)"
    sed 's/^/    | /' /tmp/vivacidade.log
  fi
  rm -rf "$CAIXA_VIVA"
done <<VIVACIDADE_FIM
$VIVACIDADE_PARES
VIVACIDADE_FIM
if [ "$VIVACIDADE_N" -eq 0 ]; then
  VIVACIDADE_OK=0
  echo "    (a varredura nao achou NENHUMA entrada tipo nao_deve em skills/*/invariantes.json — laco vazio nao e' verde)"
fi
if [ "$VIVACIDADE_OK" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   VIVACIDADE: toda frase nao_deve de producao e detectavel quando plantada ($VIVACIDADE_N entrada(s), todas exit 2)"
else
  falhou=$((falhou+1)); echo "  FALHA VIVACIDADE: toda frase nao_deve de producao e detectavel quando plantada ($VIVACIDADE_N entrada(s) varrida(s))"
fi

# Caso: skill de acao: frase obrigatoria removida do corpo reprova
CAIXA_LIMPAR="$(nova_caixa)"
mkdir -p "$CAIXA_LIMPAR/skills/limpar"
cp skills/limpar/SKILL.md "$CAIXA_LIMPAR/skills/limpar/SKILL.md"
printf '%s\n' '[{"frase":"Nunca entra na remoção"}]' > "$CAIXA_LIMPAR/skills/limpar/invariantes.json"
(cd "$CAIXA_LIMPAR/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/limpar/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');
if (!antes.includes('Nunca entra na remoção')) {
  console.error('Nao achei a frase Nunca entra na remoção');
  process.exit(3);
}
const depois = antes.replace('Nunca entra na remoção', '');
if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
" 2>&1)
MUTACAO_LIMPAR=$?
if [ "$MUTACAO_LIMPAR" -eq 0 ]; then
  (cd "$CAIXA_LIMPAR/scripts" && node conferir-invariantes.cjs > /tmp/limpar-removida.log 2>&1)
  FALHA_LIMPAR=$?
  if [ "$FALHA_LIMPAR" -eq 2 ] && grep -q "limpar" /tmp/limpar-removida.log; then
    ok=$((ok+1)); echo "  ok   VERMELHO: skill de acao: frase obrigatoria removida do corpo reprova (exit $FALHA_LIMPAR)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase removida deveria falhar com exit 2 (saiu $FALHA_LIMPAR)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar mutacao na limpar"
fi
rm -rf "$CAIXA_LIMPAR"

# Caso: deve duplicado: frase aparecendo 2x reprova
CAIXA_DUP="$(nova_caixa)"
mkdir -p "$CAIXA_DUP/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_DUP/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"O destino da branch é sempre PR"}]' > "$CAIXA_DUP/skills/fechar/invariantes.json"
(cd "$CAIXA_DUP/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/fechar/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');
if (!antes.includes('O destino da branch é sempre PR')) {
  console.error('Nao achei a frase');
  process.exit(3);
}
const depois = antes.replace('O destino da branch é sempre PR', 'O destino da branch é sempre PR\n\nRepetição: O destino da branch é sempre PR');
fs.writeFileSync(arquivo, depois);
" 2>&1)
MUTACAO_DUP=$?
if [ "$MUTACAO_DUP" -eq 0 ]; then
  (cd "$CAIXA_DUP/scripts" && node conferir-invariantes.cjs > /tmp/dup.log 2>&1)
  FALHA_DUP=$?
  if [ "$FALHA_DUP" -eq 2 ] && grep -q "aparece 2 vezes" /tmp/dup.log; then
    ok=$((ok+1)); echo "  ok   VERMELHO: deve duplicado reprova com contagem (exit $FALHA_DUP)"
  else
    falhou=$((falhou+1)); echo "  FALHA: duplicação deveria falhar com exit 2 (saiu $FALHA_DUP)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar mutacao duplicacao"
fi
rm -rf "$CAIXA_DUP"

# Caso: zero arquivos invariantes.json reprova
CAIXA_VAZIA="$(nova_caixa)"
(cd "$CAIXA_VAZIA/scripts" && node conferir-invariantes.cjs > /tmp/vazia.log 2>&1)
FALHA_VAZIA=$?
if [ "$FALHA_VAZIA" -ne 0 ]; then
  ok=$((ok+1)); echo "  ok   VERMELHO: zero arquivos invariantes reprova (exit $FALHA_VAZIA)"
else
  falhou=$((falhou+1)); echo "  FALHA: zero arquivos deveria falhar"
fi
rm -rf "$CAIXA_VAZIA"

# Caso: tipo desconhecido reprova
CAIXA_TIPO="$(nova_caixa)"
mkdir -p "$CAIXA_TIPO/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_TIPO/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"test","tipo":"invalido"}]' > "$CAIXA_TIPO/skills/fechar/invariantes.json"
(cd "$CAIXA_TIPO/scripts" && node conferir-invariantes.cjs > /tmp/tipo-invalido.log 2>&1)
FALHA_TIPO=$?
if [ "$FALHA_TIPO" -ne 0 ]; then
  ok=$((ok+1)); echo "  ok   VERMELHO: tipo desconhecido reprova (exit $FALHA_TIPO)"
else
  falhou=$((falhou+1)); echo "  FALHA: tipo invalido deveria falhar"
fi
rm -rf "$CAIXA_TIPO"

# Caso: frase ausente na invariante (chave digitada errada) reprova
CAIXA_SEM_FRASE="$(nova_caixa)"
mkdir -p "$CAIXA_SEM_FRASE/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_SEM_FRASE/skills/fechar/SKILL.md"
printf '%s\n' '[{"tipo":"nao_deve","frasse":"CONFIRMO fechar issue"}]' > "$CAIXA_SEM_FRASE/skills/fechar/invariantes.json"
printf '%s\n' 'CONFIRMO fechar issue' >> "$CAIXA_SEM_FRASE/skills/fechar/SKILL.md"
(cd "$CAIXA_SEM_FRASE/scripts" && node conferir-invariantes.cjs > /tmp/sem-frase.log 2>&1)
SEM_FRASE=$?
if [ "$SEM_FRASE" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   VERMELHO: frase ausente na invariante reprova (exit $SEM_FRASE)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: frase ausente na invariante reprova (exit 1) — saiu $SEM_FRASE"
fi
rm -rf "$CAIXA_SEM_FRASE"

# Caso: nao_deve casa com caixa diferente — restaura o semantico do `/i` do enxerto (D5)
CAIXA_NAODEV_CAIXA="$(nova_caixa)"
mkdir -p "$CAIXA_NAODEV_CAIXA/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_NAODEV_CAIXA/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"CONFIRMO fechar issue","tipo":"nao_deve"}]' > "$CAIXA_NAODEV_CAIXA/skills/fechar/invariantes.json"
printf '%s\n' 'Confirmo fechar issue #12' >> "$CAIXA_NAODEV_CAIXA/skills/fechar/SKILL.md"
(cd "$CAIXA_NAODEV_CAIXA/scripts" && node conferir-invariantes.cjs > /tmp/naodev-caixa.log 2>&1)
NAODEV_CAIXA=$?
if [ "$NAODEV_CAIXA" -eq 2 ] && grep -q "fechar" /tmp/naodev-caixa.log; then
  ok=$((ok+1)); echo "  ok   VERMELHO: nao_deve casa com caixa diferente (exit 2)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: nao_deve casa com caixa diferente (exit 2) — saiu $NAODEV_CAIXA"
fi
rm -rf "$CAIXA_NAODEV_CAIXA"

# Caso: invariantes.json com array vazio reprova (nao "ok: conferidas 0 invariantes")
CAIXA_ARR_VAZIO="$(nova_caixa)"
mkdir -p "$CAIXA_ARR_VAZIO/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_ARR_VAZIO/skills/fechar/SKILL.md"
printf '%s\n' '[]' > "$CAIXA_ARR_VAZIO/skills/fechar/invariantes.json"
(cd "$CAIXA_ARR_VAZIO/scripts" && node conferir-invariantes.cjs > /tmp/arr-vazio.log 2>&1)
ARR_VAZIO=$?
if [ "$ARR_VAZIO" -eq 1 ] && grep -q "fechar" /tmp/arr-vazio.log; then
  ok=$((ok+1)); echo "  ok   VERMELHO: invariantes.json com array vazio reprova (exit 1)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: invariantes.json com array vazio reprova (exit 1) — saiu $ARR_VAZIO"
fi
rm -rf "$CAIXA_ARR_VAZIO"

# Caso: invariantes.json fora do formato array reprova com mensagem legivel, sem stack do Node
# As tres ultimas formas sao ELEMENTO fora de formato DENTRO do array, e QUAL
# DELAS MEDE a guarda foi corrigido em 2026-09-20, por achado da quinta revisao.
# A redacao anterior dizia que as tres batiam na desestruturacao e saiam com
# stack cru de TypeError. So `[null]` faz isso: desestruturar uma string ou um
# numero e' legal em JavaScript, entao `["x"]` e `[42]` nunca estouraram.
# Medido com a validacao de forma neutralizada:
#   [null]  exit=1  TypeError: sim
#   ["x"]   exit=1  TypeError: nao -> "campo frase ausente ou vazio"
#   [42]    exit=1  TypeError: nao -> "campo frase ausente ou vazio"
# Ou seja: **so `[null]` distingue a guarda presente da guarda ausente**. As
# outras duas ficam porque documentam a mensagem legivel, nao porque medem a
# guarda — e um dia em que `["x"]` passar a sair 2 ou 0 elas vao valer a linha.
FORA_FORMATO_OK=1
for conteudo in '{"frase":"x"}' 'null' '"texto"' '42' '[null]' '["x"]' '[42]'; do
  CAIXA_FORA="$(nova_caixa)"
  mkdir -p "$CAIXA_FORA/skills/fechar"
  cp skills/fechar/SKILL.md "$CAIXA_FORA/skills/fechar/SKILL.md"
  printf '%s\n' "$conteudo" > "$CAIXA_FORA/skills/fechar/invariantes.json"
  (cd "$CAIXA_FORA/scripts" && node conferir-invariantes.cjs > /tmp/fora-formato.log 2>&1)
  FORA=$?
  if [ "$FORA" -ne 1 ] || ! grep -q "fechar" /tmp/fora-formato.log || grep -q "TypeError" /tmp/fora-formato.log; then
    FORA_FORMATO_OK=0
    echo "    (forma [$conteudo] saiu $FORA)"
  fi
  rm -rf "$CAIXA_FORA"
done
if [ "$FORA_FORMATO_OK" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   VERMELHO: invariantes.json fora do formato array reprova sem stack (exit 1)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: invariantes.json fora do formato array reprova sem stack (exit 1)"
fi

# Caso: `onde` presente sem degrau reconhecido reprova — antes desligava a checagem em silencio
ONDE_SEM_DEGRAU_OK=1
for conteudo in '[{"frase":"FRASE QUE NAO EXISTE EM LUGAR NENHUM","onde":[]}]' '[{"frase":"FRASE QUE NAO EXISTE EM LUGAR NENHUM","onde":null}]' '[{"frase":"FRASE QUE NAO EXISTE EM LUGAR NENHUM","onde":["outro"]}]'; do
  CAIXA_ONDE="$(nova_caixa)"
  mkdir -p "$CAIXA_ONDE/skills/fechar"
  cp skills/fechar/SKILL.md "$CAIXA_ONDE/skills/fechar/SKILL.md"
  printf '%s\n' "$conteudo" > "$CAIXA_ONDE/skills/fechar/invariantes.json"
  (cd "$CAIXA_ONDE/scripts" && node conferir-invariantes.cjs > /tmp/onde-sem-degrau.log 2>&1)
  ONDE=$?
  if [ "$ONDE" -ne 1 ] || ! grep -q "fechar" /tmp/onde-sem-degrau.log || grep -q "TypeError" /tmp/onde-sem-degrau.log; then
    ONDE_SEM_DEGRAU_OK=0
    echo "    (forma [$conteudo] saiu $ONDE)"
  fi
  rm -rf "$CAIXA_ONDE"
done
# Controle: a MESMA frase inexistente SEM o campo `onde` continua saindo 2, nao 1 —
# `onde` ausente e' presenca no corpo (D4) e nao pode virar erro de configuracao.
CAIXA_SEM_ONDE="$(nova_caixa)"
mkdir -p "$CAIXA_SEM_ONDE/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_SEM_ONDE/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"FRASE QUE NAO EXISTE EM LUGAR NENHUM"}]' > "$CAIXA_SEM_ONDE/skills/fechar/invariantes.json"
(cd "$CAIXA_SEM_ONDE/scripts" && node conferir-invariantes.cjs > /tmp/sem-onde.log 2>&1)
SEM_ONDE=$?
if [ "$SEM_ONDE" -ne 2 ]; then
  ONDE_SEM_DEGRAU_OK=0
  echo "    (controle: frase inexistente SEM onde deveria sair 2, saiu $SEM_ONDE)"
fi
rm -rf "$CAIXA_SEM_ONDE"
if [ "$ONDE_SEM_DEGRAU_OK" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   VERMELHO: onde presente sem degrau reconhecido reprova (exit 1)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: onde presente sem degrau reconhecido reprova (exit 1)"
fi

# Caso: degrau desconhecido AO LADO de um valido — a forma IRMA da anterior, e a
# quinta forma desta mesma classe a ser achada. A guarda de antes era
# `onde.some(d => DEGRAUS.includes(d))`: exigia UM degrau reconhecido e ignorava
# todos os outros em silencio. A rodada 4 fechou o nome da CHAVE (`ondes` por
# `onde`) e deixou aberto o nome do DEGRAU dentro dela.
#
# Este caso exercita o CENARIO INTEIRO, nao so a recusa: a mutacao canonica do
# projeto — a mesma do bloco (1) — fica DENTRO da caixa, e entao o `onde` da
# regra 10 e' variado. O controle com `nucleo` escrito certo tem de sair 2 (a
# mutacao E' medida); so depois disso o `nucelo` tem valor de prova. Medido na
# base 3e967643: `["skill","nucleo"]` -> exit 2, `["skill","nucelo"]` -> exit 0.
#
# O `onde` e' reescrito parseando o JSON, nunca por `sed`: a string `nucleo`
# aparece 5 vezes em `skills/rainforest-mind/invariantes.json` e uma troca de
# texto casaria todas as cinco.
CAIXA_DEGRAU="$(nova_caixa_rf)"
assere_base "$CAIXA_DEGRAU" "LINHA DE BASE (degrau): caixa integra passa antes da mutacao do degrau"
(cd "$CAIXA_DEGRAU/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/rainforest-mind/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');
const regex = /(\*\*10\. [^\n]+\n(?:[^\n]+\n)*?)(\<!-- detalhe -->)/;
const match = antes.match(regex);
if (!match) { console.error('Nao achei regra 10 ou marca detalhe'); process.exit(3); }
if (!match[1].includes('3.000+ tokens')) { console.error('Nao achei a frase 3.000+ tokens na regra 10'); process.exit(3); }
const depois = antes.replace(match[0], match[1].replace('3.000+ tokens', '') + match[2] + '\n3.000+ tokens vai aqui nos detalhes');
if (antes === depois) { console.error('MUTACAO NAO APLICADA'); process.exit(3); }
fs.writeFileSync(arquivo, depois);
")
MUTACAO_DEGRAU=$?

# Reescreve o campo `onde` da invariante da regra 10 com o JSON recebido em \$1.
degrau_com_onde() {
  (cd "$CAIXA_DEGRAU/scripts" && ONDE_NOVO="$1" node -e "
const fs=require('fs');
const caminho='../skills/rainforest-mind/invariantes.json';
const inv=JSON.parse(fs.readFileSync(caminho,'utf8'));
const alvo=inv.find(i => i.regra === 10);
if (!alvo) { console.error('Nao achei a invariante da regra 10'); process.exit(3); }
alvo.onde=JSON.parse(process.env.ONDE_NOVO);
fs.writeFileSync(caminho, JSON.stringify(inv, null, 2));
")
}

DEGRAU_OK=1
if [ "$MUTACAO_DEGRAU" -eq 0 ]; then
  # Controle: com `nucleo` escrito certo, a mutacao canonica E' medida — exit 2.
  # Sem este controle o vermelho abaixo poderia vir de caixa quebrada.
  degrau_com_onde '["skill","nucleo"]'
  (cd "$CAIXA_DEGRAU/scripts" && node conferir-invariantes.cjs > /tmp/degrau-controle.log 2>&1)
  DEGRAU_CONTROLE=$?
  if [ "$DEGRAU_CONTROLE" -ne 2 ]; then
    DEGRAU_OK=0
    echo "    (controle: onde [skill,nucleo] com a mutacao canonica dentro deveria sair 2, saiu $DEGRAU_CONTROLE)"
    sed 's/^/    | /' /tmp/degrau-controle.log
  fi
  # A medida: um degrau lixo AO LADO do valido. Ate 2026-09-20 saia 0 aqui.
  degrau_com_onde '["skill","nucelo"]'
  (cd "$CAIXA_DEGRAU/scripts" && node conferir-invariantes.cjs > /tmp/degrau-lixo.log 2>&1)
  DEGRAU_LIXO=$?
  if [ "$DEGRAU_LIXO" -ne 1 ] || ! grep -q "nucelo" /tmp/degrau-lixo.log || ! grep -q "rainforest-mind" /tmp/degrau-lixo.log || grep -q "TypeError" /tmp/degrau-lixo.log; then
    DEGRAU_OK=0
    echo "    (onde [skill,nucelo] saiu $DEGRAU_LIXO, esperado 1 — com a mutacao canonica dentro da caixa; saiu 0 na base 3e967643, que e' o defeito que este caso tranca)"
    sed 's/^/    | /' /tmp/degrau-lixo.log
  fi
else
  DEGRAU_OK=0
  echo "    (nao consegui aplicar a mutacao canonica na caixa do degrau)"
fi
if [ "$DEGRAU_OK" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   VERMELHO: degrau desconhecido ao lado de valido reprova (exit 1)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: degrau desconhecido ao lado de valido reprova (exit 1)"
fi
rm -rf "$CAIXA_DEGRAU"

# Caso: chave desconhecida na invariante reprova — antes era descartada em silencio.
# A segunda forma e' a medida: `ondes` no lugar de `onde` derrubava as cinco
# invariantes da rainforest-mind para presenca-no-corpo, e a mutacao canonica do
# projeto passava com exit 0.
CHAVE_DESCONHECIDA_OK=1
for conteudo in '[{"frase":"x","xpto":"lixo"}]' '[{"frase":"O destino da branch é sempre PR","ondes":["skill","nucleo"]}]'; do
  CAIXA_CHAVE="$(nova_caixa)"
  mkdir -p "$CAIXA_CHAVE/skills/fechar"
  cp skills/fechar/SKILL.md "$CAIXA_CHAVE/skills/fechar/SKILL.md"
  printf '%s\n' "$conteudo" > "$CAIXA_CHAVE/skills/fechar/invariantes.json"
  (cd "$CAIXA_CHAVE/scripts" && node conferir-invariantes.cjs > /tmp/chave-desconhecida.log 2>&1)
  CHAVE=$?
  if [ "$CHAVE" -ne 1 ] || ! grep -q "fechar" /tmp/chave-desconhecida.log || grep -q "TypeError" /tmp/chave-desconhecida.log; then
    CHAVE_DESCONHECIDA_OK=0
    echo "    (forma [$conteudo] saiu $CHAVE)"
  fi
  rm -rf "$CAIXA_CHAVE"
done
# Controle: a MESMA frase SEM a chave estranha continua saindo 0 — a recusa e' da
# chave, nao da frase.
CAIXA_CHAVE_OK="$(nova_caixa)"
mkdir -p "$CAIXA_CHAVE_OK/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_CHAVE_OK/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"O destino da branch é sempre PR"}]' > "$CAIXA_CHAVE_OK/skills/fechar/invariantes.json"
(cd "$CAIXA_CHAVE_OK/scripts" && node conferir-invariantes.cjs > /tmp/chave-conhecida.log 2>&1)
CHAVE_OK=$?
if [ "$CHAVE_OK" -ne 0 ]; then
  CHAVE_DESCONHECIDA_OK=0
  echo "    (controle: a mesma frase sem chave estranha deveria sair 0, saiu $CHAVE_OK)"
fi
rm -rf "$CAIXA_CHAVE_OK"
if [ "$CHAVE_DESCONHECIDA_OK" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   VERMELHO: chave desconhecida na invariante reprova (exit 1)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: chave desconhecida na invariante reprova (exit 1)"
fi

# Caso: `onde` numa invariante `nao_deve` reprova — era aceito e ignorado, o que
# dava aparencia de checagem por degrau que nunca existiu.
CAIXA_NAODEV_ONDE="$(nova_caixa)"
mkdir -p "$CAIXA_NAODEV_ONDE/skills/fechar"
cp skills/fechar/SKILL.md "$CAIXA_NAODEV_ONDE/skills/fechar/SKILL.md"
printf '%s\n' '[{"frase":"CONFIRMO fechar issue","tipo":"nao_deve","onde":["skill"]}]' > "$CAIXA_NAODEV_ONDE/skills/fechar/invariantes.json"
(cd "$CAIXA_NAODEV_ONDE/scripts" && node conferir-invariantes.cjs > /tmp/naodev-onde.log 2>&1)
NAODEV_ONDE=$?
if [ "$NAODEV_ONDE" -eq 1 ] && grep -q "fechar" /tmp/naodev-onde.log && grep -q "nao_deve" /tmp/naodev-onde.log; then
  ok=$((ok+1)); echo "  ok   VERMELHO: onde em invariante nao_deve reprova (exit 1)"
else
  falhou=$((falhou+1)); echo "  FALHA VERMELHO: onde em invariante nao_deve reprova (exit 1) — saiu $NAODEV_ONDE"
fi
rm -rf "$CAIXA_NAODEV_ONDE"

# Casos vermelhos para rainforest-mind — mutações numa CÓPIA, nunca no repo.
# CADA bloco monta a sua caixa com `nova_caixa_rf`, assere a linha de base dela e
# só então muta. A caixa única de antes deixava os blocos (2) a (5) rodando sobre
# a árvore estragada pelo anterior, onde qualquer mutação no-op dava `ok VERMELHO`.

# (1) MUTAÇÃO: mover a frase "3.000+ tokens" para DEPOIS de <!-- detalhe --> no SKILL.md
# Encontra a regra 10, remove "3.000+ tokens" dela, colocando a frase após a marca detalhe
CAIXA1="$(nova_caixa_rf)"
assere_base "$CAIXA1" "LINHA DE BASE (1): caixa integra passa antes da mutacao 1"
(cd "$CAIXA1/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/rainforest-mind/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');

// Encontrar a regra 10 e sua marca detalhe
const regex = /(\*\*10\. [^\n]+\n(?:[^\n]+\n)*?)(\<!-- detalhe -->)/;
const match = antes.match(regex);

if (!match) {
  console.error('Nao achei regra 10 ou marca detalhe');
  process.exit(3);
}

// Mover a frase: remover do núcleo e adicionar após a marca
let regra10 = match[1];
if (!regra10.includes('3.000+ tokens')) {
  console.error('Nao achei a frase 3.000+ tokens na regra 10');
  process.exit(3);
}

// Remover a frase do núcleo (a frase antes da marca detalhe)
const regra10SemFrase = regra10.replace('3.000+ tokens', '');
const detalhe = match[2];
// Colocar a frase após a marca detalhe (a frase agora vem depois)
const depois = antes.replace(match[0], regra10SemFrase + detalhe + '\n3.000+ tokens vai aqui nos detalhes');

if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
")
MUTACAO1=$?

if [ "$MUTACAO1" -eq 0 ]; then
  # Agora executar o conferir na cópia com a mutação
  (cd "$CAIXA1/scripts" && node conferir-invariantes.cjs > /tmp/mutacao1.log 2>&1)
  VERMELHO1=$?
  if [ "$VERMELHO1" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase movida para apos detalhe derruba conferir (exit $VERMELHO1)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase movida para apos detalhe passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a primeira mutacao"
fi
rm -rf "$CAIXA1"

# (2) MUTAÇÃO: remover a frase "exit ≠ 0 nunca é sucesso" de regra 12
# (a cópia de `references` saiu daqui em 2026-09-20: ela copiava para um diretório
#  chamado `referencias`, que o checador nunca abre, e agora `nova_caixa_rf` copia
#  para o nome certo antes da linha de base deste bloco)
CAIXA2="$(nova_caixa_rf)"
assere_base "$CAIXA2" "LINHA DE BASE (2): caixa integra passa antes da mutacao 2"
(cd "$CAIXA2/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/rainforest-mind/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');

// Encontrar e remover a frase
if (!antes.includes('exit ≠ 0 nunca é sucesso')) {
  console.error('Nao achei a frase exit ≠ 0 nunca é sucesso');
  process.exit(3);
}

const depois = antes.replace('exit ≠ 0 nunca é sucesso', 'exit diferente de zero[REMOVIDO]');

if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
")
MUTACAO2=$?

if [ "$MUTACAO2" -eq 0 ]; then
  (cd "$CAIXA2/scripts" && node conferir-invariantes.cjs > /tmp/mutacao2.log 2>&1)
  VERMELHO2=$?
  if [ "$VERMELHO2" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase removida derruba conferir (exit $VERMELHO2)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase removida passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a segunda mutacao"
fi
rm -rf "$CAIXA2"

# (3) MUTAÇÃO: mover a frase "nunca a `main`" para DEPOIS de <!-- detalhe --> (testa checagem de nucleo)
# Frase que existe em SKILL.md, está em references/, mas é movida para apos a marca detalhe
# Deve falhar pois existe em SKILL mas não chega ao nucleo extraído
CAIXA3="$(nova_caixa_rf)"
assere_base "$CAIXA3" "LINHA DE BASE (3): caixa integra passa antes da mutacao 3"
(cd "$CAIXA3/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/rainforest-mind/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');

// Encontrar a regra 11 e sua marca detalhe
const regex = /(\*\*11\. [^\n]+\n(?:[^\n]+\n)*?)(\<!-- detalhe -->)/;
const match = antes.match(regex);

if (!match) {
  console.error('Nao achei regra 11 ou marca detalhe');
  process.exit(3);
}

// Mover a frase: remover do núcleo e adicionar após a marca
let regra11 = match[1];
if (!regra11.includes('nunca a \`main\`')) {
  console.error('Nao achei a frase nunca a \`main\` na regra 11');
  process.exit(3);
}

// Remover a frase do núcleo
const regra11SemFrase = regra11.replace('nunca a \`main\`', '');
const detalhe = match[2];
// Colocar a frase após a marca detalhe
const depois = antes.replace(match[0], regra11SemFrase + detalhe + '\nnunca a \`main\` está escrito nos detalhes');

if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
")
MUTACAO3=$?

if [ "$MUTACAO3" -eq 0 ]; then
  (cd "$CAIXA3/scripts" && node conferir-invariantes.cjs > /tmp/mutacao3.log 2>&1)
  VERMELHO3=$?
  if [ "$VERMELHO3" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase movida para apos detalhe nao chega ao nucleo (exit $VERMELHO3)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase movida para apos detalhe passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a terceira mutacao"
fi
rm -rf "$CAIXA3"

# (4) MUTAÇÃO: remover a frase da references/regra-15.md (testa checagem de referencia)
# (a cópia de `references` saiu daqui em 2026-09-20: `nova_caixa_rf` já a copia, e
#  repetir sobre um diretório existente criava `references/references/`)
CAIXA4="$(nova_caixa_rf)"
assere_base "$CAIXA4" "LINHA DE BASE (4): caixa integra passa antes da mutacao 4"
(cd "$CAIXA4/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/rainforest-mind/references/regra-15.md';
const antes=fs.readFileSync(arquivo,'utf8');

// Encontrar e remover a frase printenv NOME
if (!antes.includes('printenv NOME')) {
  console.error('Nao achei a frase printenv NOME na regra 15');
  process.exit(3);
}

const depois = antes.replace('printenv NOME', 'printenv VARNAME');

if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
")
MUTACAO4=$?

if [ "$MUTACAO4" -eq 0 ]; then
  (cd "$CAIXA4/scripts" && node conferir-invariantes.cjs > /tmp/mutacao4.log 2>&1)
  VERMELHO4=$?
  if [ "$VERMELHO4" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase removida da referencia derruba conferir (exit $VERMELHO4)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase removida da referencia passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a quarta mutacao"
fi
rm -rf "$CAIXA4"

# (5) MUTAÇÃO: mover a frase "pelo `ideias.cjs plantar`" (regra 13) para DEPOIS
# de <!-- detalhe --> — o degrau `nucleo` da ÚNICA invariante que não tinha
# mutação nenhuma apontada para ela.
#
# Caixa própria, como os demais: até 2026-09-20 este bloco reusava a árvore dos
# anteriores e só restaurava o `SKILL.md`, deixando `references/regra-15.md` com a
# mutação do bloco (4) dentro — a caixa nascia vermelha e o vermelho dele era vácuo.
#
# O ALVO mudou em 2026-09-20, por achado da quinta revisão: até então este bloco
# era o bloco (1) copiado, mudando só o nome da variável de shell — mutava
# `3.000+ tokens` (regra 10) exatamente como ele. O comentário prometia "checa
# que nucleoContent está sendo validado" e o plano registrava a duplicação como
# fato ("quatro distintos — o (5) repete o (1)"). Em vez de fazer o comentário
# admitir a repetição, o bloco passou a valer a sua linha: das cinco invariantes
# da `rainforest-mind`, a da regra 13 era a única sem mutação que a exercitasse
# (10 pelo bloco (1), 11 pelo (3), 12 pelo (2), 15 pelo (4)). Agora o comentário
# é verdade E a cobertura é nova.
CAIXA5="$(nova_caixa_rf)"
assere_base "$CAIXA5" "LINHA DE BASE (5): caixa integra passa antes da mutacao 5"
(cd "$CAIXA5/scripts" && node -e "
const fs=require('fs');
const arquivo='../skills/rainforest-mind/SKILL.md';
const antes=fs.readFileSync(arquivo,'utf8');

// Encontrar a regra 13 e sua marca detalhe
const regex = /(\*\*13\. [^\n]+\n(?:[^\n]+\n)*?)(\<!-- detalhe -->)/;
const match = antes.match(regex);

if (!match) {
  console.error('Nao achei regra 13 ou marca detalhe');
  process.exit(3);
}

// Mover a frase: remover do núcleo e adicionar após a marca
let regra13 = match[1];
if (!regra13.includes('pelo \`ideias.cjs plantar\`')) {
  console.error('Nao achei a frase pelo ideias.cjs plantar na regra 13');
  process.exit(3);
}

// Remover a frase do núcleo (a frase antes da marca detalhe)
const regra13SemFrase = regra13.replace('pelo \`ideias.cjs plantar\`', '');
const detalhe = match[2];
// Colocar a frase após a marca detalhe (a frase agora vem depois)
const depois = antes.replace(match[0], regra13SemFrase + detalhe + '\nobservação se grava pelo \`ideias.cjs plantar\`, diz o detalhe');

if (antes === depois) {
  console.error('MUTACAO NAO APLICADA');
  process.exit(3);
}
fs.writeFileSync(arquivo, depois);
")
MUTACAO5=$?

if [ "$MUTACAO5" -eq 0 ]; then
  (cd "$CAIXA5/scripts" && node conferir-invariantes.cjs > /tmp/mutacao5.log 2>&1)
  VERMELHO5=$?
  # Exige a regra 13 nomeada no stderr: sem isso o vermelho poderia vir de
  # qualquer outra invariante e o bloco voltaria a medir o que o (1) já mede.
  if [ "$VERMELHO5" -ne 0 ] && grep -q "regra-13" /tmp/mutacao5.log; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase da regra 13 movida para apos detalhe nao chega ao nucleo (exit $VERMELHO5)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase da regra 13 movida para apos detalhe nao derrubou o conferir citando regra-13 (saiu $VERMELHO5)"
    sed 's/^/    | /' /tmp/mutacao5.log
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a quinta mutacao"
fi
rm -rf "$CAIXA5"

# O bloco (6), "META-TESTE: referencia check detecta frase removida", foi APAGADO
# em 2026-09-20, por achado da quinta revisão. Três motivos, e o terceiro sozinho
# já bastava:
#
# 1. Era o ÚNICO bloco de mutação sem `assere_base` — e sem caixa própria de
#    verdade: montava `/tmp/meta-ref` com caminho FIXO, fora do `mktemp -d`, o
#    que ainda fazia duas execuções concorrentes da bateria brigarem pela mesma
#    pasta.
# 2. Repetia, byte a byte, a mutação do bloco (4) — `printenv NOME` ->
#    `printenv VARNAME` em `references/regra-15.md`. O degrau `referencia` já é
#    coberto lá, com caixa própria e linha de base asserida.
# 3. `) > /dev/null 2>&1` engolia a saída, e a única aferição era `-ne 0`. Medido
#    em 2026-09-20: desligando a cópia de `references/` SÓ deste bloco, ele
#    imprimia `ok META-TESTE` sobre caixa quebrada e a bateria seguia `26/0` —
#    vermelho de vácuo, exatamente o defeito que a asserção de linha de base
#    existe para impedir.
#
# Apagar, em vez de dar caixa e linha de base a ele, é o que torna VERDADEIRA a
# afirmação do item 16 do cabeçalho: agora CADA bloco rotulado `# (n) MUTAÇÃO:`
# que existe tem a sua caixa e a sua linha de base asserida. Manter uma sexta
# cópia da mutação do (4) só para satisfazer a contagem seria inflar o placar sem
# acrescentar medida.
#
# O que o item 16 NÃO diz, precisado em 2026-09-20: os blocos rotulados `# Caso:`
# que gravam `SKILL.md` mutado — `CAIXA_LIMPAR` e `CAIXA_DUP` — não chamam
# `assere_base`, e continuam assim de propósito. Eles abortam explícito quando a
# mutação não pega e exigem `-eq 2` mais `grep`, que é o que fecha o vácuo neles.

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
