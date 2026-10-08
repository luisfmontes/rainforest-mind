'use strict';
/**
 * Sinal de utilidade da memória (D1-D11 do design
 * docs/rainforest/design/2026-09-23-memoria-sinal-de-utilidade.md).
 *
 * Mede, sem mudar a seleção da abertura (D2), se o que foi injetado na sessão
 * (servida) foi de fato usado — e se a recência (que decide as 14 vagas hoje)
 * deixou de fora observação que teria sido útil (contrafactual, D6).
 *
 * Deliberadamente NÃO requer scripts/memoria.cjs — é memoria.cjs que requer
 * este módulo para orquestrar os comandos `utilidade` e `manutencao`, e um
 * require circular deixaria os exports de um dos dois lados incompletos no
 * momento do require (module.exports de memoria.cjs só é atribuído no fim do
 * arquivo). Toda conexão de banco chega já aberta por quem chama.
 *
 * hooks/memoria-session-start.cjs e hooks/lib/memoria-sessao.cjs continuam
 * intocados (a abertura é somente-leitura) — só `formatarObservacao` é
 * importada daqui (usada a partir da Tarefa 2).
 */

const fs = require('fs');
const path = require('path');
const { formatarObservacao } = require('../../hooks/lib/memoria-sessao.cjs');

// Termo raro = aparece em até LIMIAR_DF observações do corpus (Tarefa 2, D5).
// Sem dado de calibração ainda (a ideia é medir por duas semanas antes de
// decidir qualquer coisa, D2) — 3 é conservador: um termo em até 3 das
// milhares de observações do acervo real é claramente específico, não um
// conector comum do domínio.
const LIMIAR_DF = 3;

// Quantas do contrafactual o relatório grava por sessão (D6).
const TETO_CONTRAFACTUAL = 14;

// Observações do dia (Tarefa 6, D8): SEM o filtro de substituida_por. A
// reconciliação roda ANTES da pontuação na mesma passada e pode marcar
// substituida_por numa observação que já foi servida numa sessão ainda
// pendente — D8 mede o que CHEGOU à sessão, não o que sobreviveu à
// reconciliação. `buscarContrafactual` (mais abaixo) continua filtrando
// substituida_por: ali a pergunta é outra, "o que o FTS acharia hoje".
const SQL_OBS_DO_DIA = 'SELECT id, projeto, conteudo, criada_em FROM observacoes WHERE criada_em LIKE ?';

// ---- Tarefa 1: extrator do transcrito ----

const CAB_ABERTURA = '## Memória (corpus residentes)';
const CAB_ASSUNTO = '## Memória do assunto';
// Prioridade quando a mesma memória chega por mais de um canal na sessão.
const ORDEM_CANAL = { abertura: 0, pedido: 1, subagente: 2 };

/**
 * Extrai as linhas servidas (`[AAAA-MM-DD (projeto)] ...`) de UM texto de
 * `additionalContext` — o bloco entre `## Memória (corpus residentes)` e a
 * linha `mais:` (D3, D8). Função pura, sem I/O.
 *
 * @param {string} additionalContext
 * @returns {string[]} linhas servidas, já aparadas (trim), na ordem em que
 *   apareceram no bloco (mais recente primeiro — é assim que montarMemoria as
 *   grava).
 */
function extrairLinhasServidas(additionalContext, cabecalhos = [CAB_ABERTURA, CAB_ASSUNTO]) {
  const texto = String(additionalContext || '');
  const linhas = [];
  for (const cabecalho of cabecalhos) {
    const inicio = texto.indexOf(cabecalho);
    if (inicio === -1) continue;
    const apos = inicio + cabecalho.length;
    const marcaMais = texto.indexOf('mais:', inicio);
    const proxCabecalho = texto.indexOf('\n## ', apos);
    const fins = [marcaMais, proxCabecalho].filter((p) => p !== -1);
    const fim = fins.length === 0 ? texto.length : Math.min(...fins);
    for (const l of texto.slice(inicio, fim).split('\n')) {
      const t = l.trim();
      if (t.startsWith('[')) linhas.push(t);
    }
  }
  return linhas;
}

// Texto dos tool_use.input de um transcrito de subagente + o briefing (primeira
// linha `user`), que NÃO pontua (D8) mas é de onde sai o bloco servido.
function lerTranscritoFilho(arquivo) {
  const r = { briefing: '', textoTools: '' };
  let conteudo;
  try {
    conteudo = fs.readFileSync(arquivo, 'utf8');
  } catch (e) {
    return null;
  }
  const partes = [];
  let viuUser = false;
  for (const l of conteudo.split('\n')) {
    if (!l.trim()) continue;
    let e;
    try {
      e = JSON.parse(l);
    } catch (err) {
      continue;
    }
    const c = e.message && e.message.content;
    if (e.type === 'user' && !viuUser) {
      viuUser = true;
      if (typeof c === 'string') r.briefing = c;
      else if (Array.isArray(c)) r.briefing = c.map((b) => (b && typeof b.text === 'string' ? b.text : '')).join('\n');
    } else if (e.type === 'assistant' && Array.isArray(c)) {
      for (const b of c) {
        if (b && b.type === 'tool_use' && b.input !== undefined) partes.push(JSON.stringify(b.input));
      }
    }
  }
  r.textoTools = partes.join('\n');
  return r;
}

/**
 * Lê um transcrito (.jsonl do harness) e devolve:
 *   - `servidas`: as linhas do bloco de memória que de fato chegaram à
 *     sessão, extraídas do(s) `attachment` de SessionStart (D3, D8) — nunca
 *     das candidatas que o banco tinha, só do que passou pelo corte de
 *     orçamento.
 *   - `texto`: os prompts do usuário mais as entradas (`input`) de cada
 *     `tool_use` do assistente. A prosa do assistente e todo `attachment`
 *     ficam de fora (D4) — a prosa ecoa a injeção e marcaria como "usada"
 *     toda observação só parafraseada.
 *
 * Função pura sobre o conteúdo do arquivo: não escreve nada, não abre banco.
 *
 * As duas formas de mensagem (`user` e `assistant`) passam pelo MESMO laço de
 * blocos — é o que faz a exclusão da prosa do assistente (linha abaixo) ser
 * um filtro de verdade: sem ela, um bloco `text` de um `assistant` cairia no
 * mesmo `if` que inclui texto de `user`, e entraria no texto da sessão.
 *
 * @param {string} caminhoTranscrito
 * @returns {{servidas: string[], texto: string}}
 */
function extrairSessao(caminhoTranscrito) {
  const conteudo = fs.readFileSync(caminhoTranscrito, 'utf8');
  const linhasArquivo = conteudo.split('\n');

  const servidas = [];
  const partesTexto = [];
  // Canais novos (memória por assunto): `pedido` guarda a posição, em
  // partesTexto, do pedido do usuário ao qual a injeção se anexou (o
  // attachment vem DEPOIS da linha `user` do prompt — fixture prompt-submit);
  // `subagente` guarda o agentId para achar o transcrito do filho.
  const injecoes = [];
  const doSubagente = [];
  let ultimoPedido = -1;

  for (const linhaArquivo of linhasArquivo) {
    if (!linhaArquivo.trim()) continue;

    let entrada;
    try {
      entrada = JSON.parse(linhaArquivo);
    } catch (e) {
      continue; // linha corrompida/parcial — ignora, não trava a extração
    }

    // Servidas: só o attachment de SessionStart, só o bloco de memória (D3).
    if (entrada.type === 'attachment' && entrada.attachment && entrada.attachment.hookEvent === 'SessionStart') {
      const stdout = entrada.attachment.stdout;
      let parsed = null;
      try {
        parsed = JSON.parse(stdout);
      } catch (e) {
        parsed = null;
      }
      const ctx = parsed && parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext;
      if (ctx) {
        for (const linha of extrairLinhasServidas(ctx, [CAB_ABERTURA])) servidas.push(linha);
      }
      continue; // attachment nunca entra no texto (D4)
    }

    // Canal `pedido`: contexto adicional do UserPromptSubmit (D8).
    if (
      entrada.type === 'attachment' &&
      entrada.attachment &&
      entrada.attachment.hookEvent === 'UserPromptSubmit' &&
      entrada.attachment.type === 'hook_additional_context'
    ) {
      const c = entrada.attachment.content;
      const ctx = Array.isArray(c) ? c.join('\n') : String(c || '');
      for (const linha of extrairLinhasServidas(ctx, [CAB_ASSUNTO])) {
        injecoes.push({ linha, indiceInjecao: ultimoPedido });
      }
      continue;
    }

    // Canal `subagente`: o prompt (já com a memória) devolvido ao pai.
    if (entrada.toolUseResult && typeof entrada.toolUseResult.prompt === 'string') {
      for (const linha of extrairLinhasServidas(entrada.toolUseResult.prompt, [CAB_ASSUNTO])) {
        doSubagente.push({ linha, agentId: entrada.toolUseResult.agentId || null });
      }
    }

    // Texto: prompts do usuário e entradas de tool_use do assistente.
    if ((entrada.type === 'user' || entrada.type === 'assistant') && entrada.message) {
      const conteudoMsg = entrada.message.content;

      if (typeof conteudoMsg === 'string') {
        // Prompt do usuário digitado direto, sem blocos estruturados.
        partesTexto.push(conteudoMsg);
        if (entrada.type === 'user') ultimoPedido = partesTexto.length - 1;
        continue;
      }

      if (Array.isArray(conteudoMsg)) {
        for (const bloco of conteudoMsg) {
          if (!bloco) continue;
          if (bloco.type === 'tool_result') continue; // nunca é prompt do usuário
          if (entrada.type === 'assistant' && bloco.type === 'text') continue;
          if (bloco.type === 'text' && typeof bloco.text === 'string') {
            partesTexto.push(bloco.text);
            if (entrada.type === 'user') ultimoPedido = partesTexto.length - 1;
          } else if (bloco.type === 'tool_use' && bloco.input !== undefined) {
            try {
              partesTexto.push(JSON.stringify(bloco.input));
            } catch (e) {
              // input não serializável (raro/circular) — ignora esse bloco.
            }
          }
        }
      }
    }
  }

  const texto = partesTexto.join('\n');
  const servidasCanal = servidas.map((linha) => ({ linha, canal: 'abertura', texto }));

  for (const { linha, indiceInjecao } of injecoes) {
    // D8: o pedido que disparou a injeção não pontua a própria injeção.
    const textoPosterior = partesTexto.slice(indiceInjecao + 1).join('\n');
    servidasCanal.push({ linha, canal: 'pedido', texto: textoPosterior });
  }

  // Subagente: texto = tool_use do transcrito do filho; o briefing não conta.
  const dirFilhos = path.join(path.dirname(caminhoTranscrito), path.basename(caminhoTranscrito, '.jsonl'), 'subagents');
  const vistos = new Set();
  for (const { linha, agentId } of doSubagente) {
    const filho = agentId ? lerTranscritoFilho(path.join(dirFilhos, `agent-${agentId}.jsonl`)) : null;
    if (agentId) vistos.add(agentId);
    servidasCanal.push({ linha, canal: 'subagente', texto: filho ? filho.textoTools : '' });
  }
  let arquivosFilhos = [];
  try {
    arquivosFilhos = fs.readdirSync(dirFilhos).filter((f) => /^agent-.+\.jsonl$/.test(f));
  } catch (e) {
    // sem diretório de subagentes: nada a ler
  }
  for (const arq of arquivosFilhos) {
    const agentId = arq.replace(/^agent-/, '').replace(/\.jsonl$/, '');
    if (vistos.has(agentId)) continue; // o pai já trouxe o bloco deste filho
    const filho = lerTranscritoFilho(path.join(dirFilhos, arq));
    if (!filho) continue;
    for (const linha of extrairLinhasServidas(filho.briefing, [CAB_ASSUNTO])) {
      servidasCanal.push({ linha, canal: 'subagente', texto: filho.textoTools });
    }
  }

  return { servidas: servidasCanal.map((s) => s.linha), servidasCanal, texto };
}

// ---- Tarefa 2: pontuação ----

// Sobe a árvore de diretórios procurando `.git` — MESMO algoritmo de
// `encontrarGit()` em scripts/memoria.cjs (exportada de lá pela Tarefa 9,
// mas duplicada aqui em vez de importada: mesmo motivo do require circular
// explicado no topo do arquivo. Não é de 1 linha como `chaveHarness`, mas
// ainda é função pura sobre o sistema de arquivos — o custo de duplicar é
// menor que o de amarrar a ordem de carga dos dois módulos).
function encontrarGitLocal(inicio) {
  let atual = path.resolve(inicio);
  const raizVolume = path.parse(atual).root;
  while (atual !== raizVolume) {
    const gitPath = path.join(atual, '.git');
    try {
      const stats = fs.statSync(gitPath);
      if (stats.isFile() || stats.isDirectory()) return atual;
    } catch (e) {
      // .git não existe neste diretório, sobe mais um nível
    }
    atual = path.dirname(atual);
  }
  return null;
}

/**
 * Lê o `cwd` gravado nas entradas do transcrito e deriva as duas formas sob
 * as quais uma observação pode estar gravada em `projeto` — a chave do
 * harness (`C--Projetos-rainforest-mind`) e o nome curto (`rainforest-mind`)
 * — o mesmo par que `resolverCaminhos()` de scripts/memoria.cjs monta a
 * partir do `.git` mais próximo. Deriva do `cwd` em vez de chamar
 * `resolverCaminhos()` porque a sessão de origem pode ter rodado num `cwd`
 * diferente do processo atual (a pontuação roda na manutenção, dias depois).
 *
 * Tarefa 9 (D8): sobe do `cwd` até o `.git` mais próximo, exatamente como a
 * abertura resolve o projeto — um `cwd` de sessão numa subpasta do
 * repositório (ex.: `<raiz>/scripts`) tem que resolver para o MESMO projeto
 * que a raiz, não para "scripts". Sem `.git` encontrado (worktree removido),
 * cai no `cwd` cru, como antes.
 *
 * @param {string} caminhoTranscrito
 * @returns {{harnessKey: string|null, curto: string|null}}
 */
function lerProjetoDoTranscrito(caminhoTranscrito) {
  try {
    const conteudo = fs.readFileSync(caminhoTranscrito, 'utf8');
    const linhas = conteudo.split('\n');
    for (const linha of linhas) {
      if (!linha.trim()) continue;
      let entrada;
      try {
        entrada = JSON.parse(linha);
      } catch (e) {
        continue;
      }
      if (entrada.cwd) {
        const cwd = String(entrada.cwd);
        const topLevel = encontrarGitLocal(cwd);
        const base = topLevel || cwd; // .git não encontrado -> cwd cru, como antes
        const curto = path.basename(base);
        const harnessKey = base.replace(/[\\/:]/g, '-');
        return { harnessKey, curto };
      }
    }
  } catch (e) {
    // banco/arquivo ilegível — degrada para "sem apelido conhecido"
  }
  return { harnessKey: null, curto: null };
}

/**
 * Envolve um resumo como pseudo-observação, exatamente como
 * hooks/memoria-session-start.cjs faz em `buscarResumosRecentes` — é preciso
 * reproduzir essa formatação para que `formatarObservacao` produza a MESMA
 * linha que a abertura injetou, e a linha servida encontre seu par.
 */
function resumoComoPseudoObservacao(row) {
  return {
    projeto: row.projeto,
    conteudo: `## [resumo até ${(row.criada_em || '').split('T')[0]}]\n\n${row.titulo}\n\n${row.conteudo}`,
    criada_em: row.criada_em,
  };
}

/**
 * Acha a observação ou resumo (vivos, mesmo dia) cuja formatação
 * (`formatarObservacao`) é IGUAL à linha servida — a mesma igualdade que a
 * abertura usou para desenhar essa linha. Sem par, devolve `null`: nunca
 * inventa id (Tarefa 2).
 *
 * @param {object} conexao conexão de banco já aberta
 * @param {string} linhaServida
 * @param {object|null} apelidos mapa chave-do-banco -> nome curto
 * @returns {{origem: 'observacao'|'resumo', id: number, conteudo: string}|null}
 */
function acharAlvo(conexao, linhaServida, apelidos) {
  const m = /^\[(\d{4}-\d{2}-\d{2})(?: \(([^)]*)\))?\]/.exec(linhaServida);
  if (!m) return null;
  // A linha mostra a data LOCAL (#408) e o banco guarda `criada_em` em UTC: a
  // data UTC pode ser a da linha ou a de um dia vizinho. Busca os três dias; a
  // comparação exata com `formatarObservacao` abaixo é que decide o par.
  const dia = Date.parse(`${m[1]}T00:00:00Z`);
  const likes = [-1, 0, 1].map((d) => `${new Date(dia + d * 86400000).toISOString().slice(0, 10)}%`);
  const doDia = (sql) => {
    const linhas = [];
    for (const like of likes) {
      try {
        linhas.push(...conexao.prepare(sql).all(like));
      } catch (e) {
        // tabela ausente ou banco degradado: sem candidatas deste dia
      }
    }
    return linhas;
  };

  const obsRows = doDia(SQL_OBS_DO_DIA);
  for (const row of obsRows) {
    if (formatarObservacao(row, apelidos) === linhaServida) {
      return { origem: 'observacao', id: row.id, conteudo: row.conteudo };
    }
  }

  const resumoRows = doDia(`SELECT id, projeto, titulo, conteudo, criada_em FROM resumos WHERE criada_em LIKE ?`);
  for (const row of resumoRows) {
    const pseudo = resumoComoPseudoObservacao(row);
    if (formatarObservacao(pseudo, apelidos) === linhaServida) {
      return { origem: 'resumo', id: row.id, conteudo: pseudo.conteudo };
    }
  }

  return null;
}

// Document frequency de um termo no observacoes_fts: quantas observações o
// contêm. Degrada para `null` em erro de sintaxe FTS5 — termo então não
// contribui nem a favor nem contra a nota (ver calcularNota).
function contarDocumentFrequency(conexao, termo) {
  try {
    const query = `"${termo.replace(/"/g, '""')}"`;
    const row = conexao.prepare(`SELECT COUNT(*) c FROM observacoes_fts WHERE observacoes_fts MATCH ?`).get(query);
    return row ? row.c : null;
  } catch (e) {
    return null;
  }
}

/**
 * Nota = fração dos termos RAROS do conteúdo presentes no texto da sessão
 * (D5). Termo raro = frequência de documento no `observacoes_fts` menor ou
 * igual a LIMIAR_DF. Observação sem termo raro nenhum pontua 0 — não há como
 * ela ter "casado" com o que a sessão fez.
 *
 * A presença é checada contra um CONJUNTO de tokens do texto da sessão
 * (mesmo tokenizador — letra/dígito Unicode, minúsculas), não por
 * `String.includes`: substring casaria "e" dentro de "sessao", inflando a
 * nota com termo nenhum de verdade presente.
 *
 * @param {object} conexao
 * @param {string} conteudo conteúdo da observação/resumo sendo pontuada
 * @param {string} texto texto da sessão (extrairSessao().texto)
 * @returns {number} nota entre 0 e 1
 */
function calcularNota(conexao, conteudo, texto) {
  const termos = Array.from(
    new Set((String(conteudo || '').match(/[\p{L}\p{N}]+/gu) || []).map((t) => t.toLowerCase()))
  );
  if (termos.length === 0) return 0;

  const tokensTexto = new Set((String(texto || '').match(/[\p{L}\p{N}]+/gu) || []).map((t) => t.toLowerCase()));

  let rarosTotal = 0;
  let rarosPresentes = 0;

  for (const termo of termos) {
    const df = contarDocumentFrequency(conexao, termo);
    if (df === null) continue; // não deu para medir — não conta a favor nem contra
    const raro = df <= LIMIAR_DF;
    if (!raro) continue;
    rarosTotal++;
    if (tokensTexto.has(termo)) rarosPresentes++;
  }

  if (rarosTotal === 0) return 0;
  return rarosPresentes / rarosTotal;
}

// Query MATCH do FTS5 a partir de texto livre — tokeniza por letra/dígito
// Unicode e cita cada termo (evita quebrar a sintaxe do FTS5 com pontuação).
// `limiteTermos` corta o texto de sessão (pode ser grande) para não montar
// uma query com milhares de termos.
function construirQueryFts5DoTexto(texto, limiteTermos) {
  const brutos = String(texto || '').match(/[\p{L}\p{N}]+/gu) || [];
  const unicos = Array.from(new Set(brutos.map((t) => t.toLowerCase()))).filter((t) => t.length > 0);
  const tokens = limiteTermos ? unicos.slice(0, limiteTermos) : unicos;
  if (tokens.length === 0) return null;
  return tokens.map((t) => `"${t.replace(/"/g, '""')}"`).join(' OR ');
}

// Corta o prefixo `[AAAA-MM-DD (projeto)] ` de uma linha formatada, deixando
// só "título — subtítulo" (Tarefa 9, D8). Defesa independente do rótulo: duas
// linhas com o mesmo título/subtítulo são a MESMA observação/resumo, ainda
// que o prefixo de data/projeto não bata (rótulo de projeto que não casou —
// ver lerProjetoDoTranscrito acima).
function semPrefixo(linha) {
  return String(linha || '').replace(/^\[[^\]]*\]\s*/, '');
}

/**
 * Contrafactual (D6): até TETO_CONTRAFACTUAL observações que o FTS acha a
 * partir dos termos do texto da sessão (bm25), excluindo as já servidas
 * (`jaServidos`, um Set de `"observacao:<id>"`).
 *
 * Tarefa 9 (D8): uma servida sem id casado (rótulo de projeto que não bateu)
 * não fica de fora de `jaServidos` — sem a segunda defesa abaixo, ela podia
 * reaparecer aqui como "não-servida" (servida=0), quando na verdade FOI
 * servida. `textosServidos` é o Set de `semPrefixo(linha)` de toda servida da
 * sessão (casada por id ou não); um candidato cujo texto formatado, sem o
 * prefixo de data/projeto, bate com alguma delas é descartado.
 */
function buscarContrafactual(conexao, texto, jaServidos, textosServidos) {
  const query = construirQueryFts5DoTexto(texto, 200);
  if (!query) return [];

  let rows = [];
  try {
    rows = conexao
      .prepare(
        `SELECT o.id, o.conteudo, o.projeto, o.criada_em
         FROM observacoes_fts
         JOIN observacoes o ON o.id = observacoes_fts.rowid
         WHERE observacoes_fts MATCH ? AND o.substituida_por IS NULL
         ORDER BY bm25(observacoes_fts)
         LIMIT ${TETO_CONTRAFACTUAL}`
      )
      .all(query);
  } catch (e) {
    rows = [];
  }

  const resultado = [];
  for (const row of rows) {
    const chave = `observacao:${row.id}`;
    if (jaServidos.has(chave)) continue;
    const linhaCandidato = formatarObservacao(
      { conteudo: row.conteudo, projeto: row.projeto, criada_em: row.criada_em },
      null
    );
    if (textosServidos.has(semPrefixo(linhaCandidato))) continue;
    resultado.push({ origem: 'observacao', id: row.id, conteudo: row.conteudo });
  }
  return resultado;
}

// Buscas ativas (D9): conta os tool_use cujo input contém `memoria.cjs buscar`
// no transcrito principal e, somados, nos subagents/*.jsonl da sessão. Só
// inteiros saem daqui (D10).
const PADRAO_BUSCA = 'memoria.cjs buscar';
function contarBuscasArquivo(arquivo) {
  let conteudo;
  try {
    conteudo = fs.readFileSync(arquivo, 'utf8');
  } catch (e) {
    return 0;
  }
  let n = 0;
  for (const l of conteudo.split('\n')) {
    if (!l.trim()) continue;
    let e;
    try {
      e = JSON.parse(l);
    } catch (err) {
      continue;
    }
    const c = e.message && e.message.content;
    if (e.type !== 'assistant' || !Array.isArray(c)) continue;
    for (const b of c) {
      if (b && b.type === 'tool_use' && b.input !== undefined && JSON.stringify(b.input).includes(PADRAO_BUSCA)) n++;
    }
  }
  return n;
}
function contarBuscas(caminhoTranscrito) {
  const dir = path.join(path.dirname(caminhoTranscrito), path.basename(caminhoTranscrito, '.jsonl'), 'subagents');
  let filhos = [];
  try {
    filhos = fs.readdirSync(dir).filter((f) => /^agent-.+\.jsonl$/.test(f));
  } catch (e) {
    // sem subagents
  }
  let buscasSubagente = 0;
  for (const f of filhos) buscasSubagente += contarBuscasArquivo(path.join(dir, f));
  return { buscasPrincipal: contarBuscasArquivo(caminhoTranscrito), buscasSubagente, subagentes: filhos.length };
}

// Grava (ou substitui) uma linha de uso — idempotente via INSERT OR REPLACE
// sobre UNIQUE(origem, ref_id, sessao) (Tarefa 2).
function gravarUso(conexao, { origem, refId, sessao, servida, nota, pontuadaEm, canal = 'abertura' }) {
  conexao
    .prepare(
      `INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em, canal)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
    .run(origem, refId, sessao, servida, nota, pontuadaEm, canal);
}

/**
 * Pontua uma sessão: mapeia as servidas a id (D3/D8), grava nota crua (D5),
 * grava o contrafactual (D6), e marca a sessão em `uso_memoria_sessoes`.
 * Idempotente — pode rodar mais de uma vez sobre a mesma sessão sem duplicar
 * linha (UNIQUE trata isso) nem mudar a contagem final.
 *
 * Tarefa 11 (D7, D9): todas as escritas da sessão (servidas + contrafactual +
 * a marca em uso_memoria_sessoes) ficam dentro de UMA transação
 * (`BEGIN IMMEDIATE` … `COMMIT`) — sem ela, um transcrito que faz o laço
 * lançar no meio grava só as primeiras linhas do contrafactual antes de
 * relançar, e esse contrafactual truncado só PERDE candidatos (nunca
 * inventa), o que empurra a régua D9 sempre para "recência basta". Qualquer
 * erro faz `ROLLBACK` e relança — nenhuma linha parcial fica em
 * `uso_memoria`. `BEGIN IMMEDIATE` (em vez de `BEGIN TRANSACTION`, que é
 * DEFERRED e só pega o lock de escrita na primeira escrita de fato) pega o
 * lock de escrita já na abertura — é o que faz uma segunda conexão que
 * também tenta `BEGIN IMMEDIATE` no mesmo arquivo falhar imediatamente com
 * "database is locked" em vez de esperar ou intercalar escrita.
 *
 * @param {object} conexao conexão de banco já aberta (leitura E escrita)
 * @param {string} sessao id da sessão
 * @param {string} caminhoTranscrito
 * @returns {{servidasComId: number, servidasSemId: number, contrafactuais: number}}
 */
function pontuarSessao(conexao, sessao, caminhoTranscrito) {
  const agora = new Date().toISOString();
  const { servidasCanal, texto } = extrairSessao(caminhoTranscrito);
  // Mesma memória por dois canais: grava uma vez, abertura > pedido > subagente.
  const servidas = servidasCanal.slice().sort((a, b) => ORDEM_CANAL[a.canal] - ORDEM_CANAL[b.canal]);
  const { harnessKey, curto } = lerProjetoDoTranscrito(caminhoTranscrito);
  const apelidos = harnessKey && curto && harnessKey !== curto ? { [harnessKey]: curto } : null;

  conexao.exec('BEGIN IMMEDIATE');
  try {
    const jaGravados = new Set();
    const textosServidos = new Set(servidas.map((s) => semPrefixo(s.linha)));
    let servidasComId = 0;
    let servidasSemId = 0;

    for (const { linha, canal, texto: textoServida } of servidas) {
      const alvo = acharAlvo(conexao, linha, apelidos);
      if (!alvo) {
        servidasSemId++;
        continue;
      }
      const chave = `${alvo.origem}:${alvo.id}`;
      if (jaGravados.has(chave)) continue; // linha duplicada no bloco — grava uma vez
      jaGravados.add(chave);
      const nota = calcularNota(conexao, alvo.conteudo, textoServida);
      gravarUso(conexao, { origem: alvo.origem, refId: alvo.id, sessao, servida: 1, nota, pontuadaEm: agora, canal });
      servidasComId++;
    }

    const contrafactuais = buscarContrafactual(conexao, texto, jaGravados, textosServidos);
    for (const cand of contrafactuais) {
      const nota = calcularNota(conexao, cand.conteudo, texto);
      gravarUso(conexao, { origem: cand.origem, refId: cand.id, sessao, servida: 0, nota, pontuadaEm: agora });
    }

    const b = contarBuscas(caminhoTranscrito);
    conexao
      .prepare(
        `INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em, buscas_principal, buscas_subagente, subagentes)
         VALUES (?, ?, ?, ?, ?)`
      )
      .run(sessao, agora, b.buscasPrincipal, b.buscasSubagente, b.subagentes);

    conexao.exec('COMMIT');
    return { servidasComId, servidasSemId, contrafactuais: contrafactuais.length };
  } catch (e) {
    try {
      conexao.exec('ROLLBACK');
    } catch (e2) {
      // rollback pode falhar se a transação já não existe mais (ex.: o
      // próprio BEGIN IMMEDIATE lançou por banco ocupado) — o erro original
      // é o que importa, relançado abaixo de qualquer forma.
    }
    throw e;
  }
}

// ---- Tarefa 3: manutenção ----

// Teto por passada de pontuarSessoesPendentes (Tarefa 7, D7): mesmo padrão
// do TETO_RECONCILIAR (scripts/memoria.cjs) — cada passada de manutenção
// processa no máximo isto de sessões COM transcrito, as mais antigas
// primeiro; o resto fica para a passada seguinte. Sessão sem transcrito
// nunca conta no teto (marcar sem pontuar é barato, não precisa esperar).
const TETO_PONTUAR = 30;

// Marca uma sessão em uso_memoria_sessoes sem gravar pontuação nenhuma
// (Tarefa 10, D7) — usada tanto para sessão sem transcrito (semTranscrito,
// acima) quanto para sessão cujo pontuarSessao lançou (catch, abaixo). Sem a
// marca, a fila ordenada da mais antiga devolve a MESMA sessão quebrada ao
// lote para sempre e, acumulado, trava a fila inteira.
function marcarSessao(conexao, sessao, pontuadaEm) {
  conexao
    .prepare(`INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)`)
    .run(sessao, pontuadaEm);
}

// Tarefa 11 (D7, D9): distingue falha TRANSITÓRIA de banco ocupado (outra
// conexão — ex.: `memoria-marca.cjs` gravando a marca d'água de outra
// sessão, a cada Stop/SessionEnd — segurando o lock de escrita no mesmo
// rainforest.db) de falha de verdade no transcrito (Tarefa 10). A primeira
// NUNCA marca a sessão: marcar uma sessão que só não pontuou porque o banco
// estava ocupado no momento errado a tiraria da fila para sempre, mesmo que
// o transcrito seja perfeitamente legível. `node:sqlite` reporta essa falha
// com `code === 'ERR_SQLITE_ERROR'` e mensagem contendo "database is locked"
// ou "database is busy" (SQLITE_BUSY/SQLITE_BUSY_SNAPSHOT).
function ehBancoOcupado(e) {
  return Boolean(e) && e.code === 'ERR_SQLITE_ERROR' && /database is (locked|busy)/.test(String(e.message || ''));
}

/**
 * Pontua toda sessão da `marca_dagua` sem linha em `uso_memoria_sessoes`
 * (D7), até TETO_PONTUAR sessões COM transcrito por passada (Tarefa 7), as
 * mais antigas primeiro (ordem por `processada_em`). Transcrito ainda
 * existente: pontua e marca. Transcrito ausente: marca a sessão sem nota
 * nenhuma (nunca reprocessa a mesma sessão morta todo dia) e segue — uma
 * sessão problemática nunca trava as demais, e não conta no teto. Sessão cujo
 * `pontuarSessao` lança (Tarefa 10) também é marcada, pelo mesmo motivo.
 *
 * Tarefa 11 (D7, D9): banco ocupado (`ehBancoOcupado`) é diferente — não
 * marca a sessão (ela volta inteira à próxima passada) e INTERROMPE a
 * passada nesse ponto (`break`): o banco está ocupado agora, não só para
 * esta sessão, então tentar a próxima do lote só acumularia mais falha
 * transitória.
 *
 * @param {object} conexao conexão de banco já aberta
 * @returns {{pontuadas: number, semTranscrito: number, servidasSemId: number, falharam: number, adiadas: number, pendentesParaProxima: number, total: number}}
 */
function pontuarSessoesPendentes(conexao) {
  const agora = new Date().toISOString();
  const pendentes = conexao
    .prepare(
      `SELECT m.sessao AS sessao, m.arquivo AS arquivo
       FROM marca_dagua m
       LEFT JOIN uso_memoria_sessoes u ON u.sessao = m.sessao
       WHERE u.sessao IS NULL
       ORDER BY m.processada_em ASC`
    )
    .all();

  let semTranscrito = 0;
  const comTranscrito = [];

  for (const { sessao, arquivo } of pendentes) {
    if (!arquivo || !fs.existsSync(arquivo)) {
      semTranscrito++;
      conexao
        .prepare(`INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)`)
        .run(sessao, agora);
      continue;
    }
    comTranscrito.push({ sessao, arquivo });
  }

  const lote = comTranscrito.slice(0, TETO_PONTUAR);
  const pendentesParaProxima = comTranscrito.length - lote.length;

  let pontuadas = 0;
  let servidasSemId = 0;
  let falharam = 0;
  let adiadas = 0;

  for (const { sessao, arquivo } of lote) {
    try {
      const resultado = pontuarSessao(conexao, sessao, arquivo);
      pontuadas++;
      servidasSemId += resultado.servidasSemId;
    } catch (e) {
      if (ehBancoOcupado(e)) { adiadas++; break; }
      // Tarefa 10 (D7): transcrito ilegível não trava as demais — MAS marca,
      // para não voltar ao lote para sempre (a fila é ordenada da mais
      // antiga; sem marca, a mesma sessão quebrada seria a primeira de toda
      // passada seguinte, e nunca deixaria a fila andar).
      marcarSessao(conexao, sessao, agora); falharam++;
    }
  }

  return { pontuadas, semTranscrito, servidasSemId, falharam, adiadas, pendentesParaProxima, total: pendentes.length };
}

// ---- Tarefa 4: relatório (régua D9) ----

function idadeEmDias(conexao, origem, refId) {
  try {
    const tabela = origem === 'resumo' ? 'resumos' : 'observacoes';
    const row = conexao.prepare(`SELECT criada_em FROM ${tabela} WHERE id = ?`).get(refId);
    if (!row || !row.criada_em) return null;
    const dias = Math.floor((Date.now() - new Date(row.criada_em).getTime()) / 86400000);
    return Number.isFinite(dias) ? dias : null;
  } catch (e) {
    return null;
  }
}

/**
 * Relatório da régua D9: lê só `uso_memoria` e `uso_memoria_sessoes` (nunca
 * texto de sessão — D10; `criada_em` de observações/resumos entra só para
 * calcular a idade da linha, nunca o `conteudo`), e decide se liga o
 * ranking. Não altera seleção nenhuma (D2).
 *
 * Tarefa 8 (D9): sessão sem nenhuma linha `servida = 1` (sem transcrito, ou
 * com transcrito mas nada casou) não tem como "perder" nada para a
 * recência — contá-la no denominador empurra a régua para "não liga" sem
 * dado nenhum. Só entra no denominador quem tem ao menos uma servida.
 *
 * @param {object} conexao conexão de banco já aberta (leitura basta)
 * @returns {string} relatório pronto para imprimir
 */
// Régua D7 (memória por assunto): o canal do assunto FICA só se as duas
// condições valem — fração de sessões com servida útil >= util E fração de
// sessões com perda <= perda.
const REGUA_D7 = { util: 0.4, perda: 1 / 3 };
const BASE_D7 = { dia: '2026-10-08', util: '27%', perdas: '171 de 255' };
const NOTA_UTIL = 0.5;

function gerarRelatorio(conexao) {
  let sessoes = [];
  try {
    sessoes = conexao.prepare(`SELECT sessao, pontuada_em FROM uso_memoria_sessoes ORDER BY pontuada_em ASC`).all();
  } catch (e) {
    return 'nenhuma sessão pontuada ainda (uso_memoria_sessoes não existe — rode `manutencao` ao menos uma vez)';
  }
  if (sessoes.length === 0) return 'nenhuma sessão pontuada ainda';

  const temServida = new Set(
    conexao.prepare(`SELECT DISTINCT sessao FROM uso_memoria WHERE servida = 1`).all().map((r) => r.sessao)
  );
  const sessoesComServida = sessoes.filter((s) => temServida.has(s.sessao));
  const semServida = sessoes.length - sessoesComServida.length;

  const total = sessoesComServida.length;
  if (total === 0) {
    return `${semServida} sessão(ões) sem servida fora da conta\nnenhuma sessão com servida para medir a régua D9`;
  }

  const linhas = [];
  linhas.push(`sessões pontuadas: ${sessoes.length}`);
  linhas.push(`período: ${sessoes[0].pontuada_em} a ${sessoes[sessoes.length - 1].pontuada_em}`);
  if (semServida > 0) {
    linhas.push(`${semServida} sessão(ões) sem servida fora da conta`);
  }

  let sessoesComPerda = 0;
  const comPerda = new Set();
  const naoServidasComPerda = [];

  for (const { sessao } of sessoesComServida) {
    const melhorRow = conexao.prepare(`SELECT MAX(nota) n FROM uso_memoria WHERE sessao = ? AND servida = 1`).get(sessao);
    const melhorNota = melhorRow && melhorRow.n != null ? melhorRow.n : 0;

    const naoServidas = conexao
      .prepare(
        `SELECT origem, ref_id, nota FROM uso_memoria
         WHERE sessao = ? AND servida = 0 AND nota > ?
         ORDER BY nota DESC`
      )
      .all(sessao, melhorNota);

    if (naoServidas.length > 0) {
      sessoesComPerda++;
      comPerda.add(sessao);
      for (const linha of naoServidas) {
        naoServidasComPerda.push({ sessao, origem: linha.origem, refId: linha.ref_id, nota: linha.nota });
      }
    }
  }

  linhas.push(`sessões com perda (não-servida pontuou acima da melhor servida): ${sessoesComPerda} de ${total}`);

  const top5 = naoServidasComPerda.sort((a, b) => b.nota - a.nota).slice(0, 5);
  if (top5.length > 0) {
    linhas.push('não-servidas que a recência perdeu:');
    for (const item of top5) {
      const dias = idadeEmDias(conexao, item.origem, item.refId);
      const idadeTxt = dias === null ? '?' : `${dias}d`;
      linhas.push(`  ${item.origem} #${item.refId} nota=${item.nota.toFixed(2)} idade=${idadeTxt} (sessão ${item.sessao})`);
    }
  }

  // A comparação exata da régua D9 — "pelo menos 1/3" inclui o empate.
  const liga = sessoesComPerda * 3 >= total;

  linhas.push(
    liga
      ? `régua D9: LIGA o ranking (${sessoesComPerda} de ${total} sessões)`
      : `régua D9: NÃO liga — recência basta (${sessoesComPerda} de ${total} sessões)`
  );

  // Banco que ainda não passou pela manutenção não tem a coluna canal: avisa e
  // fica na régua D9, em vez de morrer no meio do relatório.
  const temCanal = conexao.prepare('PRAGMA table_info(uso_memoria)').all().some((c) => c.name === 'canal');
  if (!temCanal) {
    linhas.push('régua D7: sem dado — banco ainda não migrado (rode `node scripts/memoria.cjs manutencao`)');
    return linhas.join('\n');
  }

  // Por canal: sessões com ao menos uma servida do canal (Y) e, dentre elas,
  // as com servida útil (nota >= NOTA_UTIL).
  for (const canal of ['abertura', 'pedido', 'subagente']) {
    const r = conexao
      .prepare(
        `SELECT COUNT(DISTINCT sessao) y,
                COUNT(DISTINCT CASE WHEN nota >= ? THEN sessao END) x
         FROM uso_memoria WHERE servida = 1 AND canal = ?`
      )
      .get(NOTA_UTIL, canal);
    const pct = r.y > 0 ? Math.round((100 * r.x) / r.y) : 0;
    linhas.push(`canal ${canal}: sessões com servida útil ${r.x} de ${r.y} (${pct}%)`);
  }

  // Buscas ativas (colunas podem faltar em banco antigo que ainda não migrou).
  try {
    const b = conexao
      .prepare(
        `SELECT COUNT(buscas_principal) medidas,
                COALESCE(SUM(buscas_principal > 0), 0) a,
                COALESCE(SUM(subagentes > 0), 0) d,
                COALESCE(SUM(buscas_subagente > 0), 0) c
         FROM uso_memoria_sessoes`
      )
      .get();
    linhas.push(
      `buscas ativas: ${b.a} sessão(ões) principal(is) de ${b.medidas}, ${b.c} subagente(s) de ${b.d} (subagente aproximado por sessão: as contagens são por sessão)`
    );
  } catch (e) {
    linhas.push('buscas ativas: sem dado (colunas ausentes — rode `manutencao` para migrar)');
  }

  // Janela da régua D7: só sessões pontuadas desde a primeira servida do canal
  // novo — sem ela, o histórico anterior ao canal dilui (ou decide) o número.
  const inicio = conexao
    .prepare(`SELECT MIN(pontuada_em) m FROM uso_memoria WHERE servida = 1 AND canal IN ('pedido', 'subagente')`)
    .get().m;
  if (!inicio) {
    linhas.push('régua D7: sem dado do canal do assunto (nenhuma sessão serviu memória pelo pedido ou pelo subagente)');
    return linhas.join('\n');
  }
  const janela = sessoesComServida.filter((s) => s.pontuada_em >= inicio).map((s) => s.sessao);
  const totalJanela = janela.length;
  const utilNaSessao = conexao.prepare(`SELECT 1 FROM uso_memoria WHERE sessao = ? AND servida = 1 AND nota >= ? LIMIT 1`);
  const comUtil = janela.filter((s) => utilNaSessao.get(s, NOTA_UTIL)).length;
  const perdaJanela = janela.filter((s) => comPerda.has(s)).length;
  const fracaoUtil = comUtil / totalJanela;
  const fracaoPerda = perdaJanela / totalJanela;
  linhas.push(`janela da régua D7: ${totalJanela} sessão(ões) com servida desde ${inicio}`);
  linhas.push(
    `sessões com servida útil em qualquer canal: ${comUtil} de ${totalJanela} (${Math.round(fracaoUtil * 100)}%) — base ${BASE_D7.dia}: ${BASE_D7.util} útil`
  );
  linhas.push(
    `sessões com perda: ${perdaJanela} de ${totalJanela} (${Math.round(fracaoPerda * 100)}%) — base ${BASE_D7.dia}: ${BASE_D7.perdas} com perda`
  );

  const fica = fracaoUtil >= REGUA_D7.util && fracaoPerda <= REGUA_D7.perda;
  const zTxt = `${Math.round(fracaoUtil * 100)}%`;
  const pTxt = `${perdaJanela}/${totalJanela}`;
  linhas.push(
    fica
      ? `régua D7: FICA o canal do assunto (útil ${zTxt} ≥ 40%, perdas ${pTxt} ≤ 1/3)`
      : `régua D7: SAI o canal do assunto (útil ${zTxt}, perdas ${pTxt})`
  );

  return linhas.join('\n');
}

module.exports = {
  LIMIAR_DF,
  TETO_CONTRAFACTUAL,
  TETO_PONTUAR,
  extrairLinhasServidas,
  extrairSessao,
  lerProjetoDoTranscrito,
  acharAlvo,
  contarDocumentFrequency,
  calcularNota,
  construirQueryFts5DoTexto,
  buscarContrafactual,
  pontuarSessao,
  pontuarSessoesPendentes,
  idadeEmDias,
  gerarRelatorio,
  contarBuscas,
  REGUA_D7,
};
