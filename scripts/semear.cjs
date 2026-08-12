#!/usr/bin/env node
/**
 * Semear — colhe o material de que a skill `semear` precisa para propor.
 *
 * A skill propõe o que criar NESTE projeto. A pergunta "o que costuma valer a pena
 * num projeto assim" já tem dono oficial e melhor: a skill
 * `claude-automation-recommender`, do plugin `claude-code-setup` da Anthropic, que
 * lê o código — package.json, framework, banco, testes — e recomenda hooks, MCP e
 * subagentes. Não duplicamos isso.
 *
 * O que ela tem e o oficial não: **o histórico do que este trabalho já tropeçou.**
 * As observações da regra 13, os relatórios de incidente, os avanços datados. O
 * oficial olha o repo e diz "tem Prisma, instale o MCP de banco". Aqui dá para
 * olhar o mesmo repo e a observação de que uma entrega foi recusada três vezes
 * pela mesma família de defeito, e propor a trava que impede aquela família. Um
 * recomenda pelo que o projeto **é**; o outro pelo que ele **sofreu**.
 *
 * Este script não propõe nada — ele só junta o material e o entrega compacto. A
 * proposta é julgamento, e julgamento fica na janela. Sem o digest, a skill leria
 * 78 ideias e 15 relatórios inteiros para achar meia dúzia de linhas úteis.
 *
 * Uso:
 *   node scripts/semear.cjs                    # do projeto atual
 *   node scripts/semear.cjs --projeto <slug>   # de outro
 *   node scripts/semear.cjs --json
 */

const fs = require('fs');
const path = require('path');

const CODIGO_ROOT = path.resolve(__dirname, '..');
const PROJETO_DIR = process.env.CLAUDE_PROJECT_DIR || process.cwd();

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return i >= 0 ? process.argv[i + 1] : null;
}

function raizDados() {
  try {
    return require('../hooks/lib/raiz.cjs').resolverRaiz({ plugin: CODIGO_ROOT }).raiz;
  } catch {
    return null;
  }
}

/**
 * O campo `projeto` é texto livre e tem 20 valores distintos para ~6 projetos
 * reais — `rainforest-mind` aparece escrito de quatro jeitos, alguns com caminho
 * do Windows dentro. Comparar por igualdade perderia dois terços do histórico,
 * então a comparação é por raiz do nome. (A correção de fundo — slug de
 * vocabulário fechado — está plantada em `projeto-vira-slug-e-caminho-sai-do-dado`.)
 */
function combina(valorDoRegistro, alvo) {
  const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-');
  const a = norm(valorDoRegistro);
  const b = norm(alvo);
  return a.includes(b) || b.includes(a.split('-c-')[0]);
}

function main() {
  const alvo = arg('projeto') || path.basename(PROJETO_DIR);
  const raiz = raizDados();
  const saida = { projeto: alvo, observacoes: [], abertas: [], relatorios: [], mapas: [], avisos: [] };

  if (!raiz) {
    saida.avisos.push('sem pasta de dados — rode: node scripts/setup.cjs --criar');
  } else {
    const jsonl = path.join(raiz, 'ideias.jsonl');
    let linhas = [];
    try {
      linhas = fs.readFileSync(jsonl, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
    } catch {
      saida.avisos.push(`nao consegui ler ${jsonl}`);
    }
    const doProjeto = linhas.filter((o) => combina(o.projeto, alvo));

    // OBSERVAÇÃO é o registro de quando o usuario teve de corrigir a saída (regra 13).
    // É a fonte mais densa que existe aqui: cada linha é um defeito que já
    // aconteceu neste projeto, com o `ao_colher` dizendo o que fazer a respeito.
    saida.observacoes = doProjeto
      .filter((o) => o.tipo === 'observacao')
      .map((o) => ({ id: o.id, titulo: o.titulo, status: o.status, ao_colher: o.ao_colher || '' }));

    // Ideia ABERTA já é uma proposta que alguém fez e ninguém executou. Propor de
    // novo o que já está plantado é ruído, e o pior tipo: parece trabalho novo.
    saida.abertas = doProjeto
      .filter((o) => o.status === 'plantada' || o.status === 'em-colheita')
      .filter((o) => o.tipo !== 'observacao')
      .map((o) => ({ id: o.id, titulo: o.titulo, gancho: o.gancho || null }));
  }

  // Relatório é incidente com método e números. O TÍTULO já carrega a lição — foi
  // escrito para isso — então o digest leva só ele e o caminho; quem precisar do
  // corpo abre o arquivo.
  // SO DO PROJETO, sem fallback. A primeira versao caia na pasta do plugin quando o
  // projeto nao tinha `relatorios/` — e ai um repo recem-instalado recebia os 14
  // incidentes do rainforest como se fossem a historia dele. Isso quebra a regra que
  // sustenta a skill: proposta cita o registro que a origina, e citar incidente de
  // outro projeto e proposta que PARECE fundamentada sem estar. Mesma familia do foco
  // caindo na pasta do plugin, corrigida no mesmo dia.
  const dirRel = path.join(PROJETO_DIR, 'relatorios');
  if (fs.existsSync(dirRel)) {
    for (const f of fs.readdirSync(dirRel).filter((x) => x.endsWith('.md')).sort()) {
      const arq = path.join(dirRel, f);
      let titulo = f;
      try {
        const primeira = fs.readFileSync(arq, 'utf8').split('\n').find((l) => l.startsWith('# '));
        if (primeira) titulo = primeira.replace(/^#\s*/, '').trim();
      } catch { /* fica o nome do arquivo */ }
      saida.relatorios.push({ arquivo: path.relative(PROJETO_DIR, arq), titulo });
    }
  }

  // O MAPA da arqueologia, quando existe. Semear le o HISTORICO (o que este trabalho
  // tropecou); arqueologia le o TERRENO (o que ja esta la e ninguem daqui escreveu).
  // Uma nao dispara a outra — arqueologia custa uma sessao e e escopada a uma
  // demanda —, mas mapa ja escrito e evidencia barata e entra no digest.
  const cobertura = path.join(PROJETO_DIR, 'docs', 'rainforest', 'mapas', 'COBERTURA.md');
  if (fs.existsSync(cobertura)) {
    try {
      saida.mapas = fs.readFileSync(cobertura, 'utf8').split('\n')
        .filter((l) => l.trim().startsWith('|'))
        .filter((l) => !/^\s*\|[\s|:-]*$/.test(l))
        .slice(1, 12);
    } catch { /* sem mapa legivel */ }
  }

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(saida, null, 2));
    return;
  }

  console.log(`MATERIAL PARA SEMEAR — projeto: ${saida.projeto}`);
  for (const a of saida.avisos) console.log(`  aviso: ${a}`);

  console.log('');
  console.log(`OBSERVACOES (${saida.observacoes.length}) — o que ja deu errado aqui`);
  if (!saida.observacoes.length) console.log('  (nenhuma)');
  for (const o of saida.observacoes) {
    console.log(`  [${o.status}] ${o.id}`);
    console.log(`     ${o.titulo}`);
  }

  console.log('');
  console.log(`IDEIAS ABERTAS (${saida.abertas.length}) — ja propostas, nao repropor`);
  if (!saida.abertas.length) console.log('  (nenhuma)');
  for (const o of saida.abertas) console.log(`  ${o.id} — ${o.titulo}`);

  console.log('');
  console.log(`RELATORIOS (${saida.relatorios.length}) — incidentes com metodo e numeros`);
  if (!saida.relatorios.length) console.log('  (nenhum)');
  for (const r of saida.relatorios) console.log(`  ${r.titulo}\n     ${r.arquivo}`);

  if (saida.mapas.length) {
    console.log('');
    console.log(`MAPAS DE LEGADO (${saida.mapas.length}) — terreno ja levantado`);
    for (const m of saida.mapas) console.log(`  ${m.trim()}`);
  }

  // Historico vazio e o caso de QUEM ACABOU DE INSTALAR, nao uma anomalia. Devolver
  // tres blocos vazios e honesto e inutil: a skill precisa dizer o que fazer a
  // respeito, senao o primeiro uso dela ensina que ela nao serve.
  const nada = !saida.observacoes.length && !saida.abertas.length
    && !saida.relatorios.length && !saida.mapas.length;
  if (nada) {
    console.log('');
    console.log('SEM HISTORICO NESTE PROJETO — nao ha o que semear a partir dele.');
    console.log('E normal em projeto novo ou recem-instalado. Tres caminhos:');
    console.log('  - o historico nasce sozinho: observacao da regra 13 e relatorio de');
    console.log('    incidente aparecem conforme o trabalho anda. Volte depois;');
    console.log('  - ha legado que ninguem daqui escreveu? `Skill(arqueologia)` levanta');
    console.log('    o TERRENO, que e a outra fonte — e o mapa dela entra aqui;');
    console.log('  - o que criar por STACK tem dono oficial: a skill');
    console.log('    `claude-automation-recommender` (plugin claude-code-setup).');
    return;
  }

  console.log('');
  console.log('O que criar por STACK (framework, banco, testes) e outra pergunta, e');
  console.log('tem dono oficial: skill `claude-automation-recommender`.');
}

if (require.main === module) main();
module.exports = { combina };
