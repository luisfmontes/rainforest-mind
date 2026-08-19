#!/usr/bin/env node
/**
 * Passada de LLM: transforma trecho de transcrito em observação gravada.
 *
 * Responsabilidade (tarefa 12): ler trecho do transcrito a partir do offset
 * da marca d'água, resumir via LLM, gravar observação com `projeto` preenchido.
 *
 * Decisão crítica (D12, D14): a passada roda FORA de qualquer hook de
 * UserPromptSubmit ou PostToolUse — sob demanda ou no SessionEnd. A marca
 * d'água não avança enquanto a observação não estiver gravada, para permitir
 * recuperação em caso de falha da LLM.
 *
 * Uso:
 *   node scripts/observar.cjs [--sessao <id>] [--projeto <nome>]
 *
 * Se --sessao não for informado, processa a marca mais recente não-processada.
 * Retorna exit 0 se sucesso, exit 1 se falha crítica (banco, I/O).
 * Se falha apenas a LLM: exit 0, marca intacta, tenta novamente depois.
 *
 * Variáveis de ambiente (testes):
 *   TESTADOR_CHAMAR_LLM: função customizada para chamar LLM (mock/dublê)
 */

const fs = require('fs');
const path = require('path');
const { abrirBanco, criarSchema, resolverCaminhos } = require(
  path.join(__dirname, 'memoria.cjs')
);

// Resolve caminhos da raiz de dados.
function resolverDados() {
  const { raiz, projeto } = resolverCaminhos();
  return {
    raiz,
    caminhoDb: path.join(raiz, 'rainforest.db'),
    projeto,
  };
}

// Lê a marca d'água para uma sessão (ou mais recente se não informada).
function lerMarca(conexao, { sessao, projeto }) {
  try {
    let stmt;
    if (sessao) {
      stmt = conexao.prepare(`
        SELECT * FROM marca_dagua
        WHERE projeto = ? AND sessao = ?
        LIMIT 1
      `);
      const rows = stmt.all(projeto, sessao);
      return rows.length > 0 ? rows[0] : null;
    } else {
      // Mais recente
      stmt = conexao.prepare(`
        SELECT * FROM marca_dagua
        WHERE projeto = ?
        ORDER BY processada_em DESC
        LIMIT 1
      `);
      const rows = stmt.all(projeto);
      return rows.length > 0 ? rows[0] : null;
    }
  } catch (e) {
    console.error(`AVISO: erro ao ler marca d'água: ${e.message}`);
    return null;
  }
}

// Lê trecho do transcrito a partir do offset (em bytes).
// O transcrito é JSONL: uma linha = um evento.
// Retorna array de eventos JSON a partir do offset.
function lerTranscrito(caminhoTranscrito, offsetInicio) {
  try {
    if (!fs.existsSync(caminhoTranscrito)) {
      return [];
    }

    const conteudo = fs.readFileSync(caminhoTranscrito, 'utf8');
    // Extrair texto a partir do offset
    const textoAposOffset = conteudo.substring(offsetInicio);

    // Dividir em linhas e parsear JSON
    const linhas = textoAposOffset.split('\n').filter(l => l.trim());
    const eventos = [];

    for (const linha of linhas) {
      try {
        const evento = JSON.parse(linha);
        eventos.push(evento);
      } catch (e) {
        // Linha malformada, pular
        console.error(`AVISO: linha malformada no transcrito (${e.message})`);
      }
    }

    return eventos;
  } catch (e) {
    console.error(`AVISO: erro ao ler transcrito: ${e.message}`);
    return [];
  }
}

// Formata eventos para passar à LLM.
// Extrai conteúdo relevante de cada evento (prompts, respostas, chamadas de ferramenta).
// Schema real dos transcritos (Claude Code):
//   - type: "user", "assistant", "system", "attachment", "last-prompt", "mode", "permission-mode", etc.
//   - message.content: string (user/system) ou array (assistant: [{type: "text", text: "..."}, {type: "tool_use", ...}])
// Ignorados: "attachment" (ruído de hooks), "system", "last-prompt", "mode", "permission-mode", etc.
function formatarParaLLM(eventos) {
  const resumo = [];

  for (const evento of eventos) {
    // Apenas "user" e "assistant" carregam conteúdo conversacional
    if (evento.type === 'user' && evento.message && evento.message.content) {
      const conteudo = evento.message.content;
      const texto = typeof conteudo === 'string' ? conteudo : '';
      if (texto.trim()) {
        resumo.push(`Prompt: ${texto}`);
      }
    }

    if (evento.type === 'assistant' && evento.message && evento.message.content) {
      const conteudo = evento.message.content;

      if (Array.isArray(conteudo)) {
        // Extrair blocos de texto e chamadas de ferramenta
        for (const bloco of conteudo) {
          if (bloco.type === 'text' && bloco.text) {
            // Truncar respostas muito longas
            const texto = bloco.text;
            const truncado = texto.substring(0, 500) + (texto.length > 500 ? '...' : '');
            resumo.push(`Resposta: ${truncado}`);
          }
          if (bloco.type === 'tool_use' && bloco.name) {
            resumo.push(`Ferramenta: ${bloco.name}`);
          }
        }
      } else if (typeof conteudo === 'string') {
        // Content pode ser string em alguns casos
        const truncado = conteudo.substring(0, 500) + (conteudo.length > 500 ? '...' : '');
        resumo.push(`Resposta: ${truncado}`);
      }
    }
  }

  return resumo.join('\n');
}

// Chamada à LLM isolada atrás de função para permitir mock em testes.
// Retorna promise com observação (string) ou null se falhar.
async function chamarLLM(textoDaPassada) {
  // Permitir mock via variável de ambiente (testes)
  if (process.env.TESTADOR_CHAMAR_LLM) {
    try {
      const modulo = require(process.env.TESTADOR_CHAMAR_LLM);
      const resultado = await modulo.chamarLLM(textoDaPassada);
      return resultado;
    } catch (e) {
      console.error(`AVISO: não consegui carregar mock de LLM: ${e.message}`);
      return null;
    }
  }

  // ====== ESTRUTURA DE CHAMADA ISOLADA ======
  // Este é o ponto que ficará isolado atrás de função quando a credencial chegar.
  //
  // Hoje, retorna null para indicar que LLM não está disponível.
  // Quando a credencial estiver configurada (API key, host), a função
  // será descomentada para fazer a chamada real.
  //
  // Estrutura:
  //   1. Ler credencial de variável de ambiente ou arquivo de config
  //   2. Chamar API da Anthropic (endpoint /messages)
  //   3. Parsear resposta e extrair texto
  //   4. Retornar observação ou null se falhar
  //
  // Exemplo pseudocódigo (descomentado quando credencial chegar):
  //
  // const chave = process.env.ANTHROPIC_API_KEY || readConfigFile('...').apiKey;
  // if (!chave) {
  //   console.error('ERRO: ANTHROPIC_API_KEY não configurada');
  //   return null; // Deixa marca intacta para próxima tentativa
  // }
  //
  // const prompt = `Resuma a seguinte interação em uma observação curta (1-2 frases):\n\n${textoDaPassada}`;
  // try {
  //   const resposta = await fetch('https://api.anthropic.com/v1/messages', {
  //     method: 'POST',
  //     headers: {
  //       'x-api-key': chave,
  //       'content-type': 'application/json',
  //       'anthropic-version': '2023-06-01',
  //     },
  //     body: JSON.stringify({
  //       model: 'claude-opus-4-1-20250805', // ou o modelo atual
  //       max_tokens: 256,
  //       messages: [{ role: 'user', content: prompt }],
  //     }),
  //   });
  //   if (!resposta.ok) {
  //     console.error(`API error: ${resposta.status}`);
  //     return null;
  //   }
  //   const dados = await resposta.json();
  //   const observacao = dados.content?.[0]?.text || null;
  //   return observacao;
  // } catch (e) {
  //   console.error(`Erro ao chamar LLM: ${e.message}`);
  //   return null; // Deixa marca intacta
  // }

  // Por enquanto, simular timeout/indisponibilidade
  console.error('AVISO: LLM não disponível (credencial não configurada)');
  return null;
}

// Grava observação no banco.
// Retorna true se sucesso, false se falha.
function gravarObservacao(conexao, { projeto, conteudo, origem }) {
  try {
    const agora = new Date().toISOString();

    const stmt = conexao.prepare(`
      INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
      VALUES (?, ?, ?, ?)
    `);

    stmt.run(projeto, conteudo, agora, origem || null);
    return true;
  } catch (e) {
    // Erro ao gravar
    console.error(`AVISO: erro ao gravar observação: ${e.message}`);
    return false;
  }
}

// Avança a marca d'água após sucesso na gravação.
// Tarefa 12 (D14): só avança offset_processado depois de gravar com sucesso.
// Retorna true se sucesso, false se falha.
function avancarMarca(conexao, { projeto, sessao, offsetProcessado }) {
  try {
    const stmt = conexao.prepare(`
      UPDATE marca_dagua
      SET offset_processado = ?
      WHERE projeto = ? AND sessao = ?
    `);

    stmt.run(offsetProcessado, projeto, sessao);
    return true;
  } catch (e) {
    console.error(`AVISO: erro ao avançar marca d'água: ${e.message}`);
    return false;
  }
}

// Log para debug (apenas em teste)
function debug(msg) {
  if (process.env.DEBUG_OBSERVADOR) {
    const logMsg = `[DEBUG] ${msg}\n`;
    if (process.env.DEBUG_LOG_FILE) {
      try {
        fs.appendFileSync(process.env.DEBUG_LOG_FILE, logMsg);
      } catch (e) {}
    } else {
      console.error(logMsg.trim());
    }
  }
}

// Função principal: processa sessão e grava observação.
async function processarSessao(sessao, projeto) {
  const dados = resolverDados();

  if (!fs.existsSync(dados.caminhoDb)) {
    console.error(`ERRO: banco não existe em ${dados.caminhoDb}`);
    process.exit(1);
  }

  let conexao;
  try {
    conexao = abrirBanco(dados.caminhoDb);
  } catch (e) {
    console.error(`ERRO: não consegui abrir banco: ${e.message}`);
    process.exit(1);
  }

  try {
    // Ler marca d'água
    const proj = projeto || dados.projeto;
    debug(`Procurando marca: sessao=${sessao}, projeto=${proj}`);
    const marca = lerMarca(conexao, { sessao, projeto: proj });
    debug(`marca encontrada: ${marca ? 'sim' : 'nao'}`);
    if (marca) {
      debug(`  sessao=${marca.sessao}, arquivo=${marca.arquivo}, offset=${marca.offset}`);
    }

    if (!marca) {
      console.log('nenhuma marca dagua encontrada');
      return;
    }

    // Calcular a janela: ler a partir de offset_processado (até onde foi processado).
    // Tarefa 12 (D14): offset_processado é o ponto já processado.
    // marca.offset é offset_visto (tamanho do arquivo no Stop/SessionEnd).
    const offsetProcessado = marca.offset_processado || 0;
    debug(`janela: [${offsetProcessado}, ${marca.offset}]`);

    // Ler transcrito a partir de offset_processado
    const eventos = lerTranscrito(marca.arquivo, offsetProcessado);
    debug(`eventos lidos: ${eventos.length}`);

    if (eventos.length === 0) {
      console.log('nenhum evento novo no transcrito');
      return;
    }

    // Formatar para LLM
    const textoDaPassada = formatarParaLLM(eventos);
    debug(`texto para LLM: ${textoDaPassada.substring(0, 100)}...`);

    // Chamar LLM
    console.log(`processando ${eventos.length} evento(s)...`);
    const observacao = await chamarLLM(textoDaPassada);
    debug(`observacao da LLM: ${observacao ? observacao.substring(0, 50) : 'null'}`);

    if (!observacao) {
      // Falha na LLM — marca intacta, tenta novamente depois
      console.log('LLM retornou null, marca dagua nao avanca');
      return;
    }

    // Gravar observação
    const gravouOk = gravarObservacao(conexao, {
      projeto: marca.projeto,
      conteudo: observacao,
      origem: `sessao:${marca.sessao}`,
    });
    debug(`gravou ok: ${gravouOk}`);

    if (!gravouOk) {
      // Falha ao gravar — marca intacta
      console.log('erro ao gravar observacao, marca dagua nao avanca');
      return;
    }

    // CRÍTICO 3: Só avança offset_processado DEPOIS de gravar com sucesso.
    // Se falhar em qualquer ponto anterior, fica intacto e tenta novamente.
    const avancoOk = avancarMarca(conexao, {
      projeto: marca.projeto,
      sessao: marca.sessao,
      offsetProcessado: marca.offset, // Avança até offset_visto (fim do que foi visto)
    });
    debug(`avanco ok: ${avancoOk}`);

    if (!avancoOk) {
      // Falha ao avançar — aviso, mas observação já foi gravada
      console.log('AVISO: observacao gravada mas offset_processado nao avancou');
      return;
    }

    console.log(`ok: observacao gravada e offset_processado avancado para sessao ${marca.sessao}`);
  } finally {
    conexao.close();
  }
}

// ---- CLI

function main() {
  // Parser simples de argumentos
  function arg(nome) {
    const i = process.argv.indexOf(`--${nome}`);
    if (i === -1 || i + 1 >= process.argv.length) return null;
    return process.argv[i + 1];
  }

  const sessao = arg('sessao');
  const projeto = arg('projeto');

  // Rodar de forma async
  processarSessao(sessao, projeto).catch(e => {
    console.error(`ERRO: ${e.message}`);
    process.exit(1);
  });
}

if (require.main === module) {
  main();
}

module.exports = { processarSessao, chamarLLM };
