#!/usr/bin/env node
// @categoria: sensor
/**
 * SubagentStop — grava o veredito de uma linha do `revisor` (D1/D3/D5,
 * `docs/rainforest/design/2026-09-23-contrato-de-veredito.md`).
 *
 * Best-effort, sempre sai 0 (molde `hooks/escada-subagente.cjs`): payload
 * ilegível, agente que não é revisor, transcrito ausente, ou briefing sem
 * `Slug:` — nada acontece, sem stack trace, sem derrubar a sessão do
 * usuário. A gravação em si (upsert por `agent_id`, trava contra escrita
 * concorrente) mora em `scripts/estado.cjs veredito` (task 3, já
 * integrada) — este hook só junta os três dados que faltam pra chamar esse
 * subcomando: slug, veredito, raiz do repositório.
 *
 * Fluxo:
 *   1. lê o payload do `SubagentStop` do stdin.
 *   2. filtra por `agent_type` — só `revisor`/`rainforest-mind:revisor`
 *      (outros agentes, mesmo com `Slug:` e veredito válidos no
 *      transcrito, saem sem gravar nada).
 *   3. acha o transcrito do SUBAGENTE (`agent_transcript_path`, com
 *      fallback calculado a partir de `transcript_path` + `session_id` +
 *      `agent_id` — achado 3 do plano) e lê a primeira mensagem dele pra
 *      achar a linha `Slug: <slug>` do briefing. Nunca usa
 *      `payload.transcript_path` direto como fonte do slug: é o transcrito
 *      da SESSÃO PRINCIPAL, cujo prompt de quem despacha também costuma
 *      ter `Slug:` — daria falso positivo (achado 3 do plano).
 *   4. extrai o veredito da ÚLTIMA linha de `last_assistant_message`
 *      (`scripts/lib/extrair-veredito.cjs`, D2, task 2) contra o
 *      vocabulário fechado; fora dele → candidato a `invalido`.
 *   5. depois de TODAS as checagens acima (agent_type, Slug, transcrito,
 *      cwd/repoRoot, toggle `contrato-veredito`) — tarefa 3 do plano
 *      `2026-09-25-veredito-fora-da-linha`, D1/D3/D5: se o veredito deu
 *      `invalido` e esta NÃO é a segunda parada
 *      (`payload.stop_hook_active !== true`), o hook devolve a vez ao
 *      revisor: imprime no stdout `{"decision":"block","reason":...}`
 *      pedindo a linha exata e sai 0 SEM gravar (confirmado ao vivo em
 *      `docs/rainforest/pesquisas/2026-09-25-subagentstop-block.md`: o
 *      harness honra esse bloqueio e devolve o `reason` ao subagente, que
 *      pode responder de novo). Na segunda parada (`stop_hook_active ===
 *      true`) segue o caminho de sempre: grava `invalido`, sem bloquear de
 *      novo (D3 — uma chance só, para não laçar o subagente).
 *   6. grava via `node scripts/estado.cjs veredito ...`, cwd = raiz do
 *      repositório do EVENTO (`payload.cwd`), nunca a do processo do hook
 *      (molde `hooks/gate-agente-em-voo.cjs` ~56-67 para a função
 *      `toplevel`).
 */

const fs = require('fs');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { primeiroPrompt, extrairSlug } = require(path.join(__dirname, '..', 'scripts', 'lib', 'primeiro-prompt-jsonl.cjs'));
const { extrairUltimaLinha, validarVocabulario } = require(path.join(__dirname, '..', 'scripts', 'lib', 'extrair-veredito.cjs'));

const VOCAB_ULTIMA_LINHA = ['veredito: ok', 'veredito: reprovado'];

// Raiz do PLUGIN (onde mora scripts/estado.cjs) — nunca a do projeto em que
// se trabalha. O hook roda em repositórios alheios (payload.cwd é a raiz do
// PROJETO, não a do rainforest-mind); sem isso o spawnSync abaixo daria
// ENOENT em silêncio em todo projeto que não seja o próprio plugin. Mesma
// variável que `hooks/escada-subagente.cjs` usa.
const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || path.resolve(__dirname, '..');

/** Raiz do repositório do cwd do EVENTO — nunca a do processo do hook
 * (mesma função de `hooks/gate-agente-em-voo.cjs` ~56-67). */
function toplevel(cwd) {
  try {
    return execFileSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim() || null;
  } catch {
    return null;
  }
}

/**
 * D5 — #329: procura docs/rainforest/estado/<slug>.json em repoRoot ou em
 * worktrees linkados. Devolve o caminho onde o arquivo existe (única fonte
 * de verdade), ou null se ambíguo/ausente.
 *
 * Precedência:
 * 1. Se existe em repoRoot, devolve repoRoot (raiz é sempre válida).
 * 2. Senão, procura `git worktree list --porcelain` por worktrees que tenham o arquivo.
 * 3. Exatamente um → devolve esse caminho; 0 ou 2+ → stderr + null.
 *
 * Nunca derruba a sessão: falha em git/stat vira "não encontrado".
 */
function raizComEstadoDoSlug(repoRoot, slug) {
  if (!slug) return repoRoot; // slug vazio = sem estado em lugar nenhum
  const estadoFile = path.join(repoRoot, 'docs', 'rainforest', 'estado', `${slug}.json`);
  if (fs.existsSync(estadoFile)) return repoRoot;

  // Procura em worktrees linkados
  let worktreeOutput;
  try {
    worktreeOutput = execFileSync('git', ['-C', repoRoot, 'worktree', 'list', '--porcelain'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    // Sem git worktree list: trata como "não encontrado"
    process.stderr.write(`${slug} nao encontrado\n`);
    return null;
  }

  const worktreePaths = [];
  const linhas = worktreeOutput.split('\n');
  for (const linha of linhas) {
    if (linha.startsWith('worktree ')) {
      const wtPath = linha.slice(9); // "worktree ".length = 9
      if (wtPath && path.resolve(wtPath) !== path.resolve(repoRoot)) {
        // Verifica se este worktree tem o arquivo
        const wtEstadoFile = path.join(wtPath, 'docs', 'rainforest', 'estado', `${slug}.json`);
        if (fs.existsSync(wtEstadoFile)) {
          worktreePaths.push(wtPath);
        }
      }
    }
  }

  if (worktreePaths.length === 1) {
    return worktreePaths[0];
  } else if (worktreePaths.length === 0) {
    process.stderr.write(`${slug} nao encontrado\n`);
  } else {
    // 2 ou mais
    const paths = worktreePaths.join(' ');
    process.stderr.write(`${slug} ambiguo: ${paths}\n`);
  }
  return null;
}

/**
 * Caminho do transcrito do SUBAGENTE. `agent_transcript_path` quando o
 * payload trouxer; senão o fallback que bateu byte a byte na captura da
 * task 1: `<dirname(transcript_path)>/<session_id>/subagents/agent-<agent_id>.jsonl`.
 */
function caminhoTranscritoSubagente(payload) {
  if (typeof payload.agent_transcript_path === 'string' && payload.agent_transcript_path) {
    return payload.agent_transcript_path;
  }
  if (
    typeof payload.transcript_path === 'string' && payload.transcript_path
    && typeof payload.session_id === 'string' && payload.session_id
    && typeof payload.agent_id === 'string' && payload.agent_id
  ) {
    return path.join(
      path.dirname(payload.transcript_path),
      payload.session_id,
      'subagents',
      `agent-${payload.agent_id}.jsonl`,
    );
  }
  return null;
}

function main() {
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0); // payload ilegível nunca derruba a sessão do usuário
  }

  const agentType = payload.agent_type;
  if (!['revisor', 'rainforest-mind:revisor'].includes(agentType)) process.exit(0);

  const caminhoTranscrito = caminhoTranscritoSubagente(payload);
  if (!caminhoTranscrito) process.exit(0);

  const prompt = primeiroPrompt(caminhoTranscrito);
  if (!prompt) process.exit(0);

  const slug = extrairSlug(prompt);
  if (!slug) process.exit(0); // revisão avulsa (D5): não grava, não trava

  // Ausente de vez (nem string) e caso que nao ha o que auditar. String
  // vazia (revisor que saiu sem texto) SEGUE para invalido — D3: a revisao
  // existe e fica registrada, o silencio e so para "nao houve revisor".
  // Na primeira parada, invalido ainda desvia para o bloqueio (D1, abaixo).
  if (typeof payload.last_assistant_message !== 'string') process.exit(0);
  const ultimaLinha = extrairUltimaLinha(payload.last_assistant_message);
  const veredito = validarVocabulario(ultimaLinha, VOCAB_ULTIMA_LINHA)
    ? (ultimaLinha === 'veredito: ok' ? 'ok' : 'reprovado')
    : 'invalido'; // D3: fora do vocabulário, mas o registro fica auditável

  if (typeof payload.cwd !== 'string' || !payload.cwd) process.exit(0);
  const repoRoot = toplevel(payload.cwd);
  if (!repoRoot) process.exit(0);

  try {
    if (!require('./lib/config.cjs').ligado('contrato-veredito', { projeto: repoRoot })) {
      process.exit(0);
    }
  } catch {}

  // Tarefa 3 (D1/D3/D5): depois de TODAS as checagens acima, primeira
  // parada com veredito invalido devolve a vez ao revisor em vez de gravar
  // invalido de cara. Na segunda parada (stop_hook_active === true) nao
  // bloqueia de novo — segue para a gravacao abaixo, como antes desta tarefa.
  if (veredito === 'invalido' && payload.stop_hook_active !== true) {
    const reason = 'Termine a mensagem com uma linha sozinha e exata, sem nada depois dela na mesma linha: VEREDITO: ok ou VEREDITO: reprovado (negrito, sublinhado ou crase em volta da linha e aceito, ex.: **VEREDITO: ok**). Nao repita a analise que voce ja escreveu, so acrescente essa linha final.';
    process.stdout.write(JSON.stringify({ decision: 'block', reason }) + '\n');
    process.exit(0);
  }

  // D5 — #329: procura docs/rainforest/estado/<slug>.json no repoRoot ou em worktrees
  const raizEstado = raizComEstadoDoSlug(repoRoot, slug);
  if (!raizEstado) process.exit(0);

  const estadoCjs = path.join(PLUGIN_ROOT, 'scripts', 'estado.cjs');
  const args = [
    estadoCjs, 'veredito',
    '--slug', slug,
    '--estagio', 'revisar',
    '--veredito', veredito,
    '--agente', String(agentType),
    // D12 — Tarefa 16: `estado.cjs veredito` agora exige --transcrito e
    // confere nele (dentro de subagents/, Slug bate, ultima linha bate) —
    // o mesmo caminho que este hook ja resolveu para achar o Slug.
    '--transcrito', caminhoTranscrito,
  ];
  if (typeof payload.agent_id === 'string' && payload.agent_id) {
    args.push('--agente-id', payload.agent_id);
  }

  try {
    // `estado.cjs` resolve a raiz de dados por RFM_ESTADO_ROOT ||
    // CLAUDE_PROJECT_DIR || process.cwd() (nessa ordem). `cwd: raizEstado`
    // cobre o último caso, mas CLAUDE_PROJECT_DIR herdado do processo do
    // hook (a sessão pode ter aberto no checkout principal e entrado em
    // worktree) venceria `cwd` — por isso ele é sobrescrito aqui com a raiz
    // DO ESTADO, que pode ser um worktree (D5), a mesma que
    // `hooks/gate-agente-em-voo.cjs` trata como única fonte. RFM_ESTADO_ROOT,
    // quando setado (sandbox de teste), não é tocado e continua vencendo tudo.
    spawnSync(process.execPath, args, {
      cwd: raizEstado,
      env: { ...process.env, CLAUDE_PROJECT_DIR: raizEstado },
      stdio: 'ignore',
    });
  } catch {
    // best-effort: falha ao gravar nunca derruba a sessão do revisor
  }

  process.exit(0);
}

main();
