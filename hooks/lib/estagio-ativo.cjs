#!/usr/bin/env node
/**
 * Resolvedor de estágio ativo por branch
 *
 * Retorna o estágio ativo (próximo não-fechado) do fluxo cuja branch atual
 * casa com o slug do arquivo de estado, sem precisar da slug explícita.
 *
 * Padrão copiado de scripts/saude.cjs:138-162 — remove o prefixo de data
 * (`^\d{4}-\d{2}-\d{2}-`) e compara com a branch. A convenção vem de
 * skills/rainforest-mind/references/regra-11.md:32.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { caminhoExecutavel } = require('./resolver-executavel.cjs');

// Lógica oficial de fechamento e de próximo estágio: vem do `estado.cjs`, que é
// o dono dela. O caminho é relativo a `__dirname`, não ao cwd — resolve igual
// rodando da raiz do projeto, de um worktree, ou do cache do plugin.
//
// NÃO há fallback local, e a ausência dele é a decisão. Até 2026-09-01 havia
// duas coisas erradas aqui, achadas em rodadas seguidas da revisão: primeiro um
// `require` guardado numa variável que ninguém lia, ao lado de um comentário
// prometendo usar a lógica oficial (rodada 4); depois, já com o import de
// verdade, uma cópia local `proximoLocal`/`estaFechadoLocal` mantida como
// fallback — byte-idêntica ao oficial e **descoberta por teste nenhum**. A
// rodada 5 provou: sabotar só a cópia deixava a bateria VERDE.
//
// Cópia sem teste ao lado do original é divergência esperando data, e por isso
// ela saiu. Mas o argumento que veio junto — "se o `estado.cjs` não carregar, o
// certo é estourar alto e agora, porque a portaria é fail-closed" — estava
// ERRADO, e a rodada 6 da revisão pegou: estourar aqui produz exit 1 no hook, e
// exit 1 num `PreToolUse` é erro NÃO-BLOQUEANTE — o despacho passa. Estourar
// abria a portaria, não fechava.
//
// O `require` continua sem `try/catch` de propósito: quem transforma exceção em
// decisão é a rede no topo de `hooks/portaria.cjs`, que captura qualquer coisa
// que escape de `main()` e sai com exit 2 e motivo. Uma rede só, no lugar onde
// a decisão mora — e não `try/catch` espalhado devolvendo valor inventado.
const { proximo } = require("../../scripts/estado.cjs");

// ============================================================================
// RESOLVER
// ============================================================================

function resolver({ cwd }) {
  // cwd deve ser a raiz de um repositório git
  if (!cwd || typeof cwd !== 'string') return null;

  // 1. Obter branch atual
  let branch;
  try {
    branch = execFileSync(caminhoExecutavel('git'), ['rev-parse', '--abbrev-ref', 'HEAD'], {
      cwd,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (_) {
    // Não é repositório git ou git falhou
    return null;
  }

  if (!branch || branch === 'HEAD') {
    return null; // Não há branch clara
  }

  // 2. Remover prefixos tipo 'fluxo/' (convenção de branch)
  // A branch pode ser 'fluxo/memoria-e-dados' ou 'memoria-e-dados'
  const branchBase = branch.replace(/^.*?\//, '');

  // 3. Ler arquivos de estado de `docs/rainforest/estado/`
  const dirEstado = path.join(cwd, 'docs', 'rainforest', 'estado');
  let arquivos;
  try {
    if (!fs.existsSync(dirEstado)) return null;
    arquivos = fs.readdirSync(dirEstado).filter((f) => f.endsWith('.json'));
  } catch (_) {
    return null;
  }

  if (!arquivos.length) return null;

  // 4. Encontrar candidatos: arquivos cujo slug (pós-data) casa com a branch
  // e que têm estágio aberto
  const candidatos = [];

  for (const arquivo of arquivos) {
    const slug = arquivo.replace(/\.json$/, '');
    let estado;

    // Ler o JSON
    try {
      const conteudo = fs.readFileSync(path.join(dirEstado, arquivo), 'utf8');
      estado = JSON.parse(conteudo);
    } catch (_) {
      // JSON inválido ou arquivo ilegível — não conta como candidato
      continue;
    }

    if (!estado || typeof estado !== 'object') continue;

    // Extrair o slug sem o prefixo de data (`^\d{4}-\d{2}-\d{2}-`)
    // Padrão: 2026-08-17-memoria-e-dados-do-rainforest
    const slugSemData = slug.replace(/^\d{4}-\d{2}-\d{2}-/, '');

    // ...e sem o prefixo de numeracao de fluxo (`fluxo-<N>-`), que a convencao
    // `<data>-<branch>` da regra 11 nao previa mas o repo passou a usar: o
    // estado do fluxo 9 se chama `fluxo-9-portaria` e a branch dele e
    // `fluxo/portaria`. Sem esta segunda forma, `resolver` devolvia `null` na
    // branch real — medido em 2026-09-01 — e a portaria, que e fail-closed,
    // negaria TODO despacho justamente no repositorio que a implementa.
    //
    // Ambiguidade continua negando: se `portaria.json` e `fluxo-9-portaria.json`
    // existirem os dois com estagio aberto, os dois viram candidato e o
    // `candidatos.length !== 1` la embaixo devolve `null`, como antes.
    const slugSemNumeroDeFluxo = slugSemData.replace(/^fluxo-\d+-/, '');

    // Verificar se alguma das duas formas do slug casa com a branch
    if (slugSemData !== branchBase && slugSemNumeroDeFluxo !== branchBase) continue;

    // Verificar se há estágio aberto (próximo !== null)
    const prox = proximo(estado);
    if (prox === null) {
      // Fluxo completo — não é candidato
      continue;
    }

    // É candidato!
    candidatos.push({ slug, estado, estagio: prox });
  }

  // 5. Retornar resultado
  // Ambiguidade nega — a condição tem que existir literal como `candidatos.length !== 1`
  if (candidatos.length !== 1) {
    return null;
  }

  const { slug, estagio } = candidatos[0];
  return { slug, estagio };
}

// Issue #447: quando `resolver` devolve null numa branch de trabalho, a portaria
// dizia so "fora-de-fluxo", e achar a causa (branch com o slug inteiro, com data,
// nao casa) exigia ler este arquivo. `diagnosticar` refaz a leitura e devolve o
// que faltou: a branch lida, a base comparada e os fluxos abertos mais perto, cada
// um com a branch que casaria. Falha aberta: qualquer erro devolve null e a
// mensagem sai sem o diagnostico, como antes.
function distancia(a, b) {
  const linha = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    let anterior = linha[0];
    linha[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const guardado = linha[j];
      linha[j] = Math.min(linha[j] + 1, linha[j - 1] + 1, anterior + (a[i - 1] === b[j - 1] ? 0 : 1));
      anterior = guardado;
    }
  }
  return linha[b.length];
}

function diagnosticar({ cwd }, limite = 3) {
  try {
    const branch = execFileSync(caminhoExecutavel('git'), ['rev-parse', '--abbrev-ref', 'HEAD'], {
      cwd,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
    if (!branch || branch === 'HEAD') return null;
    const branchBase = branch.replace(/^.*?\//, '');
    const dirEstado = path.join(cwd, 'docs', 'rainforest', 'estado');
    if (!fs.existsSync(dirEstado)) return { branch, branchBase, abertos: [], casados: 0 };
    const abertos = [];
    let casados = 0;
    for (const arquivo of fs.readdirSync(dirEstado).filter((f) => f.endsWith('.json'))) {
      const slug = arquivo.replace(/\.json$/, '');
      let estado;
      try {
        estado = JSON.parse(fs.readFileSync(path.join(dirEstado, arquivo), 'utf8'));
      } catch (_) {
        continue;
      }
      if (!estado || typeof estado !== 'object' || proximo(estado) === null) continue;
      const slugSemData = slug.replace(/^\d{4}-\d{2}-\d{2}-/, '');
      const semNumero = slugSemData.replace(/^fluxo-\d+-/, '');
      if (slugSemData === branchBase || semNumero === branchBase) casados++;
      abertos.push({ slug, esperado: `fluxo/${semNumero}`, d: Math.min(distancia(branchBase, slugSemData), distancia(branchBase, slug)) });
    }
    abertos.sort((x, y) => x.d - y.d || x.slug.localeCompare(y.slug));
    return { branch, branchBase, casados, abertos: abertos.slice(0, limite).map(({ slug, esperado }) => ({ slug, esperado })) };
  } catch (_) {
    return null;
  }
}

module.exports = { resolver, diagnosticar };
