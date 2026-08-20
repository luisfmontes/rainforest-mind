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
const { spawn } = require('child_process');
const os = require('os');
const { abrirBanco, criarSchema, resolverCaminhos } = require(
  path.join(__dirname, 'memoria.cjs')
);

// Teto conservador de argumento para CLI claude
// Medição: ENAMETOOLONG ocorre entre 16.908 e 33.708 caracteres
// Usar 16.000 como teto conservador para ficar bem abaixo do limite
const TETO_ARGUMENTO = 16000;

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

// Lê todas as marcas com pendência (offset_visto > offset_processado).
// Usado quando observar.cjs é invocado SEM argumentos (modo produção).
function lerMarcasPendentes(conexao) {
  try {
    const stmt = conexao.prepare(`
      SELECT * FROM marca_dagua
      WHERE offset > COALESCE(offset_processado, 0)
      ORDER BY processada_em DESC
    `);
    return stmt.all();
  } catch (e) {
    console.error(`AVISO: erro ao ler marcas pendentes: ${e.message}`);
    return [];
  }
}

// Lê trecho do transcrito a partir do offset (em bytes).
// O transcrito é JSONL: uma linha = um evento.
// Retorna array de eventos JSON a partir do offset.
// Tarefa 19 (D19): Offset é BYTE de ponta a ponta. Lê usando Buffer.toString(),
// não substring() que trabalha com índices de caracteres.
function lerTranscrito(caminhoTranscrito, offsetInicio) {
  try {
    if (!fs.existsSync(caminhoTranscrito)) {
      return [];
    }

    // Ler arquivo como Buffer para trabalhar com offsets em bytes
    const buffer = fs.readFileSync(caminhoTranscrito);
    // Converter a partir do byte offsetInicio, garantindo UTF-8 válido
    const conteudo = buffer.toString('utf8', offsetInicio);

    // Dividir em linhas e parsear JSON
    const linhas = conteudo.split('\n').filter(l => l.trim());
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

// Lê trecho do transcrito com rastreamento de offset por evento.
// Retorna array de objetos {evento, offsetFim} para fatiamento.
function lerTranscritoComOffsets(caminhoTranscrito, offsetInicio) {
  try {
    if (!fs.existsSync(caminhoTranscrito)) {
      return [];
    }

    // Ler arquivo como Buffer para trabalhar com offsets em bytes
    const buffer = fs.readFileSync(caminhoTranscrito);
    // Converter a partir do byte offsetInicio
    const conteudo = buffer.toString('utf8', offsetInicio);

    // Dividir em linhas
    const linhas = conteudo.split('\n');
    const eventosComOffsets = [];
    let offsetAtual = offsetInicio;

    for (const linha of linhas) {
      if (!linha.trim()) {
        // Linha vazia: avançar offset pelo tamanho em bytes
        const linhaEmBytes = Buffer.byteLength(linha + '\n', 'utf8');
        offsetAtual += linhaEmBytes;
        continue;
      }

      try {
        const evento = JSON.parse(linha);
        // Calcular quantos bytes esta linha ocupa
        const linhaEmBytes = Buffer.byteLength(linha + '\n', 'utf8');
        offsetAtual += linhaEmBytes;
        eventosComOffsets.push({ evento, offsetFim: offsetAtual });
      } catch (e) {
        // Linha malformada: avançar offset mesmo assim
        console.error(`AVISO: linha malformada no transcrito (${e.message})`);
        const linhaEmBytes = Buffer.byteLength(linha + '\n', 'utf8');
        offsetAtual += linhaEmBytes;
      }
    }

    return eventosComOffsets;
  } catch (e) {
    console.error(`AVISO: erro ao ler transcrito com offsets: ${e.message}`);
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

// Acha o executável `claude` varrendo o PATH, sem subir processo para descobrir
// (nada de `where`/`which`: este arquivo existe para tirar spawn do caminho).
// Devolve caminho absoluto ou null. `RFM_CLAUDE_EXECUTAVEL` sobrepõe, para quem
// tem o CLI fora do PATH.
function acharExecutavelClaude() {
  if (process.env.RFM_CLAUDE_EXECUTAVEL) {
    return process.env.RFM_CLAUDE_EXECUTAVEL;
  }
  const ehWindows = process.platform === 'win32';
  const separador = ehWindows ? ';' : ':';
  const extensoes = ehWindows
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';').map((e) => e.toLowerCase())
    : [''];
  for (const dir of (process.env.PATH || '').split(separador)) {
    if (!dir) continue;
    for (const ext of extensoes) {
      const alvo = path.join(dir, `claude${ext}`);
      try {
        if (fs.statSync(alvo).isFile()) {
          if (!ehWindows) fs.accessSync(alvo, fs.constants.X_OK);
          return alvo;
        }
      } catch {
        // Caminho inexistente ou sem permissão: segue procurando.
      }
    }
  }
  return null;
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

  // Invocar CLI claude com spawn, de um diretório neutro (D6): o transcrito é
  // conteúdo NÃO CONFIÁVEL, e o resumidor não tem por que enxergar o repositório
  // de quem está rodando. As ferramentas já estão negadas abaixo; o `cwd` é a
  // segunda tranca.
  //
  // E o `cwd` neutro exige resolver o executável ANTES: no Windows, `spawn`
  // com `cwd` explícito não acha `claude` pelo PATH e devolve ENOENT — medido
  // em 2026-08-20. Com o caminho absoluto do executável, `cwd` neutro funciona
  // e a autenticação continua valendo (também medido: 4,5 s, exit 0, OAuth).
  const executavel = acharExecutavelClaude();
  if (!executavel) {
    console.error('AVISO: não encontrei o executável `claude` no PATH');
    return null;
  }
  const tempDir = os.tmpdir();

  // Se o texto está acima do teto, algo deu errado no fatiamento
  if (textoDaPassada.length > TETO_ARGUMENTO) {
    console.error(`AVISO: texto acima do teto (${textoDaPassada.length} > ${TETO_ARGUMENTO})`);
    return null;
  }

  // As quebras de linha vão inteiras: argumento aceita `\n` (medido), e achatar
  // o trecho em uma linha só apaga a estrutura de turno que o resumo usa.
  const prompt = `Resuma a seguinte interação em uma observação curta (1-2 frases):\n\n${textoDaPassada}`;

  return new Promise((resolve) => {
    const timeout = 60000; // 60 segundos
    const timer = setTimeout(() => {
      console.error('AVISO: chamada à LLM expirou (timeout 60s)');
      resolve(null);
    }, timeout);

    try {
      // O PROMPT VEM PRIMEIRO, E ISSO NÃO É ESTILO. `--disallowedTools` é
      // variádico: com o prompt depois dele, o CLI engole o texto como se fosse
      // nome de ferramenta e sai com exit 1 — medido em 2026-08-20, com
      // `Permission deny rule "responda" matches no known tool`. Mesma armadilha
      // do `--mcp-config`. Não reordene.
      const child = spawn(executavel, [
        prompt,
        '-p',
        '--model', 'claude-haiku-4-5-20251001',
        '--setting-sources', '',
        '--permission-mode', 'dontAsk',
        '--disallowedTools', 'Read,Write,Edit,Bash,Glob,Grep,WebFetch,WebSearch,Task,NotebookEdit',
      ], {
        cwd: tempDir,
        windowsHide: true,
        timeout: timeout + 5000,
      });

      let stdout = '';
      let stderr = '';

      child.stdout.on('data', (data) => {
        stdout += data.toString();
      });

      child.stderr.on('data', (data) => {
        stderr += data.toString();
      });

      child.stdin.end();

      child.on('error', (error) => {
        clearTimeout(timer);
        console.error(`AVISO: erro ao chamar claude: ${error.message}`);
        resolve(null);
      });

      child.on('close', (code) => {
        clearTimeout(timer);

        if (code !== 0) {
          console.error(`AVISO: claude retornou exit code ${code}`);
          if (stderr) debug(`stderr da LLM: ${stderr}`);
          resolve(null);
          return;
        }

        if (!stdout || !stdout.trim()) {
          console.error('AVISO: LLM retornou saída vazia');
          resolve(null);
          return;
        }

        resolve(stdout.trim());
      });
    } catch (e) {
      clearTimeout(timer);
      console.error(`AVISO: erro ao invocar claude: ${e.message}`);
      resolve(null);
    }
  });
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

// Processa uma marca d'água específica: lê, formata, passa à LLM, grava observação.
// Com fatiamento: se o texto é maior que TETO_ARGUMENTO, divide em múltiplas chamadas.
// Retorna true se processou com sucesso, false se pulou ou falhou.
async function processarMarca(conexao, marca) {
  // Calcular a janela: ler a partir de offset_processado (até onde foi processado).
  // Tarefa 12 (D14): offset_processado é o ponto já processado.
  // marca.offset é offset_visto (tamanho do arquivo no Stop/SessionEnd).
  const offsetProcessado = marca.offset_processado || 0;
  debug(`janela: [${offsetProcessado}, ${marca.offset}]`);

  // Ler transcrito com rastreamento de offset
  const eventosComOffsets = lerTranscritoComOffsets(marca.arquivo, offsetProcessado);
  debug(`eventos lidos: ${eventosComOffsets.length}`);

  if (eventosComOffsets.length === 0) {
    console.log(`nenhum evento novo no transcrito (sessao=${marca.sessao})`);
    return false;
  }

  // Fatiar eventos em chunks que não excedem TETO_ARGUMENTO quando formatados
  const fatias = [];
  let fatiaAtual = [];
  let tamanhoAtual = 0;
  let offsetFimAtual = offsetProcessado;

  for (const { evento, offsetFim } of eventosComOffsets) {
    const textoEvento = formatarParaLLM([evento]);
    // Se adicionar este evento ultrapassaria o teto E já temos eventos na fatia atual
    if (tamanhoAtual + textoEvento.length > TETO_ARGUMENTO && fatiaAtual.length > 0) {
      // Fechar fatia atual e começar nova
      fatias.push({ eventos: fatiaAtual, offsetFim: offsetFimAtual });
      fatiaAtual = [evento];
      tamanhoAtual = textoEvento.length;
      offsetFimAtual = offsetFim;
    } else {
      fatiaAtual.push(evento);
      tamanhoAtual += textoEvento.length;
      offsetFimAtual = offsetFim;
    }
  }

  // Adicionar última fatia se houver
  if (fatiaAtual.length > 0) {
    fatias.push({ eventos: fatiaAtual, offsetFim: offsetFimAtual });
  }

  debug(`dividido em ${fatias.length} fatia(s)`);

  // Processar cada fatia
  for (let i = 0; i < fatias.length; i++) {
    const { eventos, offsetFim } = fatias[i];
    const textoDaPassada = formatarParaLLM(eventos);
    debug(`fatia ${i + 1}/${fatias.length}: ${eventos.length} evento(s), ${textoDaPassada.length} caracteres`);

    // Rejeitar prompt vazio (tarefa 15: não gravar lixo no banco)
    if (!textoDaPassada || !textoDaPassada.trim()) {
      console.log(`prompt vazio em fatia ${i + 1}: nenhuma observacao para gravar`);
      continue;
    }

    // Chamar LLM
    console.log(`processando fatia ${i + 1}/${fatias.length} com ${eventos.length} evento(s) (sessao=${marca.sessao})...`);
    const observacao = await chamarLLM(textoDaPassada);
    debug(`observacao da LLM: ${observacao ? observacao.substring(0, 50) : 'null'}`);

    if (!observacao) {
      // Falha na LLM — marca intacta, tenta novamente depois
      console.log(`LLM retornou null em fatia ${i + 1}, marca dagua nao avanca (sessao=${marca.sessao})`);
      return false;
    }

    // Gravar observação
    // Origem inclui offset_fim para granularidade — permite múltiplas observações
    // por sessão sem colisão (Achado 5 revisado: discriminador granular, não por sessão inteira).
    const gravouOk = gravarObservacao(conexao, {
      projeto: marca.projeto,
      conteudo: observacao,
      origem: `sessao:${marca.sessao}:offset:${offsetFim}`,
    });
    debug(`gravou ok (fatia ${i + 1}): ${gravouOk}`);

    if (!gravouOk) {
      // Falha ao gravar — marca intacta
      console.log(`erro ao gravar observacao em fatia ${i + 1}, marca dagua nao avanca (sessao=${marca.sessao})`);
      return false;
    }

    // Avançar offset_processado APÓS cada fatia processada com sucesso
    // Tarefa 6 (D6): marca d'água avança por fatia, não de uma vez no fim
    const avancoOk = avancarMarca(conexao, {
      projeto: marca.projeto,
      sessao: marca.sessao,
      offsetProcessado: offsetFim,
    });
    debug(`avanco ok (fatia ${i + 1}): ${avancoOk}`);

    if (!avancoOk) {
      // Falha ao avançar — aviso, mas observação já foi gravada
      console.log(`AVISO: observacao gravada em fatia ${i + 1} mas offset_processado nao avancou (sessao=${marca.sessao})`);
      return false;
    }
  }

  const pluralFatias = fatias.length > 1 ? 'fatias' : 'fatia';
  console.log(`ok: observacao gravada em ${fatias.length} ${pluralFatias} para sessao ${marca.sessao}`);
  return true;
}

// Função principal: processa sessão e grava observação.
async function processarSessao(sessao, projeto) {
  const dados = resolverDados();

  // Decisão D16 (reversibilidade da fase 1): se o banco não existe, é degradação
  // graciosa — a fase 1 é leitura pura e nunca cria estado. Exit 0, sem observação.
  if (!fs.existsSync(dados.caminhoDb)) {
    debug(`banco ausente (degradacao graciosa): ${dados.caminhoDb}`);
    return;
  }

  let conexao;
  try {
    conexao = abrirBanco(dados.caminhoDb);
  } catch (e) {
    console.error(`AVISO: não consegui abrir banco: ${e.message}`);
    return; // Degradação: tenta novamente depois
  }

  try {
    // Modo 1: sessão e projeto informados — processar aquela marca específica
    if (sessao && projeto) {
      debug(`Procurando marca: sessao=${sessao}, projeto=${projeto}`);
      const marca = lerMarca(conexao, { sessao, projeto });
      debug(`marca encontrada: ${marca ? 'sim' : 'nao'}`);
      if (marca) {
        debug(`  sessao=${marca.sessao}, arquivo=${marca.arquivo}, offset=${marca.offset}`);
      }

      if (!marca) {
        console.log('nenhuma marca dagua encontrada');
        return;
      }

      await processarMarca(conexao, marca);
    }
    // Modo 2: sem argumentos — processar TODAS as marcas com pendência
    else {
      debug('Nenhum argumento: processando todas as marcas com pendência');
      const marcas = lerMarcasPendentes(conexao);

      if (marcas.length === 0) {
        console.log('nenhuma marca com pendencia para processar');
        return;
      }

      console.log(`encontradas ${marcas.length} marca(s) com pendencia`);
      for (const marca of marcas) {
        debug(`processando marca: sessao=${marca.sessao}, projeto=${marca.projeto}`);
        await processarMarca(conexao, marca);
      }
    }
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
