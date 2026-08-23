#!/usr/bin/env bash
# Tarefa 7 (emenda de 2026-08-23) do plano
# docs/rainforest/planos/2026-08-22-agente-arqueologo.md.
#
# A revisão daquele plano achou que a mutação declarada na tarefa 4 não morde:
# `scripts/testa-perfil.sh` confere SÓ o bloco entre
# <!-- perfil-de-trabalho:inicio --> e :fim, nunca o corpo do agente. Hoje,
# apagar de agents/arqueologo.md a linha que manda carregar `Skill(arqueologia)`
# deixa aquela bateria toda verde — e é exatamente essa linha que separa
# "agente que executa a skill" (decisão D2) de "agente que duplica o método",
# o erro que D1/D2 existem para evitar.
#
# Esta bateria morde os dois lados desse par de regras:
#   1. o corpo do agente TEM que conter a chamada que carrega a skill que a
#      própria description do frontmatter promete executar;
#   2. o corpo NÃO PODE conter um trecho característico copiado ao pé da letra
#      da SKILL.md daquela skill — senão o agente duplica o método em vez de
#      delegar.
#
# Generalização (em vez de citar "arqueologo" fixo): o candidato a cada regra
# é descoberto varrendo `agents/*.md` por um padrão fixo na description —
# "... que executa a skill <nome>" — que hoje casa com agents/arqueologo.md
# (skill arqueologia) E agents/depurador.md (skill depurar), o precedente do
# mesmo desenho. O trecho característico do caso 2 também é DERIVADO lendo a
# SKILL.md correspondente em tempo de execução — nunca escrito à mão aqui.
# Lista escrita à mão é a armadilha que este repositório já pagou (ver a nota
# de scripts/testa-triagem.sh sobre grep hardcoded enganando uma medição).
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ok=0
falhou=0
soma_ok() { ok=$((ok+1)); echo "  ok   $1"; }
soma_falha() { falhou=$((falhou+1)); echo "  FALHA $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "(fixtures em: $TMP)"

# --- os scripts node (helpers) -------------------------------------------
# Escritos em arquivo, nunca em `node -e` com caminho embutido: caminho POSIX
# dentro de uma string de `node -e` não passa pela conversão de caminho do
# MSYS (ela só vale para argumento/variável de ambiente), armadilha que já
# gerou uma versão quebrada de scripts/testa-perfil.sh.

cat > "$TMP/comum.cjs" <<'EOF'
'use strict';
const fs = require('fs');

function lerFrontmatter(txt) {
  const m = txt.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!m) return { front: '', body: txt };
  return { front: m[1], body: m[2] };
}

function campoFrontmatter(front, campo) {
  // Um valor por linha ("campo: valor..."); description pode ter ':' dentro
  // do texto, então corta só no primeiro ':'.
  const linhas = front.split(/\r?\n/);
  for (const l of linhas) {
    const i = l.indexOf(':');
    if (i === -1) continue;
    const nome = l.slice(0, i).trim();
    if (nome === campo) return l.slice(i + 1).trim();
  }
  return null;
}

// Trechos "característicos" de uma SKILL.md: linhas de heading de seção
// (## ou ###, nunca o título ## /# do topo do arquivo — curto demais, casaria
// por acidente) e linhas de tabela markdown que não sejam a linha separadora
// (|---|---|). Para arqueologia isso captura o cabeçalho da tabela de
// conferência de três saídas; para depurar (sem tabela nenhuma) captura os
// headings de fase/seção. Deriva-se lendo o arquivo — nada aqui é uma lista
// escrita à mão por skill.
function assinaturasDaSkill(skillPath) {
  const txt = fs.readFileSync(skillPath, 'utf8');
  const { body } = lerFrontmatter(txt);
  const linhas = body.split(/\r?\n/);
  const assinaturas = [];
  for (const l of linhas) {
    const t = l.trim();
    if (/^#{2,3}\s+\S/.test(t)) { assinaturas.push(t); continue; }
    if (t.startsWith('|')) {
      if (/^\|[\s:|-]+\|?$/.test(t)) continue; // linha separadora da tabela
      assinaturas.push(t);
    }
  }
  return assinaturas;
}

// Para a prova de mutação (caso 3): prefere uma linha de tabela (o exemplo
// que o briefing cita, "cabeçalho da tabela de conferência de três saídas");
// sem tabela, cai no primeiro heading de seção.
function assinaturaParaTeste(assinaturas) {
  const linhaTabela = assinaturas.find((s) => s.startsWith('|'));
  return linhaTabela || assinaturas[0];
}

module.exports = { lerFrontmatter, campoFrontmatter, assinaturasDaSkill, assinaturaParaTeste };
EOF

cat > "$TMP/gate.cjs" <<'EOF'
'use strict';
const fs = require('fs');
const path = require('path');
const { lerFrontmatter, campoFrontmatter, assinaturasDaSkill } = require(path.join(__dirname, 'comum.cjs'));

const [, , agentsDir, skillsDir] = process.argv;
if (!agentsDir || !skillsDir) {
  console.error('uso: gate.cjs <agentsDir> <skillsDir>');
  process.exit(2);
}

const arquivos = fs.readdirSync(agentsDir).filter((f) => f.endsWith('.md')).sort();
const casos = [];
let candidatos = 0;

for (const arq of arquivos) {
  const caminho = path.join(agentsDir, arq);
  const txt = fs.readFileSync(caminho, 'utf8');
  const { front, body } = lerFrontmatter(txt);
  const desc = campoFrontmatter(front, 'description') || '';
  // O gatilho de seleção não usa o corpo do agente — só a description do
  // frontmatter. Isso importa: se o gatilho olhasse a própria linha
  // `Skill(...)` no corpo, removê-la faria o agente sair da amostra em vez
  // de reprovar, e a mutação passaria por vacuidade.
  const m = desc.match(/executa a skill ([a-z-]+)/);
  if (!m) continue;
  candidatos++;
  const skillNome = m[1];
  const skillPath = path.join(skillsDir, skillNome, 'SKILL.md');

  if (!fs.existsSync(skillPath)) {
    casos.push({ ok: false, label: `${arq}: skill declarada '${skillNome}' nao existe em skills/${skillNome}/SKILL.md` });
    continue;
  }
  casos.push({ ok: true, label: `${arq}: skill declarada '${skillNome}' existe em skills/${skillNome}/SKILL.md` });

  // Caso 1 — carrega de verdade.
  const chamada = `Skill(${skillNome})`;
  const carrega = body.includes(chamada);
  casos.push({ ok: carrega, label: `${arq}: o corpo carrega ${chamada}` });

  // Caso 2 — não duplica o método da skill.
  const assinaturas = assinaturasDaSkill(skillPath);
  let duplicada = null;
  for (const s of assinaturas) {
    if (s.length >= 8 && body.includes(s)) { duplicada = s; break; }
  }
  casos.push({
    ok: duplicada === null,
    label: duplicada === null
      ? `${arq}: nao duplica trecho de skills/${skillNome}/SKILL.md`
      : `${arq}: duplica trecho de skills/${skillNome}/SKILL.md -> ${JSON.stringify(duplicada)}`,
  });
}

// Guarda de vacuidade: se ninguém casar o padrão, os dois casos acima nunca
// rodam e a bateria "passaria" sem testar nada.
casos.push({ ok: candidatos >= 2, label: `pelo menos 2 agentes declaram 'executa a skill X' na description (achei ${candidatos})` });

for (const c of casos) {
  console.log((c.ok ? 'OK' : 'FALHA') + '\t' + c.label);
}
process.exit(casos.some((c) => !c.ok) ? 1 : 0);
EOF

cat > "$TMP/lista-candidatos.cjs" <<'EOF'
'use strict';
const fs = require('fs');
const path = require('path');
const { lerFrontmatter, campoFrontmatter } = require(path.join(__dirname, 'comum.cjs'));

const [, , agentsDir] = process.argv;
const arquivos = fs.readdirSync(agentsDir).filter((f) => f.endsWith('.md')).sort();
for (const arq of arquivos) {
  const txt = fs.readFileSync(path.join(agentsDir, arq), 'utf8');
  const { front } = lerFrontmatter(txt);
  const desc = campoFrontmatter(front, 'description') || '';
  const m = desc.match(/executa a skill ([a-z-]+)/);
  if (m) console.log(arq + '\t' + m[1]);
}
EOF

cat > "$TMP/remove-linha.cjs" <<'EOF'
'use strict';
const fs = require('fs');
const [, , agentFile, skillNome] = process.argv;
const chamada = `Skill(${skillNome})`;
const txt = fs.readFileSync(agentFile, 'utf8');
const linhas = txt.split(/\r?\n/);
const idx = linhas.findIndex((l) => l.includes(chamada));
if (idx === -1) {
  console.error('LINHA COM ' + chamada + ' NAO ENCONTRADA — mutacao nao aplicada');
  process.exit(3);
}
linhas.splice(idx, 1);
fs.writeFileSync(agentFile, linhas.join('\n'));
console.error('removeu a linha (continha ' + chamada + ')');
EOF

cat > "$TMP/cola-trecho.cjs" <<'EOF'
'use strict';
const fs = require('fs');
const path = require('path');
const { assinaturasDaSkill, assinaturaParaTeste } = require(path.join(__dirname, 'comum.cjs'));

const [, , agentFile, skillFile] = process.argv;
const assinaturas = assinaturasDaSkill(skillFile);
const trecho = assinaturaParaTeste(assinaturas);
if (!trecho) {
  console.error('SEM TRECHO CARACTERISTICO PARA COLAR — mutacao nao aplicada');
  process.exit(3);
}
const txt = fs.readFileSync(agentFile, 'utf8');
fs.writeFileSync(agentFile, txt + '\n' + trecho + '\n');
console.error('colou: ' + trecho);
EOF

# --- 1. fonte real, íntegro ------------------------------------------------
echo
echo "== 1. fonte real, integro: cada agente que declara 'executa a skill X' carrega e nao duplica =="
SAIDA1="$(node "$TMP/gate.cjs" "$SRC/agents" "$SRC/skills" 2>&1)"
while IFS=$'\t' read -r tag label; do
  [ -z "${tag:-}" ] && continue
  if [ "$tag" = "OK" ]; then soma_ok "$label"; else soma_falha "$label"; fi
done <<< "$SAIDA1"

# --- descobre os candidatos para as duas provas de mutação -----------------
CANDIDATOS="$(node "$TMP/lista-candidatos.cjs" "$SRC/agents")"
NCAND=0
if [ -n "$CANDIDATOS" ]; then
  NCAND=$(printf '%s\n' "$CANDIDATOS" | grep -c .)
fi

# --- 2. mutação: remove a linha que carrega a skill (numa cópia, por agente) --
echo
echo "== 2. mutacao: remove a linha que carrega a skill (numa copia, por agente) =="
if [ "$NCAND" -eq 0 ]; then
  soma_falha "nenhum candidato encontrado — nao ha o que provar aqui (bateria vazia)"
else
  while IFS=$'\t' read -r arq skillNome; do
    [ -z "$arq" ] && continue
    CAIXA="$(mktemp -d)"
    cp -r "$SRC/agents" "$CAIXA/agents"
    node "$TMP/remove-linha.cjs" "$CAIXA/agents/$arq" "$skillNome" > "$CAIXA/remove.log" 2>&1
    APLICOU=$?
    if [ "$APLICOU" -ne 0 ]; then
      soma_falha "[$arq] a mutacao (remover a linha da Skill($skillNome)) nem foi aplicada — a prova abaixo nao valeria nada"
    else
      node "$TMP/gate.cjs" "$CAIXA/agents" "$SRC/skills" > "$CAIXA/gate.log" 2>&1
      RC=$?
      PADRAO="$(printf 'FALHA\t%s: o corpo carrega Skill(%s)' "$arq" "$skillNome")"
      if [ "$RC" -ne 0 ] && grep -qF -- "$PADRAO" "$CAIXA/gate.log"; then
        soma_ok "VERMELHO [$arq]: remover a linha da Skill($skillNome) derruba o gate (exit $RC)"
      else
        soma_falha "[$arq] remover a linha da Skill($skillNome) NAO derrubou o gate — a mutacao nao morde"
        sed 's/^/         /' "$CAIXA/gate.log"
      fi
    fi
    rm -rf "$CAIXA"
  done <<< "$CANDIDATOS"
fi

# --- 3. mutação: cola um trecho característico da SKILL.md dentro do agente --
echo
echo "== 3. mutacao: cola um trecho caracteristico da SKILL.md dentro do agente (numa copia, por agente) =="
if [ "$NCAND" -eq 0 ]; then
  soma_falha "nenhum candidato encontrado — nao ha o que provar aqui (bateria vazia)"
else
  while IFS=$'\t' read -r arq skillNome; do
    [ -z "$arq" ] && continue
    CAIXA="$(mktemp -d)"
    cp -r "$SRC/agents" "$CAIXA/agents"
    node "$TMP/cola-trecho.cjs" "$CAIXA/agents/$arq" "$SRC/skills/$skillNome/SKILL.md" > "$CAIXA/cola.log" 2>&1
    APLICOU=$?
    if [ "$APLICOU" -ne 0 ]; then
      soma_falha "[$arq] a mutacao (colar trecho de skills/$skillNome/SKILL.md) nem foi aplicada — a prova abaixo nao valeria nada"
    else
      node "$TMP/gate.cjs" "$CAIXA/agents" "$SRC/skills" > "$CAIXA/gate.log" 2>&1
      RC=$?
      PADRAO="$(printf 'FALHA\t%s: duplica trecho de skills/%s/SKILL.md' "$arq" "$skillNome")"
      if [ "$RC" -ne 0 ] && grep -qF -- "$PADRAO" "$CAIXA/gate.log"; then
        soma_ok "VERMELHO [$arq]: colar trecho de skills/$skillNome/SKILL.md derruba o gate (exit $RC)"
      else
        soma_falha "[$arq] colar trecho de skills/$skillNome/SKILL.md NAO derrubou o gate — deteccao de duplicacao nao morde"
        sed 's/^/         /' "$CAIXA/gate.log"
      fi
    fi
    rm -rf "$CAIXA"
  done <<< "$CANDIDATOS"
fi

# --- 4. guarda de asserção vácua -------------------------------------------
# Esperado por candidato descoberto: 3 casos na seção 1 (skill existe / carrega
# / nao duplica) + 1 caso na secao 2 (mutacao remove) + 1 caso na secao 3
# (mutacao cola) = 5 por candidato, mais o guard de "pelo menos 2 candidatos"
# da propria secao 1. Se rodou menos que isso, alguma parte silenciosamente
# não executou.
echo
TOTAL=$((ok+falhou))
MINIMO=$((NCAND*5+1))
if [ "$TOTAL" -ge "$MINIMO" ]; then
  soma_ok "rodaram $TOTAL casos (esperado >= $MINIMO para $NCAND candidato(s))"
else
  soma_falha "rodaram so $TOTAL casos, esperado >= $MINIMO para $NCAND candidato(s) — bateria vazia por baixo"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
