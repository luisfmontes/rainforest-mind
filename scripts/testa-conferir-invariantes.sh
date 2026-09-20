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

# Casos vermelhos para rainforest-mind — mutações numa CÓPIA, nunca no repo
CAIXA="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}"' EXIT

mkdir -p "$CAIXA/skills/rainforest-mind" "$CAIXA/scripts"
cp scripts/conferir-invariantes.cjs "$CAIXA/scripts/"
cp skills/rainforest-mind/invariantes.json "$CAIXA/skills/rainforest-mind/"
cp skills/rainforest-mind/SKILL.md "$CAIXA/skills/rainforest-mind/SKILL.md"
cp -r hooks "$CAIXA/"

# (1) MUTAÇÃO: mover a frase "3.000+ tokens" para DEPOIS de <!-- detalhe --> no SKILL.md
# Encontra a regra 10, remove "3.000+ tokens" dela, colocando a frase após a marca detalhe
(cd "$CAIXA/scripts" && node -e "
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
  (cd "$CAIXA/scripts" && node conferir-invariantes.cjs > /tmp/mutacao1.log 2>&1)
  VERMELHO1=$?
  if [ "$VERMELHO1" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase movida para apos detalhe derruba conferir (exit $VERMELHO1)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase movida para apos detalhe passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a primeira mutacao"
fi

# (2) MUTAÇÃO: remover a frase "exit ≠ 0 nunca é sucesso" de regra 12
cp -r skills/rainforest-mind/references "$CAIXA/skills/rainforest-mind/referencias"
(cd "$CAIXA/scripts" && node -e "
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
  (cd "$CAIXA/scripts" && node conferir-invariantes.cjs > /tmp/mutacao2.log 2>&1)
  VERMELHO2=$?
  if [ "$VERMELHO2" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase removida derruba conferir (exit $VERMELHO2)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase removida passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a segunda mutacao"
fi

# (3) MUTAÇÃO: mover a frase "nunca a `main`" para DEPOIS de <!-- detalhe --> (testa checagem de nucleo)
# Frase que existe em SKILL.md, está em references/, mas é movida para apos a marca detalhe
# Deve falhar pois existe em SKILL mas não chega ao nucleo extraído
(cd "$CAIXA/scripts" && node -e "
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
  (cd "$CAIXA/scripts" && node conferir-invariantes.cjs > /tmp/mutacao3.log 2>&1)
  VERMELHO3=$?
  if [ "$VERMELHO3" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase movida para apos detalhe nao chega ao nucleo (exit $VERMELHO3)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase movida para apos detalhe passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a terceira mutacao"
fi

# (4) MUTAÇÃO: remover a frase da references/regra-15.md (testa checagem de referencia)
# Cria um cópia da árvore com a referência disponível
cp -r skills/rainforest-mind/references "$CAIXA/skills/rainforest-mind/"
(cd "$CAIXA/scripts" && node -e "
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
  (cd "$CAIXA/scripts" && node conferir-invariantes.cjs > /tmp/mutacao4.log 2>&1)
  VERMELHO4=$?
  if [ "$VERMELHO4" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase removida da referencia derruba conferir (exit $VERMELHO4)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase removida da referencia passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a quarta mutacao"
fi

# (5) MUTAÇÃO: mover frase "3.000+ tokens" para depois de detalhe (checa que nucleoContent está sendo validado)
# Reutiliza a árvore anterior com references já copiadas, mas reseta SKILL.md
cp skills/rainforest-mind/SKILL.md "$CAIXA/skills/rainforest-mind/SKILL.md"
(cd "$CAIXA/scripts" && node -e "
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
MUTACAO5=$?

if [ "$MUTACAO5" -eq 0 ]; then
  (cd "$CAIXA/scripts" && node conferir-invariantes.cjs > /tmp/mutacao5.log 2>&1)
  VERMELHO5=$?
  if [ "$VERMELHO5" -ne 0 ]; then
    ok=$((ok+1)); echo "  ok   VERMELHO: frase 3.000+ tokens movida para apos detalhe derruba conferir (exit $VERMELHO5)"
  else
    falhou=$((falhou+1)); echo "  FALHA: frase movida para apos detalhe passou (deveria falhar)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA: nao consegui aplicar a quinta mutacao"
fi

# (6) MUTAÇÃO VERIFICAÇÃO: testa que o conferir detecta quando frase é removida da referencia
# Esta é uma meta-verificação que prova que a checagem de referencia está funcionando
# Diretamente inline para evitar issues com heredoc e subprocessos
(
  mkdir -p /tmp/meta-ref/skills/rainforest-mind/references /tmp/meta-ref/scripts /tmp/meta-ref/hooks
  cp scripts/conferir-invariantes.cjs /tmp/meta-ref/scripts/
  cp skills/rainforest-mind/invariantes.json /tmp/meta-ref/skills/rainforest-mind/
  cp skills/rainforest-mind/SKILL.md /tmp/meta-ref/skills/rainforest-mind/
  cp -r skills/rainforest-mind/references /tmp/meta-ref/skills/rainforest-mind/
  cp -r hooks /tmp/meta-ref/
  # Remove a frase da referencia para testar que a checagem funciona
  sed 's/printenv NOME/printenv VARNAME/g' /tmp/meta-ref/skills/rainforest-mind/references/regra-15.md > /tmp/meta-ref/skills/rainforest-mind/references/regra-15.md.tmp
  mv /tmp/meta-ref/skills/rainforest-mind/references/regra-15.md.tmp /tmp/meta-ref/skills/rainforest-mind/references/regra-15.md
  # Executa o conferir na cópia com a mutação
  (cd /tmp/meta-ref/scripts && node conferir-invariantes.cjs) > /dev/null 2>&1
  RESULTADO=$?
  rm -rf /tmp/meta-ref
  # Deve sair com código 1 (falha) se printenv NOME for removido da referencia
  [ "$RESULTADO" -ne 0 ]
) > /dev/null 2>&1
TESTE_REF=$?
if [ "$TESTE_REF" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok   META-TESTE: referencia check detecta frase removida"
else
  falhou=$((falhou+1)); echo "  FALHA: meta-teste para referencia check falhou"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
