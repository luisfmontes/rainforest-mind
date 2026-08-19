#!/usr/bin/env node
/**
 * Hook: marca d'água sobre o transcrito.
 *
 * Eventos: Stop, SessionEnd — gravam o ponto de processamento na abertura seguinte.
 *
 * Responsabilidade (tarefa 10): gravar na tabela `marca_dagua` o ponto de
 * processamento atual (sessão, caminho do transcrito, offset processado),
 * permitindo que uma sessão interrompida seja recuperada na abertura seguinte.
 *
 * Justificativa do evento:
 * - O transcrito cresce a cada ferramenta executada.
 * - PostToolUse dispara no fim de cada ferramenta, capturando o transcrito atual.
 * - Permite recuperação fina: se a sessão morrer, sabe-se até onde foi processado.
 * - Custo: zero — apenas uma escrita de marca d'água no banco, em processo.
 *
 * Propriedades exigidas:
 * - Zero spawn/exec (nenhum processo novo).
 * - Idempotente: recuar offset e reprocessar = mesma contagem final.
 * - Degradação graciosa: banco ausente/corrompido não trava o hook.
 */

const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { abrirBanco, criarSchema, resolverCaminhos } = require(
  path.join(__dirname, '..', 'scripts', 'memoria.cjs')
);

// Lê JSON do stdin (evento do harness).
function lerEvento() {
  try {
    const input = fs.readFileSync(0, 'utf8');
    return JSON.parse(input);
  } catch (e) {
    // Sem stdin válido, sem dados — exit 0, não bloqueia.
    return {};
  }
}

// Resolve caminhos da raiz de dados.
function resolverDados() {
  const { raiz } = resolverRaiz({
    plugin: path.resolve(__dirname, '..'),
  });

  if (!raiz) {
    return null;
  }

  return {
    raiz,
    caminhoDb: path.join(raiz, 'rainforest.db'),
  };
}

// Resolve o caminho do transcrito.
// O harness escreve em: ${CLAUDE_CONFIG_DIR}/projects/<projeto>/<sessão>.jsonl
// Para agora, usamos CLAUDE_CONFIG_DIR se disponível, ou resolvemos pela raiz.
function resolverTranscrito(evento) {
  const configDir = process.env.CLAUDE_CONFIG_DIR;
  const sessionId = evento.session_id || 'desconhecida';

  if (!configDir) {
    return null;
  }

  // Tenta usar o projeto do evento (pode vir do stdin).
  const projeto = evento.project || 'default';

  // Caminho do transcrito: ${CLAUDE_CONFIG_DIR}/projects/${projeto}/${sessionId}.jsonl
  const caminhoTranscrito = path.join(
    configDir,
    'projects',
    projeto,
    `${sessionId}.jsonl`
  );

  return caminhoTranscrito;
}

// Grava a marca d'água na tabela.
// Para a tarefa 10: registra sessão, arquivo, offset (tamanho do arquivo).
// Usa INSERT OR REPLACE para ser idempotente.
function gravarMarca(conexao, { projeto, sessao, arquivo, offset }) {
  const agora = new Date().toISOString();

  try {
    const stmt = conexao.prepare(`
      INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em)
      VALUES (?, ?, ?, ?, ?)
    `);

    stmt.run(projeto, sessao, arquivo, offset, agora);
  } catch (e) {
    // Falha ao gravar — ignorar, não travar o hook.
  }
}

// Extrai o tamanho do transcrito (offset).
function lerOffset(caminhoTranscrito) {
  try {
    if (!fs.existsSync(caminhoTranscrito)) {
      return 0;
    }
    const stats = fs.statSync(caminhoTranscrito);
    return stats.size;
  } catch (e) {
    return 0;
  }
}

// Recupera marcas d'água pendentes (sessões interrompidas).
// Chamado no SessionStart com --recover.
// Varre a tabela marca_dagua, detecta pendências (offset_visto > offset_processado)
// e sinaliza para que observar.cjs processe na sessão atual.
function recuperarSessoes() {
  try {
    const dados = resolverDados();
    if (!dados) {
      process.exit(0);
    }

    let conexao;
    try {
      conexao = abrirBanco(dados.caminhoDb);
      criarSchema(conexao);
    } catch (e) {
      // Banco não abrível — degradação silenciosa.
      process.exit(0);
    }

    try {
      // Varre todas as marcas da tabela.
      // Nota: offset_processado pode não existir em DBs legados (antes da migração).
      // SQLite retorna NULL para colunas inexistentes, mas se a migração rodou,
      // offset_processado existe com default 0.
      const stmtLer = conexao.prepare(`
        SELECT id, projeto, sessao, arquivo, offset,
               COALESCE(offset_processado, 0) as offset_processado
        FROM marca_dagua
      `);
      const marcas = stmtLer.all();

      // Tarefa 11 (D14): detecta e **sinaliza** pendência, MAS NUNCA avança offset.
      // O offset só avança após a passada de observação (tarefa 12) processar e gravar.
      // Sinalização: console.log de pendência detectada.
      // A passada de observação (observar.cjs) roda em SessionStart e verifica
      // se há pendências a processar.
      for (const marca of marcas) {
        try {
          const tamanhoAtual = lerOffset(marca.arquivo);

          // Se o arquivo cresceu além do offset_processado (não offset_visto),
          // há observações pendentes para gerar.
          if (tamanhoAtual > marca.offset_processado) {
            // Sinaliza que há pendência nesta sessão.
            // O formato é estruturado para ser parsável por testes.
            console.log(`PENDENCIA: sessao=${marca.sessao} projeto=${marca.projeto} offset_processado=${marca.offset_processado} tamanho_atual=${tamanhoAtual}`);
          }
        } catch (e) {
          // Erro ao processar marca específica — continua com próxima.
        }
      }

      process.exit(0);
    } finally {
      conexao.close();
    }
  } catch (e) {
    // Qualquer erro não antecipado — degradação silenciosa.
    process.exit(0);
  }
}

// Main: lê evento, resolve caminhos, grava marca.
// Detecta se está rodando em modo --recover (SessionStart) ou modo normal (Stop/SessionEnd).
function main() {
  // Modo recuperação: SessionStart com --recover
  if (process.argv.includes('--recover')) {
    recuperarSessoes();
    return;
  }

  // Modo normal: grava marca d'água (Stop/SessionEnd)
  try {
    const evento = lerEvento();
    const sessionId = evento.session_id;

    // Sem sessão, sem dados.
    if (!sessionId) {
      process.exit(0);
    }

    // Resolve raiz de dados.
    const dados = resolverDados();
    if (!dados) {
      process.exit(0);
    }

    // Resolve caminho do transcrito.
    const caminhoTranscrito = resolverTranscrito(evento);
    if (!caminhoTranscrito) {
      process.exit(0);
    }

    // Abre banco e cria schema se necessário.
    let conexao;
    try {
      conexao = abrirBanco(dados.caminhoDb);
      criarSchema(conexao);
    } catch (e) {
      // Banco não abrível — degradação.
      process.exit(0);
    }

    try {
      // Extrai projeto e offset.
      const projeto = evento.project || path.basename(dados.raiz);
      const offset = lerOffset(caminhoTranscrito);

      // Grava marca d'água.
      gravarMarca(conexao, {
        projeto,
        sessao: sessionId,
        arquivo: caminhoTranscrito,
        offset,
      });
    } finally {
      conexao.close();
    }

    process.exit(0);
  } catch (e) {
    // Qualquer erro não antecipado — degradação.
    process.exit(0);
  }
}

if (require.main === module) {
  main();
}

module.exports = { gravarMarca, resolverTranscrito, lerOffset };
