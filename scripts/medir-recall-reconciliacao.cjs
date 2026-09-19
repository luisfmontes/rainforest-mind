#!/usr/bin/env node
'use strict';

/**
 * Mede se o FTS5 sozinho, como buscador de candidatas para a reconciliação de
 * memória (K_CANDIDATAS=5, bm25, mesmo projeto — ver `scripts/memoria.cjs`),
 * acha a observação certa, ou se falta um índice vetorial. Decisão D4 do
 * design `docs/rainforest/design/2026-09-16-memoria-reconciliacao-e-consolidacao.md`,
 * tarefa 7 do plano `docs/rainforest/planos/2026-09-16-memoria-reconciliacao-e-consolidacao.md`.
 *
 * A ARMADILHA que este script existe para não cair: se a LLM só enxergar as
 * candidatas que o FTS5 trouxe, todo alvo escolhido está trivialmente entre
 * elas e o recall sai 100% por construção — medição que não vale nada.
 *
 * O DESENHO CORRETO: para cada observação sondada, o conjunto de candidatas
 * apresentado à LLM é MAIOR que o do FTS5 — as K_CANDIDATAS (5) que o FTS5
 * traria, MAIS as INDEPENDENTE (20) observações mais recentes do mesmo
 * `projeto`, anteriores à sondada (ver `buscarIndependentes` abaixo — é aqui
 * que as 20 entram). A união é embaralhada, sem id de banco visível (rotulada
 * 1..N), e é isso que a LLM vê. O recall é a fração das decisões
 * `update`/`merge` cujo alvo escolhido estava entre as 5 do FTS5.
 *
 * Ambiente: abre o banco real (`~/.rainforest/rainforest.db`, resolvido pelo
 * mesmo `resolverCaminhos()` de `scripts/memoria.cjs`) em modo SOMENTE
 * LEITURA (`abrirBancoSomenteLeitura`, que usa `{readOnly:true}`) — nenhuma
 * escrita acontece neste script. A chamada à LLM segue o mesmo padrão de
 * `chamarLLMParaConsolidar`/`chamarLLMParaReconciliar` em `scripts/memoria.cjs`
 * (spawn do `claude` resolvido por `scripts/lib/achar-executavel-claude.cjs`,
 * modelo `claude-haiku-4-5-20251001`). Falha de resolução do executável, ou
 * de qualquer chamada, é reportada — nunca estimada ou inventada.
 */

const path = require('path');

const {
  abrirBancoSomenteLeitura,
  resolverCaminhos,
  K_CANDIDATAS,
  buscarCandidatas,
  interpretarDecisaoReconciliacao,
} = require('./memoria.cjs');
const { acharExecutavelClaude } = require('./lib/achar-executavel-claude.cjs');

const INDEPENDENTE = 20;
const TETO_ARGUMENTO = 16000;
const TIMEOUT_MS = 60000;

function parseArgs(argv) {
  let amostra = 200;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--amostra' && argv[i + 1]) {
      amostra = Number(argv[i + 1]);
      i++;
    }
  }
  if (!Number.isFinite(amostra) || amostra <= 0) amostra = 200;
  return { amostra };
}

// As INDEPENDENTE (20) observações mais recentes do mesmo `projeto`,
// anteriores à sondada — o conjunto que NÃO vem do FTS5. É esta função que
// impede o recall de sair 100% por construção (ver cabeçalho do arquivo).
function buscarIndependentes(conexao, obs) {
  return conexao.prepare(`
    SELECT id, conteudo
    FROM observacoes
    WHERE projeto = :projeto
      AND id != :id
      AND substituida_por IS NULL
      AND criada_em < :criada_em
    ORDER BY criada_em DESC
    LIMIT :limite
  `).all({ projeto: obs.projeto, id: obs.id, criada_em: obs.criada_em, limite: INDEPENDENTE });
}

function embaralhar(arr) {
  const copia = arr.slice();
  for (let i = copia.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copia[i], copia[j]] = [copia[j], copia[i]];
  }
  return copia;
}

// Monta o conjunto de candidatas: FTS5 (até K_CANDIDATAS) UNIÃO independentes
// (até INDEPENDENTE), sem duplicar id, embaralhado. Devolve também o Set de
// ids que vieram do FTS5 — é contra ele que o recall se mede.
function montarConjuntoCandidatas(conexao, obs) {
  const doFts = buscarCandidatas(conexao, obs);
  const independentes = buscarIndependentes(conexao, obs);
  const ftsIds = new Set(doFts.map((c) => c.id));

  const porId = new Map();
  for (const c of doFts) porId.set(c.id, c.conteudo);
  for (const c of independentes) if (!porId.has(c.id)) porId.set(c.id, c.conteudo);

  const uniao = embaralhar(Array.from(porId, ([id, conteudo]) => ({ id, conteudo })));

  return { candidatas: uniao, ftsIds, tamanhoFts: doFts.length, tamanhoIndependentes: independentes.length };
}

// Mesma pergunta que `formatarPromptReconciliacao` em scripts/memoria.cjs faz
// ao reconciliar de verdade — só que aqui as candidatas vêm numeradas (1..N),
// sem id de banco visível, para a LLM nunca saber qual veio do FTS5.
function formatarPromptMedicao(observacao, candidatasRotuladas) {
  const linhas = candidatasRotuladas
    .map((c, i) => `- [${i + 1}] ${c.conteudo}`)
    .join('\n');

  return [
    'Observacao nova (sondada):',
    observacao.conteudo,
    '',
    'Candidatas parecidas, mesmo projeto (numeradas 1..N, ordem sem significado):',
    linhas || '(nenhuma)',
    '',
    'Decida a acao para a observacao sondada:',
    '- store: nova, sem relacao com nenhuma candidata',
    '- update: a observacao sondada atualiza uma candidata desatualizada (informe alvo_id = numero da candidata)',
    '- merge: a observacao sondada e uma candidata sao complementares e devem se fundir (informe alvo_id = numero da candidata)',
    '- skip: a observacao sondada ja esta coberta por uma candidata, descarte',
    '',
    'Responda em JSON estrito, sem texto antes ou depois:',
    '{"acao": "store"|"update"|"merge"|"skip", "alvo_id": <numero da candidata ou null>}',
  ].join('\n');
}

// Mesmo padrão de chamada que `chamarLLMParaConsolidar`/`chamarLLMParaReconciliar`
// em scripts/memoria.cjs: spawn do `claude` resolvido por
// achar-executavel-claude.cjs, modelo claude-haiku-4-5-20251001, sem
// ferramentas. Retorna { texto, falhaDeSpawn } — falhaDeSpawn distingue erro
// de SO ao criar o processo (ENOENT/UNKNOWN, exit code negativo de libuv) de
// resposta ausente/timeout, porque só o primeiro caso é candidato a nova
// tentativa (ver `chamarLLM`).
function tentarChamarLLMUmaVez(executavel, prompt) {
  const { spawn } = require('child_process');
  const os = require('os');

  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      console.error('AVISO: chamada à LLM expirou (timeout 60s)');
      resolve({ texto: null, falhaDeSpawn: false });
    }, TIMEOUT_MS);

    try {
      const child = spawn(executavel, [
        prompt,
        '-p',
        '--model', 'claude-haiku-4-5-20251001',
        '--setting-sources', '',
        '--permission-mode', 'dontAsk',
        '--disallowedTools', 'Read,Write,Edit,Bash,Glob,Grep,WebFetch,WebSearch,Task,NotebookEdit',
      ], {
        cwd: os.tmpdir(),
        windowsHide: true,
        timeout: TIMEOUT_MS + 5000,
      });

      let stdout = '';
      child.stdout.on('data', (d) => { stdout += d.toString(); });
      child.stderr.on('data', () => {});
      child.stdin.end();

      child.on('error', (error) => {
        clearTimeout(timer);
        console.error(`AVISO: erro ao chamar claude em "${executavel}": ${error.message}`);
        resolve({ texto: null, falhaDeSpawn: true });
      });

      child.on('close', (code) => {
        clearTimeout(timer);
        if (code !== 0) {
          console.error(`AVISO: claude retornou exit code ${code}`);
          // Exit code negativo de libuv (ex.: -4058 = ENOENT) indica falha
          // ao criar o processo sob contenção de SO, não recusa do modelo.
          resolve({ texto: null, falhaDeSpawn: code < 0 });
          return;
        }
        if (!stdout || !stdout.trim()) {
          console.error('AVISO: LLM retornou saída vazia');
          resolve({ texto: null, falhaDeSpawn: false });
          return;
        }
        resolve({ texto: stdout.trim(), falhaDeSpawn: false });
      });
    } catch (e) {
      clearTimeout(timer);
      console.error(`AVISO: erro ao invocar claude em "${executavel}": ${e.message}`);
      resolve({ texto: null, falhaDeSpawn: true });
    }
  });
}

function dormir(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Máquina sob contenção (vários agentes rodando `claude`/`node` ao mesmo
// tempo) produz falha intermitente de SO ao criar o processo — ENOENT/UNKNOWN
// mesmo com o executável existindo, medido nesta máquina em 2026-09-18. Até
// MAX_TENTATIVAS_SPAWN tentativas extras, só quando a falha foi de spawn (não
// de timeout nem de resposta vazia, que já são "sem decisão" legítimo).
const MAX_TENTATIVAS_SPAWN = 3;

async function chamarLLM(executavel, prompt) {
  if (prompt.length > TETO_ARGUMENTO) {
    console.error(`AVISO: prompt acima do teto (${prompt.length} > ${TETO_ARGUMENTO})`);
    return null;
  }

  for (let tentativa = 1; tentativa <= MAX_TENTATIVAS_SPAWN; tentativa++) {
    const { texto, falhaDeSpawn } = await tentarChamarLLMUmaVez(executavel, prompt);
    if (texto !== null) return texto;
    if (!falhaDeSpawn) return null;
    if (tentativa < MAX_TENTATIVAS_SPAWN) {
      console.error(`AVISO: falha de spawn, tentativa ${tentativa}/${MAX_TENTATIVAS_SPAWN}, nova tentativa em 1s`);
      await dormir(1000);
    }
  }
  console.error(`AVISO: falha de spawn persistente após ${MAX_TENTATIVAS_SPAWN} tentativas`);
  return null;
}

// Sorteia a amostra estratificada pelas duas metades do corpus bilíngue:
// `sessao:%` (nativas, português) e `claude-mem:%` (importadas, inglês).
// Metade do teto para cada uma (a última leva o resto se ímpar) — sem isto
// uma amostra puramente aleatória teria ~12% de português (1.375 de 11.467)
// e o recorte por idioma que o D4 pede sairia com base estatística fraca.
function sortearAmostra(conexao, amostra) {
  const metadeA = Math.floor(amostra / 2);
  const metadeB = amostra - metadeA;

  const portugues = conexao.prepare(`
    SELECT id, projeto, conteudo, criada_em, origem
    FROM observacoes
    WHERE origem LIKE 'sessao:%' AND substituida_por IS NULL
    ORDER BY RANDOM()
    LIMIT ?
  `).all(metadeA);

  const ingles = conexao.prepare(`
    SELECT id, projeto, conteudo, criada_em, origem
    FROM observacoes
    WHERE origem LIKE 'claude-mem:%' AND substituida_por IS NULL
    ORDER BY RANDOM()
    LIMIT ?
  `).all(metadeB);

  return embaralhar([...portugues, ...ingles]);
}

function classificarIdioma(origem) {
  if (String(origem || '').startsWith('sessao:')) return 'portugues';
  if (String(origem || '').startsWith('claude-mem:')) return 'ingles';
  return 'outro';
}

function formatarPct(n, d) {
  if (d === 0) return 'n/d (0 decisões update/merge)';
  return `${((n / d) * 100).toFixed(1)}%`;
}

async function medir(amostra) {
  const { caminhoDb } = resolverCaminhos();
  const conexao = abrirBancoSomenteLeitura(caminhoDb);
  if (!conexao) {
    throw new Error(`não consegui abrir o banco somente-leitura em ${caminhoDb}`);
  }

  const executavel = acharExecutavelClaude();
  if (!executavel) {
    conexao.close();
    throw new Error('não encontrei o executável `claude` no PATH (scripts/lib/achar-executavel-claude.cjs devolveu null)');
  }

  const sondadas = sortearAmostra(conexao, amostra);
  if (sondadas.length === 0) {
    conexao.close();
    throw new Error('amostra vazia — corpus sem observações vivas em sessao:%% ou claude-mem:%%');
  }

  const resultado = {
    caminhoDb,
    executavel,
    amostraRequisitada: amostra,
    amostraObtida: sondadas.length,
    falhas: 0,
    tamanhoConjuntoExemplo: null,
    porIdioma: {
      portugues: { n: 0, hits: 0, denom: 0, store: 0, skip: 0, falhas: 0 },
      ingles: { n: 0, hits: 0, denom: 0, store: 0, skip: 0, falhas: 0 },
      outro: { n: 0, hits: 0, denom: 0, store: 0, skip: 0, falhas: 0 },
    },
    global: { hits: 0, denom: 0 },
    itens: [],
  };

  let i = 0;
  for (const obs of sondadas) {
    i++;
    const idioma = classificarIdioma(obs.origem);
    resultado.porIdioma[idioma].n++;

    const { candidatas, ftsIds, tamanhoFts, tamanhoIndependentes } = montarConjuntoCandidatas(conexao, obs);

    if (resultado.tamanhoConjuntoExemplo === null && candidatas.length > K_CANDIDATAS) {
      resultado.tamanhoConjuntoExemplo = {
        idObservacao: obs.id,
        tamanhoFts,
        tamanhoIndependentes,
        tamanhoUniao: candidatas.length,
      };
    }

    if (candidatas.length === 0) {
      // Nada para comparar (nem FTS5 nem histórico do projeto): decisão
      // automática 'store', poupa a chamada — mesmo comportamento de
      // cmdReconciliar quando buscarCandidatas devolve vazio.
      resultado.porIdioma[idioma].store++;
      console.log(`[${i}/${sondadas.length}] obs ${obs.id} (${idioma}): sem candidatas, store automático`);
      continue;
    }

    const prompt = formatarPromptMedicao(obs, candidatas);

    let respostaBruta;
    try {
      respostaBruta = await chamarLLM(executavel, prompt);
    } catch (e) {
      respostaBruta = null;
      console.error(`AVISO: exceção na chamada da observação ${obs.id}: ${e.message}`);
    }

    if (respostaBruta === null) {
      resultado.falhas++;
      resultado.porIdioma[idioma].falhas++;
      console.log(`[${i}/${sondadas.length}] obs ${obs.id} (${idioma}): FALHA na chamada à LLM — sem decisão`);
      continue;
    }

    const decisao = interpretarDecisaoReconciliacao(respostaBruta);

    if (decisao.acao === 'update' || decisao.acao === 'merge') {
      const label = decisao.alvo_id;
      const alvo = (label !== null && Number.isInteger(label) && label >= 1 && label <= candidatas.length)
        ? candidatas[label - 1]
        : null;
      const hit = alvo !== null && ftsIds.has(alvo.id);

      resultado.global.denom++;
      resultado.porIdioma[idioma].denom++;
      if (hit) {
        resultado.global.hits++;
        resultado.porIdioma[idioma].hits++;
      }

      resultado.itens.push({ id: obs.id, idioma, acao: decisao.acao, hit });
      console.log(`[${i}/${sondadas.length}] obs ${obs.id} (${idioma}): ${decisao.acao} -> alvo rotulo=${label} ${hit ? 'HIT (estava no FTS5)' : 'MISS (fora do FTS5)'}`);
    } else if (decisao.acao === 'skip') {
      resultado.porIdioma[idioma].skip++;
      console.log(`[${i}/${sondadas.length}] obs ${obs.id} (${idioma}): skip`);
    } else {
      resultado.porIdioma[idioma].store++;
      console.log(`[${i}/${sondadas.length}] obs ${obs.id} (${idioma}): store`);
    }
  }

  conexao.close();
  return resultado;
}

function montarRelatorio(r, amostraArg) {
  const hoje = new Date().toISOString().slice(0, 10);
  const recallGlobalPct = formatarPct(r.global.hits, r.global.denom);
  const pt = r.porIdioma.portugues;
  const en = r.porIdioma.ingles;
  const recallPtPct = formatarPct(pt.hits, pt.denom);
  const recallEnPct = formatarPct(en.hits, en.denom);

  const LIMIAR = 70;
  const ptNum = pt.denom > 0 ? (pt.hits / pt.denom) * 100 : null;
  const enNum = en.denom > 0 ? (en.hits / en.denom) * 100 : null;

  let veredito;
  if (ptNum === null || enNum === null) {
    veredito = `sem dados suficientes para veredito — pelo menos uma das metades não teve decisão update/merge na amostra (portugues denom=${pt.denom}, ingles denom=${en.denom}). Repetir com amostra maior ou revisar a estratificação antes de decidir.`;
  } else if (ptNum < LIMIAR || enNum < LIMIAR) {
    const qual = [];
    if (ptNum < LIMIAR) qual.push(`portugues (${ptNum.toFixed(1)}%)`);
    if (enNum < LIMIAR) qual.push(`ingles (${enNum.toFixed(1)}%)`);
    veredito = `recall abaixo de ${LIMIAR}% em ${qual.join(' e ')} — vira decisão de vetor no próximo design (limiar do plano \`docs/rainforest/planos/2026-09-16-memoria-reconciliacao-e-consolidacao.md\`, tarefa 7).`;
  } else {
    veredito = `recall de ${LIMIAR}% ou mais nas duas metades (portugues ${ptNum.toFixed(1)}%, ingles ${enNum.toFixed(1)}%) — mantém FTS5 com K=5, sem vetor.`;
  }

  const exemplo = r.tamanhoConjuntoExemplo;
  const linhaExemplo = exemplo
    ? `Exemplo de conjunto apresentado (observação ${exemplo.idObservacao}): FTS5 trouxe ${exemplo.tamanhoFts}, independentes trouxe ${exemplo.tamanhoIndependentes}, união sem duplicata = ${exemplo.tamanhoUniao} candidatas (maior que K = 5).`
    : 'Nenhum item da amostra teve conjunto de candidatas maior que K = 5 (corpus com pouco histórico por projeto).';

  return `# Recall do FTS5 como buscador de candidatas — reconciliação de memória

Medição da tarefa 7 (D4) do plano
\`docs/rainforest/planos/2026-09-16-memoria-reconciliacao-e-consolidacao.md\`, rodada em
${hoje} contra cópia somente-leitura de \`${r.caminhoDb}\`.

## Desenho

A pergunta do D4: o FTS5 sozinho acha a observação certa para reconciliar, ou falta
índice vetorial? O risco nomeado é o corpus bilíngue: observações nativas em
português e observações importadas do claude-mem em inglês.

Para cada observação sondada, o conjunto de candidatas apresentado à LLM é **maior**
que o do FTS5 — senão o recall sairia 100% por construção, porque a LLM só veria o
que o FTS5 trouxe:

- as **K = 5** candidatas que o FTS5 traria (\`K_CANDIDATAS\` de \`scripts/memoria.cjs\`,
  \`bm25(observacoes_fts)\`, mesmo \`projeto\`);
- mais as **independente: 20** observações mais recentes do mesmo \`projeto\`,
  anteriores à sondada (função \`buscarIndependentes\` em
  \`scripts/medir-recall-reconciliacao.cjs\` — não vem do FTS5).

A união (sem duplicar id) é embaralhada e apresentada à LLM numerada de 1 a N, sem id
de banco visível. ${linhaExemplo}

Pergunta-se à LLM exatamente o que \`cmdReconciliar\` pergunta na produção (mesma
ação válida: store/update/merge/skip). Das decisões \`update\`/\`merge\`, o **recall**
é a fração cujo alvo escolhido estava entre as 5 do FTS5.

## Amostra

- amostra: ${amostraArg} (requisitada via \`--amostra\`; obtida: ${r.amostraObtida})
- estratificada meio a meio entre as duas metades do corpus bilíngue
- falhas na chamada à LLM (item "sem decisão", não contam no recall): ${r.falhas}

## Resultado

| corpus | origem | n na amostra | store | skip | decisões update/merge | hits (no FTS5) | recall | falhas |
|---|---|---|---|---|---|---|---|---|
| portugues | \`sessao:%\` | ${pt.n} | ${pt.store} | ${pt.skip} | ${pt.denom} | ${pt.hits} | ${recallPtPct} | ${pt.falhas} |
| ingles | \`claude-mem:%\` | ${en.n} | ${en.store} | ${en.skip} | ${en.denom} | ${en.hits} | ${recallEnPct} | ${en.falhas} |

recall global: ${recallGlobalPct} (${r.global.hits}/${r.global.denom})

## Veredito

veredito: ${veredito}

Limiar deste plano: recall abaixo de 70% em qualquer das duas metades vira decisão de
vetor no próximo design; 70% ou mais mantém o FTS5 com K = 5.
`;
}

async function main() {
  const { amostra } = parseArgs(process.argv.slice(2));

  let r;
  try {
    r = await medir(amostra);
  } catch (e) {
    console.error(`BLOQUEIO: ${e.message}`);
    process.exit(1);
  }

  const relatorio = montarRelatorio(r, amostra);
  const destino = path.join(__dirname, '..', 'relatorios', '2026-09-18-recall-fts5-reconciliacao.md');
  require('fs').mkdirSync(path.dirname(destino), { recursive: true });
  require('fs').writeFileSync(destino, relatorio, 'utf8');

  console.log('');
  console.log(`amostra obtida: ${r.amostraObtida}/${amostra}, falhas na chamada à LLM: ${r.falhas}`);
  console.log(`recall global: ${r.global.hits}/${r.global.denom}`);
  console.log(`relatório escrito em: ${destino}`);
}

if (require.main === module) {
  main();
}

module.exports = { montarConjuntoCandidatas, buscarIndependentes, formatarPromptMedicao, classificarIdioma };
