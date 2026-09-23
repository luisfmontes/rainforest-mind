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

// ---- Tarefa 1: extrator do transcrito ----

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
function extrairLinhasServidas(additionalContext) {
  const texto = String(additionalContext || '');
  const inicio = texto.indexOf('## Memória (corpus residentes)');
  if (inicio === -1) return [];
  const marcaMais = texto.indexOf('mais:', inicio);
  const fim = marcaMais === -1 ? texto.length : marcaMais;
  const bloco = texto.slice(inicio, fim);
  return bloco
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('['));
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
        for (const linha of extrairLinhasServidas(ctx)) servidas.push(linha);
      }
      continue; // attachment nunca entra no texto (D4)
    }

    // Texto: prompts do usuário e entradas de tool_use do assistente.
    if ((entrada.type === 'user' || entrada.type === 'assistant') && entrada.message) {
      const conteudoMsg = entrada.message.content;

      if (typeof conteudoMsg === 'string') {
        // Prompt do usuário digitado direto, sem blocos estruturados.
        partesTexto.push(conteudoMsg);
        continue;
      }

      if (Array.isArray(conteudoMsg)) {
        for (const bloco of conteudoMsg) {
          if (!bloco) continue;
          if (bloco.type === 'tool_result') continue; // nunca é prompt do usuário
          if (entrada.type === 'assistant' && bloco.type === 'text') continue;
          if (bloco.type === 'text' && typeof bloco.text === 'string') {
            partesTexto.push(bloco.text);
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

  return { servidas, texto: partesTexto.join('\n') };
}

// ---- Tarefa 2: pontuação ----

/**
 * Lê o `cwd` gravado nas entradas do transcrito e deriva as duas formas sob
 * as quais uma observação pode estar gravada em `projeto` — a chave do
 * harness (`C--Projetos-rainforest-mind`) e o nome curto (`rainforest-mind`)
 * — o mesmo par que `resolverCaminhos()` de scripts/memoria.cjs monta a
 * partir do `.git` mais próximo. Deriva do `cwd` em vez de chamar
 * `resolverCaminhos()` porque a sessão de origem pode ter rodado num `cwd`
 * diferente do processo atual (a pontuação roda na manutenção, dias depois).
 *
 * Duplica a transformação de `chaveHarness()` (scripts/memoria.cjs) em vez de
 * importá-la — mesmo motivo do require circular explicado no topo do
 * arquivo: função pura de 1 linha, custo de duplicar é menor que o de um
 * require condicionado à ordem de carga do módulo.
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
        const curto = path.basename(cwd);
        const harnessKey = cwd.replace(/[\\/:]/g, '-');
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
  const data = m[1];
  const like = `${data}%`;

  let obsRows = [];
  try {
    obsRows = conexao
      .prepare(
        `SELECT id, projeto, conteudo, criada_em FROM observacoes
         WHERE criada_em LIKE ? AND substituida_por IS NULL`
      )
      .all(like);
  } catch (e) {
    obsRows = [];
  }
  for (const row of obsRows) {
    if (formatarObservacao(row, apelidos) === linhaServida) {
      return { origem: 'observacao', id: row.id, conteudo: row.conteudo };
    }
  }

  let resumoRows = [];
  try {
    resumoRows = conexao
      .prepare(`SELECT id, projeto, titulo, conteudo, criada_em FROM resumos WHERE criada_em LIKE ?`)
      .all(like);
  } catch (e) {
    resumoRows = [];
  }
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

/**
 * Contrafactual (D6): até TETO_CONTRAFACTUAL observações que o FTS acha a
 * partir dos termos do texto da sessão (bm25), excluindo as já servidas
 * (`jaServidos`, um Set de `"observacao:<id>"`).
 */
function buscarContrafactual(conexao, texto, jaServidos) {
  const query = construirQueryFts5DoTexto(texto, 200);
  if (!query) return [];

  let rows = [];
  try {
    rows = conexao
      .prepare(
        `SELECT o.id, o.conteudo
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
    resultado.push({ origem: 'observacao', id: row.id, conteudo: row.conteudo });
  }
  return resultado;
}

// Grava (ou substitui) uma linha de uso — idempotente via INSERT OR REPLACE
// sobre UNIQUE(origem, ref_id, sessao) (Tarefa 2).
function gravarUso(conexao, { origem, refId, sessao, servida, nota, pontuadaEm }) {
  conexao
    .prepare(
      `INSERT OR REPLACE INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em)
       VALUES (?, ?, ?, ?, ?, ?)`
    )
    .run(origem, refId, sessao, servida, nota, pontuadaEm);
}

/**
 * Pontua uma sessão: mapeia as servidas a id (D3/D8), grava nota crua (D5),
 * grava o contrafactual (D6), e marca a sessão em `uso_memoria_sessoes`.
 * Idempotente — pode rodar mais de uma vez sobre a mesma sessão sem duplicar
 * linha (UNIQUE trata isso) nem mudar a contagem final.
 *
 * @param {object} conexao conexão de banco já aberta (leitura E escrita)
 * @param {string} sessao id da sessão
 * @param {string} caminhoTranscrito
 * @returns {{servidasComId: number, servidasSemId: number, contrafactuais: number}}
 */
function pontuarSessao(conexao, sessao, caminhoTranscrito) {
  const agora = new Date().toISOString();
  const { servidas, texto } = extrairSessao(caminhoTranscrito);
  const { harnessKey, curto } = lerProjetoDoTranscrito(caminhoTranscrito);
  const apelidos = harnessKey && curto && harnessKey !== curto ? { [harnessKey]: curto } : null;

  const jaGravados = new Set();
  let servidasComId = 0;
  let servidasSemId = 0;

  for (const linha of servidas) {
    const alvo = acharAlvo(conexao, linha, apelidos);
    if (!alvo) {
      servidasSemId++;
      continue;
    }
    const chave = `${alvo.origem}:${alvo.id}`;
    if (jaGravados.has(chave)) continue; // linha duplicada no bloco — grava uma vez
    jaGravados.add(chave);
    const nota = calcularNota(conexao, alvo.conteudo, texto);
    gravarUso(conexao, { origem: alvo.origem, refId: alvo.id, sessao, servida: 1, nota, pontuadaEm: agora });
    servidasComId++;
  }

  const contrafactuais = buscarContrafactual(conexao, texto, jaGravados);
  for (const cand of contrafactuais) {
    const nota = calcularNota(conexao, cand.conteudo, texto);
    gravarUso(conexao, { origem: cand.origem, refId: cand.id, sessao, servida: 0, nota, pontuadaEm: agora });
  }

  conexao
    .prepare(`INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)`)
    .run(sessao, agora);

  return { servidasComId, servidasSemId, contrafactuais: contrafactuais.length };
}

// ---- Tarefa 3: manutenção ----

/**
 * Pontua toda sessão da `marca_dagua` sem linha em `uso_memoria_sessoes`
 * (D7). Transcrito ainda existente: pontua e marca. Transcrito ausente: marca
 * a sessão sem nota nenhuma (nunca reprocessa a mesma sessão morta todo dia)
 * e segue — uma sessão problemática nunca trava as demais.
 *
 * @param {object} conexao conexão de banco já aberta
 * @returns {{pontuadas: number, semTranscrito: number, total: number}}
 */
function pontuarSessoesPendentes(conexao) {
  const agora = new Date().toISOString();
  const pendentes = conexao
    .prepare(
      `SELECT m.sessao AS sessao, m.arquivo AS arquivo
       FROM marca_dagua m
       LEFT JOIN uso_memoria_sessoes u ON u.sessao = m.sessao
       WHERE u.sessao IS NULL`
    )
    .all();

  let pontuadas = 0;
  let semTranscrito = 0;

  for (const { sessao, arquivo } of pendentes) {
    if (!arquivo || !fs.existsSync(arquivo)) {
      semTranscrito++;
      conexao
        .prepare(`INSERT OR REPLACE INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?, ?)`)
        .run(sessao, agora);
      continue;
    }
    try {
      pontuarSessao(conexao, sessao, arquivo);
      pontuadas++;
    } catch (e) {
      // uma sessão com transcrito ilegível não trava as demais — nem marca,
      // para que a próxima passada tente de novo.
    }
  }

  return { pontuadas, semTranscrito, total: pendentes.length };
}

module.exports = {
  LIMIAR_DF,
  TETO_CONTRAFACTUAL,
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
};
