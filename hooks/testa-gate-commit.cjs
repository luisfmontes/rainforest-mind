/* Bateria da trava de COMMIT do gate de publicacao — Issue #165.
 *
 * O QUE ELA PROVA, e por que nao bastava a bateria irma. O
 * `testa-gate-publicacao-destino.sh` cobre `Write`, `Edit` e `MultiEdit`, ou
 * seja, a FERRAMENTA. Em 2026-09-02 o mesmo conteudo sensivel entrou no
 * repositorio sem o gate ver, escrito por um `fs.writeFileSync` dentro de um
 * script node invocado pelo Bash: nenhum evento de `Write` foi emitido, nenhum
 * `PreToolUse` disparou. `sed -i`, heredoc e `python - <<PY` tem o mesmo caminho
 * livre — e escrita por script e justamente a que se usa em mudanca de lote,
 * que e onde o volume passa sem ninguem ler linha a linha.
 *
 * Esta bateria monta um repositorio git DE VERDADE numa caixa, escreve o
 * arquivo pelo caminho que o gate de escrita nao ve, e dispara o payload de
 * `PreToolUse` do `git commit`. Ela nao le codigo e nao confia em relato: o
 * veredito e o exit code do hook real.
 *
 * POR QUE EM NODE, E NAO EM BASH. A Issue #158 mediu que o
 * `testa-gate-publicacao-destino.sh` reporta "4 ok" sobre 8 casos que ninguem
 * exerceu: ele monta o payload com `jq`, e numa maquina sem `jq` o payload sai
 * VAZIO — o hook recebe lixo, sai 0, e a bateria le esse 0 como aprovacao. Uma
 * bateria que passa mais alto quando a ferramenta some e o pior instrumento
 * possivel. Aqui o payload e `JSON.stringify`, que nao tem como faltar.
 *
 * NENHUM DADO SENSIVEL LITERAL NESTE ARQUIVO, e sem o marcador
 * `dados-de-exemplo`: o marcador dispensa o arquivo INTEIRO da conferencia, e
 * uma bateria isenta e um lugar confortavel para um vazamento de verdade
 * dormir. As formas sao montadas por concatenacao em tempo de execucao.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const SRC = path.join(__dirname, '..');
const HOOK = path.join(SRC, 'hooks', 'gate-publicacao-destino.cjs');

// Montados, nunca escritos: o gate barraria este proprio arquivo, e estaria
// certo — ele nao tem como saber que `.invalid` e TLD reservada (RFC 2606).
const SEG = 'Us' + 'ers';
const EMAIL_CI = 'ci@' + 'rainforest.invalid';
const sujo = (nome) => `caminho: /c/${SEG}/${nome}/.claude\n`;
const LIMPO = 'conteudo sem nada sensivel' + String.fromCharCode(10);

let ok = 0;
let falhou = 0;
const caso = (nome, condicao, detalhe) => {
  if (condicao) { ok++; console.log(`  ok    ${nome}`); }
  else { falhou++; console.log(`  FALHA ${nome}${detalhe ? ` (${detalhe})` : ''}`); }
};

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), 'gate-commit-'));
const git = (...a) => {
  try { return execFileSync('git', ['-C', caixa, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch { return null; }
};

git('init', '-q');
git('config', 'user.email', EMAIL_CI);
git('config', 'user.name', 'Teste');
fs.writeFileSync(path.join(caixa, 'README.md'), 'base\n');
git('add', 'README.md');
git('commit', '-qm', 'base');

/** Dispara o hook real com o payload de PreToolUse de um comando Bash. */
function dispara(cmd) {
  const payload = JSON.stringify({
    cwd: caixa,
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: { command: cmd },
  });
  const r = spawnSync(process.execPath, [HOOK], { input: payload, encoding: 'utf8' });
  return { exit: r.status, err: r.stderr || '' };
}

console.log('== 1. o caso da Issue #165: escrito por script, barrado no commit ==');
fs.writeFileSync(path.join(caixa, 'vaza.md'), sujo('Fulaninho'));
git('add', 'vaza.md');
{
  const r = dispara('git commit -m "x"');
  caso('arquivo escrito FORA do Write, staged, barra o commit', r.exit === 2, `exit=${r.exit}`);
  caso('e a mensagem diz por que o gate de escrita nao viu', /Issue #165/.test(r.err), r.err.slice(0, 120));
  caso('e nomeia o arquivo', /vaza\.md/.test(r.err), r.err.slice(0, 120));
}

console.log('\n== 2. a distincao indice-vs-worktree, que nao e preciosismo ==');
// `git commit` leva o INDICE; `git commit -a` leva o WORKTREE. Conferir o disco
// num commit normal aprovaria (ou reprovaria) conteudo que nao vai ser gravado.
git('reset', '-q');
caso('o mesmo arquivo NAO staged deixa o commit passar', dispara('git commit -m "x"').exit === 0);

git('add', 'vaza.md');
git('commit', '-qm', 'entra sujo');  // entra por fora do hook, de proposito
fs.writeFileSync(path.join(caixa, 'vaza.md'), sujo('Beltrano'));
caso('rastreado e modificado no worktree, com -am, barra', dispara('git commit -am "x"').exit === 2);
caso('e sem -a o mesmo estado passa (o indice esta limpo)', dispara('git commit -m "x"').exit === 0);
git('checkout', '-q', '--', 'vaza.md');

// Os dois casos que SEPARAM indice de worktree. Sem eles a distincao passa
// despercebida: a catraca de mutacao trocou `git show :<arquivo>` por leitura
// do disco e a bateria continuou VERDE, porque nenhum caso tinha os dois
// estados divergentes ao mesmo tempo.
fs.writeFileSync(path.join(caixa, 'divergente.md'), LIMPO);
git('add', 'divergente.md');
fs.writeFileSync(path.join(caixa, 'divergente.md'), sujo('Fulaninho'));
caso('indice LIMPO e worktree sujo: o commit passa (e o indice que vai)',
  dispara('git commit -m "x"').exit === 0);
caso('e o MESMO estado com -a barra, porque -a leva o worktree',
  dispara('git commit -am "x"').exit === 2);

fs.writeFileSync(path.join(caixa, 'divergente.md'), sujo('Beltrano'));
git('add', 'divergente.md');
fs.writeFileSync(path.join(caixa, 'divergente.md'), LIMPO);
caso('indice SUJO e worktree limpo: o commit BARRA (o disco mente)',
  dispara('git commit -m "x"').exit === 2);
git('reset', '-q');
fs.rmSync(path.join(caixa, 'divergente.md'));

console.log('\n== 3. as isencoes sao as MESMAS do gate de escrita ==');
// Uma trava contradizendo a outra ensina a desligar as duas.
fs.writeFileSync(path.join(caixa, '.gitignore'), 'segredo.md\n');
fs.writeFileSync(path.join(caixa, 'segredo.md'), sujo('Fulaninho'));
git('add', '.gitignore');
caso('arquivo gitignorado nao barra', dispara('git commit -m "x"').exit === 0);

fs.writeFileSync(path.join(caixa, 'fixture.sh'),
  `# rainforest-gate: dados-de-exemplo\n${sujo('Fulaninho')}`);
git('add', 'fixture.sh');
caso('marcador dados-de-exemplo dispensa a conferencia', dispara('git commit -m "x"').exit === 0);

console.log('\n== 4. o que NAO e commit nao vira conferencia ==');
git('reset', '-q');
// O conteudo sujo tem de estar REALMENTE staged, senao os tres casos abaixo
// passariam com o gate DESLIGADO: indice vazio nao barra nada. A primeira
// versao desta secao dava `git add` num arquivo sem modificacao e provava
// zero — quem denunciou foi a secao 6, que espera exit 2 e reprovou.
fs.writeFileSync(path.join(caixa, 'vaza2.md'), sujo('Sicrano'));
git('add', 'vaza2.md');
caso('o fixture esta mesmo staged (senao a secao nao prova nada)',
  (git('diff', '--cached', '--name-only') || '').includes('vaza2.md'));
caso('git status nao dispara', dispara('git status').exit === 0);
caso('a palavra "commit" em prosa nao dispara', dispara('echo "vou fazer o commit"').exit === 0);
caso('git commit-tree nao e git commit', dispara('git commit-tree abc').exit === 0);
caso('git -C <dir> commit dispara', dispara(`git -C ${caixa} commit -m "x"`).exit === 2);

console.log('\n== 5. o caminho limpo continua passando ==');
git('reset', '-q');
fs.rmSync(path.join(caixa, 'vaza2.md'));
fs.writeFileSync(path.join(caixa, 'limpo.md'), 'nada sensivel aqui\n');
git('add', 'limpo.md');
caso('commit de arquivo limpo passa', dispara('git commit -m "x"').exit === 0);

console.log('\n== 6. o desligamento explicito continua valendo ==');
// Sem isto, quem precisa da excecao aprende a nao usar o gate em vez de usar a
// porta que existe para ela.
fs.writeFileSync(path.join(caixa, 'vaza3.md'), sujo('Fulaninho'));
git('add', 'vaza3.md');
fs.writeFileSync(path.join(caixa, '.rainforest-gate-off'), '');
caso('.rainforest-gate-off na raiz desliga', dispara('git commit -m "x"').exit === 0);
fs.rmSync(path.join(caixa, '.rainforest-gate-off'));
caso('e removido, a trava volta', dispara('git commit -m "x"').exit === 2);

fs.rmSync(caixa, { recursive: true, force: true });

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou > 0 ? 1 : 0);
