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
 *   node scripts/semear.cjs <slug>              # de outro, posicional
 *   node scripts/semear.cjs --projeto <slug>   # de outro, com flag
 *   node scripts/semear.cjs --json
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const CODIGO_ROOT = path.resolve(__dirname, '..');
const PROJETO_DIR = process.env.CLAUDE_PROJECT_DIR || process.cwd();

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return i >= 0 ? process.argv[i + 1] : null;
}

/** Primeiro argumento posicional (nao-flag) — o slug passado sem `--projeto`. */
function argPosicional() {
  const posicionais = process.argv.slice(2).filter((a, i, arr) => {
    if (a.startsWith('--')) return false;
    if (i > 0 && arr[i - 1].startsWith('--')) return false; // valor de uma flag
    return true;
  });
  return posicionais[0] || null;
}

/**
 * Worktree linkado (regra 11) e exatamente onde o metodo manda o trabalho
 * acontecer — e e exatamente onde `path.basename(cwd)` erra o projeto: o nome
 * do worktree (`.claude/worktrees/regua`) nao e o slug do repositorio
 * (`rainforest-mind`). `git rev-parse --git-common-dir` aponta pro `.git` do
 * repositorio PRINCIPAL mesmo de dentro do worktree; dono do commit
 * `semear-deriva-projeto-do-cwd-e-quebra-em-worktree` (2026-08-21).
 *
 * Fora de um repositorio git, ou em repo comum (sem worktree), cai no proprio
 * PROJETO_DIR sem diferenca de comportamento.
 */
function raizProjetoGit(dir) {
  try {
    const saida = execFileSync('git', ['rev-parse', '--git-common-dir'], {
      cwd: dir,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).toString().trim();
    if (!saida) return dir;
    const comum = path.isAbsolute(saida) ? saida : path.resolve(dir, saida);
    return path.basename(comum) === '.git' ? path.dirname(comum) : dir;
  } catch {
    return dir;
  }
}

function raizDados() {
  try {
    return require('../hooks/lib/raiz.cjs').resolverRaiz({ plugin: CODIGO_ROOT }).raiz;
  } catch {
    return null;
  }
}

/**
 * O `projeto` virou slug de vocabulário fechado em 2026-08-12 (o campo era texto
 * livre, guardava caminho do Windows dentro de string JSON e a barra + `r` comeu
 * o caminho de 4 registros). O vocabulário mora no `projetos.json` da pasta de
 * dados, e é ele que traduz PASTA em slug: um projeto cujo diretório não se chama
 * como o slug (`...\protheus-totvs-agro\inovacao` → `protheus-inovacao`) só se
 * resolve por esse mapa.
 *
 * A comparação difusa continua existindo, e só como REDE: registro que ainda não
 * passou pela migração, ou alvo que não está no vocabulário. Quando os dois lados
 * são slug, a comparação é igualdade — que é o ponto da mudança.
 */
function lerVocabulario(raiz) {
  if (!raiz) return null;
  try {
    const m = JSON.parse(fs.readFileSync(path.join(raiz, 'projetos.json'), 'utf8'));
    return m && typeof m === 'object' && !Array.isArray(m) ? m : null;
  } catch {
    return null;
  }
}

/** Slug do alvo pedido: nome do slug, apelido dele, ou pasta registrada. */
function slugDoAlvo(alvo, vocab, dir) {
  if (!vocab) return null;
  if (Object.prototype.hasOwnProperty.call(vocab, alvo)) return alvo;
  const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-');
  const alvoNorm = norm(alvo);
  const dirNorm = dir ? path.resolve(dir).toLowerCase() : null;
  for (const [slug, v] of Object.entries(vocab)) {
    const apelidos = Array.isArray(v && v.apelidos) ? v.apelidos : [];
    if ([slug, ...apelidos].some((t) => norm(t) === alvoNorm)) return slug;
    if (dirNorm && v && v.caminho && path.resolve(v.caminho).toLowerCase() === dirNorm) return slug;
  }
  return null;
}

function combina(valorDoRegistro, alvo) {
  const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-');
  const a = norm(valorDoRegistro);
  const b = norm(alvo);
  return a.includes(b) || b.includes(a.split('-c-')[0]);
}

function main() {
  // Slug explicito (flag ou posicional) vence o cwd. Sem ele, o padrao nao e
  // mais `path.basename(PROJETO_DIR)` puro: PROJETO_DIR pode ser um worktree
  // linkado (`.claude/worktrees/<nome>`), e o nome do worktree nao e o slug do
  // repositorio. `raizProjetoGit` sobe ate o repositorio principal via
  // `git rev-parse --git-common-dir` antes de tirar o basename.
  const slugExplicito = arg('projeto') || argPosicional();
  const projetoRaiz = raizProjetoGit(PROJETO_DIR);
  const alvo = slugExplicito || path.basename(projetoRaiz);
  const raiz = raizDados();
  const saida = {
    projeto: alvo, observacoes: [], totalObservacoes: 0, abertas: [], totalAbertas: 0,
    relatorios: [], mapas: [], avisos: [],
  };

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
    const vocab = lerVocabulario(raiz);
    // O casamento por diretorio registrado (`v.caminho`) so vale para o alvo
    // IMPLICITO (derivado do cwd/worktree) — e' o que resolve, por exemplo, um
    // projeto cujo diretorio nao se chama como o slug. Quando o pedido e
    // EXPLICITO (flag ou posicional), casar por diretorio ignoraria o que foi
    // digitado e devolveria outro projeto qualquer so por coincidir o cwd —
    // e um slug explicito errado tem que RECUSAR, nao ser substituido em silencio.
    const slug = slugDoAlvo(alvo, vocab, slugExplicito ? null : projetoRaiz);

    // Na duvida, RECUSA — so quando o pedido foi EXPLICITO (flag ou posicional)
    // e existe vocabulario para consultar. Slug desconhecido devolvendo acervo
    // vazio com exit 0 e o modo de falha que este repo nao aceita: parece
    // resposta legitima sem ser. Projeto novo/nao registrado SEM pedido
    // explicito continua no fluxo normal (bloco "SEM HISTORICO" mais abaixo) —
    // e o caso de quem acabou de instalar, nao uma duvida.
    if (vocab && slugExplicito && !slug) {
      console.error(`RECUSADO: '${slugExplicito}' nao esta no projetos.json.`);
      console.error(
        `registre: node scripts/ideias.cjs projetos --registrar <slug> --caminho "<caminho-do-projeto>"`
      );
      console.error('ou rode sem slug para usar o projeto do diretorio atual.');
      process.exit(1);
    }

    if (slug && slug !== alvo) saida.projeto = `${slug} (pedido como '${alvo}')`;
    const doProjeto = slug
      ? linhas.filter((o) => o.projeto === slug || combina(o.projeto, slug))
      : linhas.filter((o) => combina(o.projeto, alvo));
    if (vocab && !slug) {
      saida.avisos.push(
        `'${alvo}' nao esta no projetos.json — comparacao difusa, pode trazer de outro projeto. ` +
          `registre: node scripts/ideias.cjs projetos --registrar <slug> --caminho "${projetoRaiz}"`
      );
    }

    // OBSERVAÇÃO é o registro de quando o usuario teve de corrigir a saída (regra 13).
    // É a fonte mais densa que existe aqui: cada linha é um defeito que já
    // aconteceu neste projeto, com o `ao_colher` dizendo o que fazer a respeito.
    // Contagem em "N de M" (CONTRIBUTING: contagem diz de qual conjunto saiu) —
    // M e o total de observacoes no acervo inteiro, de todos os projetos.
    saida.totalObservacoes = linhas.filter((o) => o.tipo === 'observacao').length;
    saida.observacoes = doProjeto
      .filter((o) => o.tipo === 'observacao')
      .map((o) => ({ id: o.id, titulo: o.titulo, status: o.status, ao_colher: o.ao_colher || '' }));

    // Ideia ABERTA já é uma proposta que alguém fez e ninguém executou. Propor de
    // novo o que já está plantado é ruído, e o pior tipo: parece trabalho novo.
    saida.totalAbertas = linhas
      .filter((o) => o.status === 'plantada' || o.status === 'em-colheita')
      .filter((o) => o.tipo !== 'observacao').length;
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
  console.log(`OBSERVACOES (${saida.observacoes.length} de ${saida.totalObservacoes}) — o que ja deu errado aqui`);
  if (!saida.observacoes.length) console.log('  (nenhuma)');
  for (const o of saida.observacoes) {
    console.log(`  [${o.status}] ${o.id}`);
    console.log(`     ${o.titulo}`);
  }

  console.log('');
  console.log(`IDEIAS ABERTAS (${saida.abertas.length} de ${saida.totalAbertas}) — ja propostas, nao repropor`);
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
