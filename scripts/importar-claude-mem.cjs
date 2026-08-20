#!/usr/bin/env node
/**
 * Importador de observações do claude-mem para o banco de dados do rainforest.
 *
 * Por que existe: durante a fase 1 (antes da captura própria), as observações
 * existentes entram por importação única mais reimportação incremental até a fase 2.
 * O importador é script isolado rodado sob demanda, nunca caminho de execução
 * (decisão D6).
 *
 * Garantias:
 * - Importação única: rodar de novo sem novidade insere 0 (idempotente)
 * - Origem ausente é caminho normal, não erro: exit 0 com mensagem
 * - Abre origem somente-leitura (mode=ro) e tolera WAL aberto por escrita
 * - Discriminador estável: content_hash + id da origem (já existe em claude-mem.db)
 *
 * Uso:
 *   node scripts/importar-claude-mem.cjs
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

// Importar funções reutilizáveis de memoria.cjs (D2, D8 — zero duplicação de lógica,
// driver isolado no adaptador).
const { resolverCaminhos, abrirBanco, abrirBancoSomenteLeitura, criarSchema } = require('./memoria.cjs');

// Encontrar o banco de origem (claude-mem.db) em ~/.claude-mem/
// Por testes: permite override via TESTADOR_ORIGEM_CLAUDE_MEM
function encontrarOrigemClaudeMem() {
  // Override para testes — se definido, sempre usa (mesmo que arquivo não exista)
  // isso permite testar o caso de "origem ausente" sem interferir com ~/.claude-mem real
  if (process.env.TESTADOR_ORIGEM_CLAUDE_MEM) {
    return process.env.TESTADOR_ORIGEM_CLAUDE_MEM;
  }

  const home = os.homedir();
  const caminhoOrigemPadrao = path.join(home, '.claude-mem', 'claude-mem.db');

  if (fs.existsSync(caminhoOrigemPadrao)) {
    return caminhoOrigemPadrao;
  }

  return null;
}

// Normaliza nome de projeto ao último segmento do caminho.
// Tarefa 2 (D2): `inovacao/gestao-projetos-template` → `gestao-projetos-template`.
// Vale para `/` e para `\` em caminhos Windows.
function normalizarProjeto(projetoOrigem) {
  if (!projetoOrigem) return null;
  // Pegar o último segmento do caminho (independente do separador / ou \)
  const partes = String(projetoOrigem).split(/[\/\\]/);
  const ultimo = partes[partes.length - 1];
  return ultimo || null;
}

// Busca observações da origem (tabela `observations`)
// Tarefa 2 (D2, D4): Inclui coluna `project` da origem para preservação linha a linha.
function buscarObservacoes(conexaoOrigem) {
  try {
    // Esquema da origem (D5): id, text, created_at, content_hash, project
    // Se coluna project não existe (origem antiga), trata como null — SQL retorna NULL para coluna inexistente
    const resultado = conexaoOrigem.prepare(`
      SELECT id, text, created_at, content_hash, project
      FROM observations
      ORDER BY id ASC
    `).all();
    return resultado || [];
  } catch (e) {
    // Se tabela não existe ou consulta falha (inclusive se coluna project não existe),
    // tentar sem a coluna project (compatibilidade com origin antiga)
    try {
      const resultado = conexaoOrigem.prepare(`
        SELECT id, text, created_at, content_hash, NULL as project
        FROM observations
        ORDER BY id ASC
      `).all();
      return resultado || [];
    } catch {
      // Se tabela não existe ou consulta falha mesmo, retornar vazio
      // (origem incompatível ou corrompida)
      return [];
    }
  }
}

// Importar observações do banco de origem para o destino
// Tarefa 2 (D2, D4): Preserva o projeto da origem, normalizado.
// Usa discriminador estável (content_hash + id) via campo `origem` no destino
function importarObservacoes(conexaoOrigem, conexaoDestino, projetoFallback) {
  const observacoes = buscarObservacoes(conexaoOrigem);

  if (observacoes.length === 0) {
    console.log('(nenhuma observação encontrada na origem)');
    return 0;
  }

  let importadas = 0;
  let duplicadas = 0;

  for (const obs of observacoes) {
    try {
      // Tarefa 2 (D2): Se a observação tem projeto, normalizar e usar.
      // Senão, fallback para o projeto resolvido no destino.
      let projetoFinal = projetoFallback;
      if (obs.project) {
        const normalizado = normalizarProjeto(obs.project);
        if (normalizado) {
          projetoFinal = normalizado;
        }
      }

      // Inserir com discriminador estável como origem
      const stmt = conexaoDestino.prepare(`
        INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
        VALUES (:projeto, :conteudo, :criada_em, :origem)
      `);

      stmt.run({
        projeto: projetoFinal,
        conteudo: obs.text || '',
        criada_em: obs.created_at || new Date().toISOString(),
        // Discriminador estável: identifica origem e evita reimportação
        origem: `claude-mem:${obs.id}:${obs.content_hash || 'unknown'}`,
      });

      importadas++;
    } catch (e) {
      // UNIQUE(projeto, origem) violation: observação desta origem já foi importada
      if (e.message && e.message.includes('UNIQUE constraint failed')) {
        duplicadas++;
      } else {
        throw e;
      }
    }
  }

  console.log(`importadas: ${importadas}, duplicadas (já existentes): ${duplicadas}`);
  return importadas;
}

function main() {
  // Encontrar origem
  const caminhoOrigem = encontrarOrigemClaudeMem();

  if (!caminhoOrigem || !fs.existsSync(caminhoOrigem)) {
    console.log('nenhuma origem encontrada: claude-mem.db não existe');
    console.log('continue sem importar histórico, ou instale o claude-mem e rode este comando de novo');
    process.exit(0);
  }

  // Abrir origem em modo somente-leitura via adaptador (D6, D8 — origem ausente é caminho normal,
  // driver isolado no adaptador memoria.cjs)
  const conexaoOrigem = abrirBancoSomenteLeitura(caminhoOrigem);
  if (!conexaoOrigem) {
    console.log('não consegui abrir origem (em uso ou corrompida)');
    console.log('tente de novo em alguns segundos');
    process.exit(0);
  }

  try {
    // Resolver raiz de dados do destino (D9 — cadeia de 4 níveis)
    const { caminhoDb, projeto } = resolverCaminhos();

    // Criar diretório se não existe
    const raiz = path.dirname(caminhoDb);
    fs.mkdirSync(raiz, { recursive: true });

    // Abrir destino (e garantir schema — D2, reusar de memoria.cjs)
    const conexaoDestino = abrirBanco(caminhoDb);
    criarSchema(conexaoDestino);

    try {
      const importadas = importarObservacoes(conexaoOrigem, conexaoDestino, projeto);

      if (importadas > 0) {
        console.log(`✓ ${importadas} observação(ões) importada(s)`);
      }
    } finally {
      conexaoDestino.close();
    }
  } finally {
    conexaoOrigem.close();
  }
}

if (require.main === module) {
  try {
    main();
  } catch (e) {
    console.error(`ERRO: ${e.message}`);
    process.exit(1);
  }
}

module.exports = { encontrarOrigemClaudeMem };
