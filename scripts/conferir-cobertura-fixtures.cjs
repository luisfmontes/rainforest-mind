#!/usr/bin/env node
/**
 * Catraca de cobertura por FIXTURE: para cada fixture, existe ao menos um
 * mutante que vira o veredito DELA?
 *
 * POR QUE EXISTE, com data e medição. O `conferir-mutacao.cjs` pergunta se a
 * bateria fica vermelha quando o comportamento é invertido, e isso é necessário
 * mas não suficiente: o exit code de uma bateria é AGREGADO. Uma fixture pode
 * nunca mudar de veredito sob mutante nenhum e ainda assim parecer coberta,
 * porque OUTRA asserção quebra no mesmo run e pinta tudo de vermelho.
 *
 * Medido em 2026-09-12, na 5ª rodada de revisão do leitor de autorização:
 *
 *   - 3 das 6 fixtures novas de um commit passavam verdes contra TODOS os 11
 *     mutantes, isoladas. A catraca agregada dizia 11/11 vermelhas.
 *   - Com a pergunta feita por fixture, apareceram duas lacunas reais no
 *     conjunto de mutantes: nenhum revertia a regra da cauda para a regra
 *     ampla, e nenhum tirava os possessivos da lista de determinantes.
 *   - E apareceu uma fixture MAL ESCRITA: a que devia exercitar o possessivo
 *     tinha a concessão na 1ª frase, que concedia sozinha — o possessivo nunca
 *     era consultado. Isso não dá para ver lendo o teste; só medindo.
 *
 * A saída é um CONTRATO, não um relatório: o arquivo de mutações declara quais
 * fixtures são mudas por desenho (guarda de regressão de defeito estrutural, ou
 * de regra que foi REMOVIDA). Fixture muda fora dessa lista reprova; fixture da
 * lista que passou a ser exercitada TAMBÉM reprova, porque a lista apodreceu.
 *
 * A GUARDA DO PADRÃO QUE NÃO CASA é herdada do `conferir-mutacao.cjs`, e não é
 * zelo: nesta mesma sessão, três mutações seguidas viraram no-op silencioso
 * porque o substitutor não casou o alvo (contrabarra comida pelo heredoc do
 * harness). No-op que devolve verde é veredito certo pelo motivo errado.
 *
 * O fonte é restaurado em TODO caminho de saída, inclusive erro e sinal: deixar
 * o arquivo mutado na árvore é pior que qualquer falso veredito.
 *
 * Uso:
 *   node scripts/conferir-cobertura-fixtures.cjs --mutacoes <arquivo.json> [--raiz <pasta>] [--timeout <ms>]
 *
 * Formato do arquivo de mutações:
 *   {
 *     "arquivo":  "hooks/lib/autorizacao-usuario.cjs",
 *     "fixtures": "test/fixtures/autorizacao",
 *     "avaliar":  "hooks/lib/autorizacao-usuario.cjs#autorizado",
 *     "mutacoes": [
 *       { "nome": "M1 …", "alvo": "<substring que acha a LINHA>",
 *         "de": "<substring da linha>", "para": "<substituta>" },
 *       { "nome": "M2 …", "alvo": "<substring>", "linha": "<linha inteira nova>" }
 *     ],
 *     "mudas_esperadas": [
 *       { "fixture": "x.jsonl", "motivo": "guarda de regressão de defeito estrutural" }
 *     ]
 *   }
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function uso(msg) {
  if (msg) console.error(`erro: ${msg}\n`);
  console.error('uso: node scripts/conferir-cobertura-fixtures.cjs --mutacoes <arquivo.json> [--raiz <pasta>] [--timeout <ms>]');
  process.exit(2);
}

const args = process.argv.slice(2);
const opts = {};
for (let i = 0; i < args.length; i += 2) {
  if (!args[i].startsWith('--')) uso(`argumento inesperado: ${args[i]}`);
  opts[args[i].slice(2)] = args[i + 1];
}
if (!opts.mutacoes) uso('--mutacoes é obrigatório');

const raiz = path.resolve(opts.raiz || process.cwd());
const timeout = Number(opts.timeout || 60000);

let spec;
try {
  spec = JSON.parse(fs.readFileSync(path.resolve(raiz, opts.mutacoes), 'utf8'));
} catch (e) {
  uso(`não consegui ler --mutacoes: ${e.message}`);
}
for (const campo of ['arquivo', 'fixtures', 'avaliar', 'mutacoes']) {
  if (!spec[campo]) uso(`o arquivo de mutações não tem "${campo}"`);
}

const alvoFonte = path.resolve(raiz, spec.arquivo);
const pastaFixtures = path.resolve(raiz, spec.fixtures);
const [moduloAvaliar, funcaoAvaliar] = String(spec.avaliar).split('#');
if (!funcaoAvaliar) uso('"avaliar" precisa ser "<modulo>#<funcao>"');

const original = fs.readFileSync(alvoFonte, 'utf8');
let restaurado = false;
function restaurar() {
  if (restaurado) return;
  restaurado = true;
  try { fs.writeFileSync(alvoFonte, original); } catch (_) { /* nada a fazer */ }
}
process.on('exit', restaurar);
for (const sinal of ['SIGINT', 'SIGTERM']) {
  process.on(sinal, () => { restaurar(); process.exit(130); });
}

const fixtures = fs.readdirSync(pastaFixtures).filter((f) => !f.startsWith('.')).sort();
if (fixtures.length === 0) uso(`nenhuma fixture em ${spec.fixtures}`);

/** Roda a função de avaliação contra todas as fixtures, num filho sem stdin. */
function vereditos(fonte) {
  fs.writeFileSync(alvoFonte, fonte);
  const programa = `
    const m = require(${JSON.stringify(path.resolve(raiz, moduloAvaliar))});
    const saida = {};
    for (const f of ${JSON.stringify(fixtures)}) {
      try { saida[f] = m[${JSON.stringify(funcaoAvaliar)}](${JSON.stringify(pastaFixtures)} + "/" + f); }
      catch (e) { saida[f] = "ERRO:" + e.message; }
    }
    process.stdout.write(JSON.stringify(saida));
  `;
  const r = spawnSync(process.execPath, ['-e', programa], {
    cwd: raiz, encoding: 'utf8', timeout, stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (r.status !== 0) return { erro: (r.stderr || '').trim().split('\n').slice(-3).join(' | ') || `exit ${r.status}` };
  try { return { ok: JSON.parse(r.stdout) }; } catch (e) { return { erro: `saída ilegível: ${e.message}` }; }
}

const base = vereditos(original);
if (base.erro) {
  restaurar();
  console.error(`FONTE LIMPO NÃO AVALIA: ${base.erro}`);
  process.exit(2);
}

const exercitada = new Map(); // fixture -> [mutantes que viram o veredito dela]
let problemas = 0;

for (const m of spec.mutacoes) {
  const nome = m.nome || '(sem nome)';
  const linhas = original.split('\n');
  const i = linhas.findIndex((l) => l.includes(m.alvo));
  if (i === -1) {
    console.log(`MUTACAO NAO APLICADA  ${nome} — alvo não encontrado: ${JSON.stringify(m.alvo)}`);
    problemas++;
    continue;
  }
  const nova = m.linha !== undefined ? m.linha : linhas[i].split(m.de).join(m.para);
  if (nova === linhas[i]) {
    console.log(`MUTACAO NAO APLICADA  ${nome} — a linha não mudou`);
    problemas++;
    continue;
  }
  linhas[i] = nova;

  const r = vereditos(linhas.join('\n'));
  if (r.erro) {
    console.log(`MUTANTE NAO CARREGA   ${nome} — ${r.erro}`);
    problemas++;
    continue;
  }
  const virou = fixtures.filter((f) => r.ok[f] !== base.ok[f]);

  // MUTANTE GROSSO não prova cobertura específica. Desligar a porta de entrada
  // do leitor vira o veredito de quase toda fixture de uma vez, e se isso
  // contasse, bastaria um mutante desses para o relatório dizer que está tudo
  // coberto — o oposto do que este script existe para medir. Medido em
  // 2026-09-12: com um mutante assim entrando na conta, 7 fixtures que a
  // ferramenta tinha acabado de flagrar como mudas voltaram a parecer cobertas.
  // O corte e um TERCO das fixtures: o mutante medido virava 24 de 52 (46%), e
  // um corte pela metade o deixava passar por especifico.
  const grosso = virou.length > fixtures.length / 3;
  if (!grosso) {
    for (const f of virou) {
      if (!exercitada.has(f)) exercitada.set(f, []);
      exercitada.get(f).push(nome);
    }
  }
  console.log(`${String(virou.length).padStart(3)} fixture(s)  ${nome}${grosso ? '   [GROSSO — não conta para cobertura específica]' : ''}`);
}

restaurar();
const depois = fs.readFileSync(alvoFonte, 'utf8');
if (depois !== original) {
  console.error('FONTE NAO RESTAURADO — pare e confira a árvore antes de qualquer commit.');
  process.exit(2);
}

const esperadasMudas = new Map((spec.mudas_esperadas || []).map((e) => [e.fixture, e.motivo || '(sem motivo)']));
const mudas = fixtures.filter((f) => !exercitada.has(f));

console.log(`\n${fixtures.length} fixtures, ${exercitada.size} exercitadas por algum mutante.`);

const mudasNaoDeclaradas = mudas.filter((f) => !esperadasMudas.has(f));
if (mudasNaoDeclaradas.length) {
  console.log('\nMUDAS NAO DECLARADAS (nenhum mutante muda o veredito delas):');
  for (const f of mudasNaoDeclaradas) console.log(`  ${f}`);
  console.log('  → ou falta mutante para o mecanismo que elas guardam, ou a fixture não');
  console.log('    exercita o que o comentário dela afirma. As duas já aconteceram aqui.');
  problemas += mudasNaoDeclaradas.length;
}

const declaradasQueMexem = [...esperadasMudas.keys()].filter((f) => exercitada.has(f));
if (declaradasQueMexem.length) {
  console.log('\nDECLARADAS MUDAS, MAS EXERCITADAS (a lista apodreceu):');
  for (const f of declaradasQueMexem) console.log(`  ${f} — por ${exercitada.get(f).join(', ')}`);
  problemas += declaradasQueMexem.length;
}

const declaradasQueSumiram = [...esperadasMudas.keys()].filter((f) => !fixtures.includes(f));
if (declaradasQueSumiram.length) {
  console.log('\nDECLARADAS MUDAS, MAS NAO EXISTEM MAIS:');
  for (const f of declaradasQueSumiram) console.log(`  ${f}`);
  problemas += declaradasQueSumiram.length;
}

if (problemas === 0) {
  console.log('\ncobertura por fixture: OK');
  process.exit(0);
}
console.log(`\ncobertura por fixture: ${problemas} problema(s)`);
process.exit(1);
