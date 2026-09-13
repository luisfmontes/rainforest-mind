#!/usr/bin/env node
/**
 * Bateria do `conferir-cobertura-fixtures.cjs`.
 *
 * O script sob teste MUTA FONTE em disco, então as duas provas que mais importam
 * não são sobre o relatório: ele precisa RESTAURAR o arquivo em todo caminho de
 * saída, e precisa REPROVAR quando a mutação não casa o alvo. As duas já
 * falharam neste acervo — a segunda três vezes nesta mesma sessão, com
 * contrabarra comida pelo harness de quoting.
 *
 * Trabalha num sandbox de arquivos próprios, nunca no fonte do plugin.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const SCRIPT = path.resolve(__dirname, 'conferir-cobertura-fixtures.cjs');
let ok = 0;
let falhou = 0;

function caso(nome, condicao, detalhe) {
  if (condicao) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe !== undefined ? ` — ${detalhe}` : ''}`);
  }
}

/** Monta um sandbox: um módulo com duas regras e fixtures que as exercitam. */
function sandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cob-'));
  fs.mkdirSync(path.join(dir, 'fx'));
  fs.writeFileSync(path.join(dir, 'alvo.cjs'), [
    'const fs = require("fs");',
    'function decide(p) {',
    '  const t = fs.readFileSync(p, "utf8").trim();',
    '  if (t.includes("NAO")) return false;',
    '  if (t.endsWith("?")) return false;',
    '  return t.includes("SIM");',
    '}',
    'module.exports = { decide };',
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(dir, 'fx', 'concede.txt'), 'SIM');
  fs.writeFileSync(path.join(dir, 'fx', 'nega.txt'), 'NAO SIM');
  fs.writeFileSync(path.join(dir, 'fx', 'pergunta.txt'), 'SIM?');
  fs.writeFileSync(path.join(dir, 'fx', 'muda.txt'), 'nada aqui');
  return dir;
}

function escreverSpec(dir, mutacoes, mudas) {
  const spec = {
    arquivo: 'alvo.cjs',
    fixtures: 'fx',
    avaliar: 'alvo.cjs#decide',
    mutacoes,
    mudas_esperadas: mudas || [],
  };
  const p = path.join(dir, 'spec.json');
  fs.writeFileSync(p, JSON.stringify(spec, null, 2));
  return p;
}

function rodar(dir, spec) {
  return spawnSync(process.execPath, [SCRIPT, '--mutacoes', spec, '--raiz', dir], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  });
}

const MUT_NEGACAO = { nome: 'negacao desligada', alvo: 'includes("NAO")', linha: '  if (false) return false;' };
const MUT_PERGUNTA = { nome: 'pergunta desligada', alvo: 'endsWith("?")', linha: '  if (false) return false;' };

console.log('== 1. caminho feliz: toda fixture viva e exercitada, muda declarada ==');
{
  const dir = sandbox();
  const antes = fs.readFileSync(path.join(dir, 'alvo.cjs'), 'utf8');
  const spec = escreverSpec(dir, [MUT_NEGACAO, MUT_PERGUNTA], [
    { fixture: 'muda.txt', motivo: 'nao contem SIM; false por ausencia, nao por regra' },
    { fixture: 'concede.txt', motivo: 'concessao limpa; nenhuma das duas regras a toca' },
  ]);
  const r = rodar(dir, spec);
  caso('exit 0', r.status === 0, `${r.status} — ${r.stdout}${r.stderr}`);
  caso('diz "cobertura por fixture: OK"', /cobertura por fixture: OK/.test(r.stdout), r.stdout);
  caso('FONTE RESTAURADO no caminho feliz', fs.readFileSync(path.join(dir, 'alvo.cjs'), 'utf8') === antes);
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('== 2. fixture muda NAO declarada reprova ==');
{
  const dir = sandbox();
  const spec = escreverSpec(dir, [MUT_NEGACAO, MUT_PERGUNTA], []);
  const r = rodar(dir, spec);
  caso('exit 1', r.status === 1, r.status);
  caso('nomeia a fixture muda', /muda\.txt/.test(r.stdout), r.stdout);
  caso('nao diz OK', !/cobertura por fixture: OK/.test(r.stdout));
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('== 3. MUTACAO QUE NAO CASA O ALVO reprova (o no-op silencioso) ==');
{
  const dir = sandbox();
  const antes = fs.readFileSync(path.join(dir, 'alvo.cjs'), 'utf8');
  const spec = escreverSpec(dir, [
    { nome: 'alvo inexistente', alvo: 'padrao-que-nao-existe-em-lugar-nenhum', linha: '  // nada' },
  ], []);
  const r = rodar(dir, spec);
  caso('exit 1', r.status === 1, r.status);
  caso('imprime MUTACAO NAO APLICADA', /MUTACAO NAO APLICADA/.test(r.stdout), r.stdout);
  caso('FONTE RESTAURADO mesmo com alvo errado', fs.readFileSync(path.join(dir, 'alvo.cjs'), 'utf8') === antes);
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('== 4. MUTACAO QUE NAO MUDA A LINHA reprova ==');
{
  const dir = sandbox();
  const spec = escreverSpec(dir, [
    { nome: 'substituicao inerte', alvo: 'includes("NAO")', de: 'nao-existe-nesta-linha', para: 'idem' },
  ], []);
  const r = rodar(dir, spec);
  caso('exit 1', r.status === 1, r.status);
  caso('diz que a linha nao mudou', /a linha não mudou/.test(r.stdout), r.stdout);
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('== 5. lista de mudas que apodreceu reprova ==');
{
  const dir = sandbox();
  const spec = escreverSpec(dir, [MUT_NEGACAO, MUT_PERGUNTA], [
    { fixture: 'muda.txt', motivo: 'ok' },
    { fixture: 'concede.txt', motivo: 'ok' },
    { fixture: 'nega.txt', motivo: 'ERRADO: esta e exercitada pelo mutante da negacao' },
  ]);
  const r = rodar(dir, spec);
  caso('exit 1', r.status === 1, r.status);
  caso('acusa DECLARADAS MUDAS, MAS EXERCITADAS', /DECLARADAS MUDAS, MAS EXERCITADAS/.test(r.stdout), r.stdout);
  caso('nomeia nega.txt', /nega\.txt/.test(r.stdout));
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('== 6. muda declarada que nao existe mais reprova ==');
{
  const dir = sandbox();
  const spec = escreverSpec(dir, [MUT_NEGACAO, MUT_PERGUNTA], [
    { fixture: 'muda.txt', motivo: 'ok' },
    { fixture: 'concede.txt', motivo: 'ok' },
    { fixture: 'apagada-faz-tempo.txt', motivo: 'nao existe mais' },
  ]);
  const r = rodar(dir, spec);
  caso('exit 1', r.status === 1, r.status);
  caso('acusa DECLARADAS MUDAS, MAS NAO EXISTEM MAIS', /NAO EXISTEM MAIS/.test(r.stdout), r.stdout);
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('== 7. mutante GROSSO nao conta para cobertura especifica ==');
{
  // Um mutante que zera tudo vira o veredito de mais de um terco das fixtures.
  // Se ele contasse, `muda.txt` pareceria coberta e o caso 2 nunca reprovaria.
  const dir = sandbox();
  const spec = escreverSpec(dir, [
    { nome: 'decide sempre true, logo na entrada', alvo: 'includes("NAO")', linha: '  return true;' },
  ], []);
  const r = rodar(dir, spec);
  caso('marca o mutante como GROSSO', /GROSSO/.test(r.stdout), r.stdout);
  caso('ainda reprova, porque nenhuma fixture ficou coberta', r.status === 1, r.status);
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('== 8. fonte limpo que nao avalia para com exit 2, sem deixar lixo ==');
{
  const dir = sandbox();
  fs.writeFileSync(path.join(dir, 'alvo.cjs'), 'isto nao e javascript valido (((');
  const antes = fs.readFileSync(path.join(dir, 'alvo.cjs'), 'utf8');
  const spec = escreverSpec(dir, [MUT_NEGACAO], []);
  const r = rodar(dir, spec);
  caso('exit 2', r.status === 2, r.status);
  caso('FONTE RESTAURADO', fs.readFileSync(path.join(dir, 'alvo.cjs'), 'utf8') === antes);
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou > 0) {
  console.log('BATERIA VERMELHA');
  process.exit(1);
}
console.log('todos os casos: OK');
