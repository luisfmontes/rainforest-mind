// Números do jardineiro, contados do arquivo — não estimados pelo modelo.
// Existe porque haiku errou a contagem em 4 execuções seguidas com os mesmos
// dados (12, 10, 9, 11 plantadas, sendo 10 a resposta certa) e chegou a somar
// observação junto com ideia. Instrução não conserta aritmética; comando sim.
// O run-vigia.ps1 roda automaticamente qualquer vigias/dados-<vigia>.js e
// injeta a saída no prompt.
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');

const PLUGIN = path.resolve(__dirname, '..');
const { raiz: RAIZ_DADOS } = resolverRaiz({ plugin: PLUGIN });
const ARQ = RAIZ_DADOS ? path.join(RAIZ_DADOS, 'ideias.jsonl') : null;
const hoje = new Date();
const dia = (d) => Math.round((Date.UTC(hoje.getFullYear(), hoje.getMonth(), hoje.getDate())
  - Date.parse(d + 'T00:00:00Z')) / 86400000);

let linhas;
try {
  if (!ARQ) throw new Error('raiz de dados nao encontrada');
  linhas = fs.readFileSync(ARQ, 'utf8').split(/\r?\n/).filter((l) => l.trim()).map(JSON.parse);
} catch (e) {
  console.log('FALHA AO LER ' + (ARQ || 'ideias.jsonl (raiz nao resolvida)') + ': ' + e.message);
  console.log('Diga na mensagem que a apuracao falhou — nao invente numero.');
  process.exit(0);
}

const ideias = linhas.filter((o) => o.tipo !== 'observacao');
const obs = linhas.filter((o) => o.tipo === 'observacao');
const plantadas = ideias.filter((o) => o.status === 'plantada');
const emColheita = ideias.filter((o) => o.status === 'em-colheita');
const colhidasSemana = linhas.filter((o) => o.colhida_em && dia(o.colhida_em) <= 7);
const obsAbertas = obs.filter((o) => o.status === 'plantada');

// Agrupa as plantadas por idade, da mais velha para a mais nova.
const porIdade = new Map();
for (const o of plantadas) {
  const d = dia(o.plantada_em);
  if (!porIdade.has(d)) porIdade.set(d, []);
  porIdade.get(d).push(o.id);
}

console.log('IDEIAS PLANTADAS: ' + plantadas.length);
for (const d of [...porIdade.keys()].sort((a, b) => b - a)) {
  console.log('  ' + d + (d === 1 ? ' dia: ' : ' dias: ') + porIdade.get(d).join(', '));
}
console.log('IDEIAS EM COLHEITA: ' + emColheita.length +
  (emColheita.length ? ' (' + emColheita.map((o) => o.id).join(', ') + ')' : ''));
console.log('COLHIDAS NOS ULTIMOS 7 DIAS: ' + colhidasSemana.length +
  (colhidasSemana.length ? ' (' + colhidasSemana.map((o) => o.id).join(', ') + ')' : ''));
console.log('OBSERVACOES ABERTAS: ' + obsAbertas.length +
  (obsAbertas.length ? ' (' + obsAbertas.map((o) => o.id).join(', ') + ')' : ''));
