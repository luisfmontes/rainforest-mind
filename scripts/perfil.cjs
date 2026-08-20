#!/usr/bin/env node
/**
 * Mantém o bloco de perfil de trabalho em sincronia entre a fonte
 * (`referencias/perfil-de-trabalho.md`) e os sete `agents/*.md`.
 *
 * Por que existe: o padrão de evidência do usuário precisa chegar ao SUBAGENTE,
 * e as 17 regras da skill não chegam lá — o agente só vê o próprio `.md` e o
 * briefing. Até aqui isso era recontado à mão a cada despacho, e o que fosse
 * esquecido simplesmente não existia.
 *
 * Por que por script, e não editando os sete na mão: valor que vive em vários
 * lugares diverge em silêncio. Foi o que aconteceu com a versão do plugin em
 * 2026-08-14 (plugin.json em 0.65.0, README em 0.63.0, cinco revisões passando
 * por cima), e o `testa-versao.sh` nasceu disso. Mesmo princípio aqui: a fonte
 * é uma, os demais se conferem contra ela.
 *
 * Uso:
 *   node scripts/perfil.cjs --aplicar    escreve o bloco nos agentes
 *   node scripts/perfil.cjs --conferir   exit 0 se todos batem, 1 se divergem
 */

const fs = require('fs');
const path = require('path');

const RAIZ = path.resolve(__dirname, '..');
const FONTE = path.join(RAIZ, 'referencias', 'perfil-de-trabalho.md');
const DIR_AGENTES = path.join(RAIZ, 'agents');

const INICIO = '<!-- perfil-de-trabalho:inicio -->';
const FIM = '<!-- perfil-de-trabalho:fim -->';

function lerBloco() {
  const texto = fs.readFileSync(FONTE, 'utf8');
  const i = texto.indexOf(INICIO);
  const f = texto.indexOf(FIM);
  if (i === -1 || f === -1 || f < i) {
    console.error(`ERRO: marcadores nao encontrados em ${FONTE}`);
    process.exit(2);
  }
  return texto.slice(i, f + FIM.length);
}

function agentes() {
  return fs.readdirSync(DIR_AGENTES)
    .filter((n) => n.endsWith('.md'))
    .map((n) => path.join(DIR_AGENTES, n));
}

// Insere ou substitui o bloco. Agente sem bloco recebe no FIM do arquivo —
// nunca no topo: o topo tem o frontmatter, e o metodo de trabalho do agente
// vem antes do padrao de evidencia.
function aplicarEm(caminho, bloco) {
  const texto = fs.readFileSync(caminho, 'utf8');
  const i = texto.indexOf(INICIO);
  const f = texto.indexOf(FIM);

  if (i !== -1 && f !== -1 && f > i) {
    const novo = texto.slice(0, i) + bloco + texto.slice(f + FIM.length);
    if (novo === texto) return false;
    fs.writeFileSync(caminho, novo);
    return true;
  }

  const separador = texto.endsWith('\n') ? '\n' : '\n\n';
  fs.writeFileSync(caminho, texto + separador + bloco + '\n');
  return true;
}

function extrairBloco(texto) {
  const i = texto.indexOf(INICIO);
  const f = texto.indexOf(FIM);
  if (i === -1 || f === -1 || f < i) return null;
  return texto.slice(i, f + FIM.length);
}

function main() {
  const modo = process.argv[2];
  const bloco = lerBloco();
  const lista = agentes();

  if (modo === '--aplicar') {
    let mudados = 0;
    for (const caminho of lista) {
      if (aplicarEm(caminho, bloco)) {
        mudados++;
        console.log(`  atualizado ${path.basename(caminho)}`);
      }
    }
    console.log(`ok: ${mudados} de ${lista.length} agente(s) atualizado(s)`);
    return 0;
  }

  if (modo === '--conferir') {
    const divergentes = [];
    for (const caminho of lista) {
      const atual = extrairBloco(fs.readFileSync(caminho, 'utf8'));
      if (atual === null) divergentes.push(`${path.basename(caminho)} (sem bloco)`);
      else if (atual !== bloco) divergentes.push(`${path.basename(caminho)} (bloco diferente da fonte)`);
    }
    if (divergentes.length === 0) {
      console.log(`ok: os ${lista.length} agentes carregam o bloco da fonte`);
      return 0;
    }
    console.error('DIVERGENTE:');
    for (const d of divergentes) console.error(`  ${d}`);
    console.error('rode: node scripts/perfil.cjs --aplicar');
    return 1;
  }

  console.error('uso: node scripts/perfil.cjs --aplicar | --conferir');
  return 2;
}

process.exit(main());
