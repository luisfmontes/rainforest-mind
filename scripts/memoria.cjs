#!/usr/bin/env node
/**
 * Gerenciador do banco de dados da memória do rainforest.
 *
 * Por que existe: o rainforest precisa de seu próprio store de memória para
 * sair da dependência frágil do claude-mem. O banco é consultável,
 * versionável e não sofre com os ~3.800 spawns diários que o caminho
 * de escrita do claude-mem provoca (decisão D2).
 *
 * Driver: node:sqlite (decisão D8). Zero dependência externa; experimental
 * em Node 22, mas isolado neste adaptador para absorver mudanças de API.
 *
 * Raiz de dados: cadeia de 4 níveis resolvida por hooks/lib/raiz.cjs
 * (decisão D9) — RFM_ROOT > projeto/.rainforest > ~/.rainforest > plugin.
 *
 * Uso:
 *   node scripts/memoria.cjs iniciar                 criar/abrir o banco
 *   node scripts/memoria.cjs esquema [--json]        listar schema do banco
 *   node scripts/memoria.cjs buscar [opções]         buscar observações
 *   node scripts/memoria.cjs backup                  fazer backup do banco
 *   node scripts/memoria.cjs reindexar               reconstruir índices
 *   node scripts/memoria.cjs consolidar              sintetizar observações antigas em resumos
 *   node scripts/memoria.cjs reconciliar             store/update/merge/skip contra o acervo pendente
 *   node scripts/memoria.cjs utilidade --extrair <transcrito>   inspecionar servidas/texto de um transcrito
 *   node scripts/memoria.cjs utilidade --relatorio  régua D9: liga ou não o ranking por utilidade
 */

const fs = require('fs');
const path = require('path');

// node:sqlite — built-in desde Node 22.0.0. Status: estável (Node 23.1+),
// experimental antes disso. O adaptador deste arquivo absorve mudanças.
let sqlite3 = null;
try {
  sqlite3 = require('node:sqlite');
} catch (e) {
  console.error('ERRO: node:sqlite não disponível');
  console.error('Requer: Node.js 22.0.0 ou superior');
  process.exit(1);
}

// Resolve a raiz de dados e o projeto — cadeia de 4 níveis (D9).
// RFM_ROOT > projeto/.rainforest > ~/.rainforest > plugin
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');

// Acha o executável `claude` do PATH.
const { acharExecutavelClaude } = require('./lib/achar-executavel-claude.cjs');

// Chave de grupo de origem de uma observação — consolidação por grupo (D7).
const { sqlGrupoDeOrigem } = require('./lib/grupo-de-origem.cjs');

// Sinal de utilidade da memória (Tarefas 1, 3 e 4, D1-D11). Sentido único:
// utilidade.cjs nunca requer este arquivo de volta (evitaria require
// circular — ver o comentário no topo de scripts/lib/utilidade.cjs).
const { extrairSessao, pontuarSessoesPendentes, gerarRelatorio } = require('./lib/utilidade.cjs');

// Encontra o diretório .git subindo a árvore de diretórios.
// Retorna o caminho do diretório que contém .git, ou null se não encontrado.
// Implementação: varredura de sistema de arquivos, sem spawns de git (decisão D1).
function encontrarGit(inicio = process.cwd()) {
  let atual = path.resolve(inicio);
  const raizVolume = path.parse(atual).root;

  while (atual !== raizVolume) {
    const gitPath = path.join(atual, '.git');
    try {
      const stats = fs.statSync(gitPath);
      // .git pode ser arquivo (worktree linkada) ou diretório (repositório normal)
      if (stats.isFile() || stats.isDirectory()) {
        return atual;
      }
    } catch (e) {
      // .git não existe neste diretório, subir mais um nível
    }
    atual = path.dirname(atual);
  }

  return null;
}

// Deriva a chave de projeto que o harness do Claude Code usa para armazenar projetos.
// Formato harness: paths com \ / e : são trocados por -.
// Ex: C:\Projetos\rainforest-mind → C--Projetos-rainforest-mind
//     C:\Microsiga\erp-trabalho\inovacao → C--Microsiga-erp-trabalho-inovacao
// Função pura, sem I/O.
function chaveHarness(diretorio) {
  if (!diretorio) return '';
  // Normalizar separadores (\ e /) e : para -
  return diretorio.replace(/[\\/:]/g, '-');
}

// Ponto único de inversão (Tarefa 3, D3): observação substituída
// (substituida_por IS NOT NULL) sai da injeção e da busca, sem ser apagada.
// Todo caminho de leitura em observacoes usa esta função em vez de escrever
// o AND à mão — um único lugar para a catraca de mutação inverter.
// `alias`, quando a consulta usa alias de tabela (ex.: `FROM observacoes o`),
// tem que vir com o ponto (`'o.'`), porque o retorno é colado direto na SQL.
function filtroVivas(alias) {
  return 'AND ' + (alias || '') + 'substituida_por IS NULL';
}

function resolverCaminhos() {
  const { raiz } = resolverRaiz({
    plugin: path.resolve(__dirname, '..'),
  });

  if (!raiz) {
    console.error('ERRO: Nenhuma raiz de dados encontrada');
    console.error('Configure RFM_ROOT, use .rainforest no projeto, ou rode o setup');
    process.exit(1);
  }

  // Tarefa 1 (D13): O projeto vem do diretório da sessão, não da raiz de dados.
  // Suba a árvore procurando .git (arquivo ou diretório); basename desse diretório é o projeto.
  // Fallback: basename do cwd se .git não encontrado (sessão fora de repositório).
  // Decisão D13 define que a matéria-prima é projects/<projeto>/<sessão>.jsonl no harness.
  let projeto;
  const cwd = process.cwd();
  const topLevel = encontrarGit(cwd);
  if (topLevel) {
    projeto = path.basename(topLevel);
  } else {
    projeto = path.basename(cwd);
  }

  const caminhoDb = path.join(raiz, 'rainforest.db');

  // Retornar AMBAS as chaves: `projeto` (curta, para compatibilidade) e `projetos`
  // (array com chave harness + chave curta, sem duplicatas, sem vazias).
  // Permite que o leitor consulte ambas, mantendo histórico sob chave curta
  // enquanto novos dados vêm em chave harness.
  const chaveHarness_valor = topLevel ? chaveHarness(topLevel) : '';
  const projetosCandidatas = [chaveHarness_valor, projeto].filter(
    (p, i, arr) => p && arr.indexOf(p) === i // sem duplicatas, sem vazias
  );

  return { raiz, caminhoDb, projeto, projetos: projetosCandidatas };
}

// Abre conexão com o banco. Cria se não existe. Retorna a conexão.
// LANÇA exceção se não conseguir abrir — permite degradação graciosa no chamador.
function abrirBanco(caminhoDb) {
  // sqlite3.open retorna uma Promise; aqui usamos await em contexto
  // async, ou podemos usar synchronous method se disponível. Node 22
  // oferece sync via openSync no namespace sqlite.
  //
  // Para Node 22 + 23, usamos DatabaseSync (synchronous).
  try {
    const DatabaseSync = require('node:sqlite').DatabaseSync;
    const conexao = new DatabaseSync(caminhoDb);
    // WAL mode para concorrência: leitura não bloqueia escrita.
    conexao.exec('PRAGMA journal_mode = WAL;');
    return conexao;
  } catch (e) {
    // Tarefa 21 (D18): LANÇAR exceção em vez de process.exit, permitindo
    // degradação graciosa do chamador (hook de SessionStart, saude.cjs, etc).
    throw new Error(`Não consegui abrir DatabaseSync do node:sqlite: ${e.message}`);
  }
}

// Abre conexão somente-leitura com um banco (qualquer banco, não só rainforest.db).
// Decisão D8 (driver isolado no adaptador): todos acessos a node:sqlite via este módulo.
//
// Uso: importação de bancos externos, auditorias, backups, leitura de transcritos.
// Tolera WAL aberto por escrita concorrente — o modo somente-leitura do SQLite mais o
// PRAGMA query_only impedem escrita, mesmo com PRAGMA journal_mode = WAL ativo em outro
// processo. Ver o comentário dentro da função: até 2026-08-25 esta promessa era falsa,
// porque o nome da opção estava errado e o `node:sqlite` a ignorava calado.
//
// Parâmetros:
//   caminhoDb (string): caminho do arquivo do banco
//
// Retorna: conexão DatabaseSync se sucesso, null se falha (banco ausente, corrompido, etc.)
// Não lança exceção, não faz console.error — decisão para degradação graciosa em hook.
function abrirBancoSomenteLeitura(caminhoDb) {
  try {
    const DatabaseSync = require('node:sqlite').DatabaseSync;
    // `readOnly`, com O maiúsculo — o `node:sqlite` IGNORA opção desconhecida em
    // silêncio, então `{ readonly: true }` (como estava até 2026-08-25) abria o
    // banco em LEITURA E ESCRITA sem avisar ninguém. Medido no Node v22.16.0
    // desta máquina: com `readonly` minúsculo, `PRAGMA query_only = OFF` seguido
    // de INSERT **grava**; com `readOnly`, o SQLite recusa com "attempt to write
    // a readonly database". A bateria assere exatamente isso.
    //
    // O `query_only` abaixo escondia o defeito: ele barra escrita de SQL nos dois
    // casos, então nenhum teste de INSERT pegava a diferença. O que ele NÃO barra
    // é o checkpoint de WAL no `close()` — e foi assim que uma auditoria de
    // 2026-08-25, que só queria contar linhas do `claude-mem.db`, absorveu o WAL
    // de 4 MB do banco que estava auditando. Dado nenhum se perdeu, mas quem abre
    // "somente leitura" não deve poder alterar um byte do arquivo.
    const conexao = new DatabaseSync(caminhoDb, { readOnly: true });
    // PRAGMA query_only: segunda tranca, não a primeira. Fica porque dá mensagem
    // de erro melhor para escrita de SQL, mas o que garante o arquivo é o modo.
    conexao.exec('PRAGMA query_only = ON;');
    return conexao;
  } catch (e) {
    // Banco indisponível (em uso, corrompido, ausente, etc.)
    return null;
  }
}

// Verifica se o banco tem UNIQUE(projeto, origem) — constraint obrigatória.
// Retorna: true se constraint existe, false caso contrário.
// Não lança exceção, retorna false em qualquer erro de leitura.
function verificarConstraintUniqueProjetoOrigem(conexao) {
  if (!conexao) return false;

  try {
    const indices = conexao.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='index' AND tbl_name='observacoes'
    `).all();

    for (const idx of indices) {
      try {
        const colunas = conexao.prepare(`PRAGMA index_info('${idx.name}')`).all();
        if (colunas.length === 2
            && colunas[0].name === 'projeto'
            && colunas[1].name === 'origem') {
          return true;
        }
      } catch {
        // Continuar verificando outros índices
      }
    }

    return false;
  } catch {
    return false;
  }
}

// Recuperação de banco que já está em estado quebrado.
// Detacta: observacoes_backup órfã (observacoes não existe ou está vazia)
// Recupera: copia backup → observacoes, remove backup
// Chamado ANTES de criarSchema para impedir que CREATE TABLE IF NOT EXISTS crie tabela vazia
function recuperarSeNecessario(conexao) {
  try {
    const temTabela = conexao.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='observacoes'
    `).all().length > 0;

    const temBackup = conexao.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='observacoes_backup'
    `).all().length > 0;

    // Se observacoes_backup existe e (observacoes não existe OU está vazia), recuperar
    if (temBackup) {
      let deveRecuperar = false;
      if (!temTabela) {
        deveRecuperar = true;
      } else {
        const cntObs = conexao.prepare(`SELECT COUNT(*) as c FROM observacoes`).all()[0].c;
        if (cntObs === 0) {
          deveRecuperar = true;
        }
      }

      if (deveRecuperar) {
        conexao.exec('BEGIN TRANSACTION');
        try {
          // Se observacoes existe mas vazia, remover para criar nova
          if (temTabela) {
            conexao.exec(`DROP TABLE observacoes;`);
          }

          // Criar tabela nova com constraint correto
          conexao.exec(`
            CREATE TABLE observacoes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              projeto TEXT NOT NULL,
              conteudo TEXT NOT NULL,
              criada_em TEXT NOT NULL,
              origem TEXT,
              UNIQUE(projeto, origem)
            );
          `);

          // Copiar dados de backup
          conexao.exec(`
            INSERT INTO observacoes (id, projeto, conteudo, criada_em, origem)
            SELECT id, projeto, conteudo, criada_em, origem FROM observacoes_backup
          `);

          // Remover backup
          conexao.exec(`DROP TABLE observacoes_backup;`);

          // Recriar índice
          conexao.exec(`CREATE INDEX IF NOT EXISTS idx_observacoes_projeto ON observacoes(projeto);`);

          conexao.exec('COMMIT');

          if (process.env.DEBUG_SCHEMA) {
            console.error(`Recuperação: tabela observacoes restaurada de backup`);
          }
        } catch (e) {
          try {
            conexao.exec('ROLLBACK');
          } catch { }
          throw e;
        }
      }
    }
  } catch (e) {
    if (process.env.DEBUG_SCHEMA) {
      console.error(`AVISO: recuperação parcial - ${e.message}`);
    }
    // Não relança: deixa a próxima etapa lidar com o erro
  }
}

// Limpa marca_dagua sob rótulo velho de projeto.
// Tarefa 4 (D1): O projeto muda de derivação (de raiz global para diretório da sessão).
// Linhas antigas com projeto constante (ex: "Luis") nunca mais casam com sessões novas.
// Esta migração é idempotente: DELETE de tabela vazia ou inexistente não causa erro.
// Justificativa: UNIQUE(projeto, sessao) garante que qualquer sessão nova cria linha nova,
// então é seguro deletar tudo. Marca d'água só carrega (sessao, arquivo, offset),
// ainda não existe observação nenhuma no banco de teste, e reprocessar do offset 0 não duplica.
// Versão de esquema desta base. Sobe quando uma migração precisa rodar UMA vez.
// 1 = marca_dagua limpa por causa da troca de derivação de projeto (D1).
const VERSAO_ESQUEMA = 1;

function limparMarcaDagua(conexao) {
  try {
    // Verificar se a tabela marca_dagua existe
    const temTabela = conexao.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='marca_dagua'
    `).all().length > 0;

    if (!temTabela) {
      // Tabela não existe — nada a limpar.
      return;
    }

    // ESTA MIGRAÇÃO RODA UMA VEZ, E O GUARDA É O MOTIVO DE ELA EXISTIR ASSIM.
    // `criarSchema()` é chamada em todo caminho que abre o banco — inclusive
    // pelo `hooks/memoria-marca.cjs`, a cada gravação de marca d'água. Sem o
    // guarda, o DELETE apagava a marca que o próprio hook acabara de escrever:
    // o `offset_processado` nunca saía de 0 e a captura reprocessava do início
    // para sempre, em silêncio. Medido em 2026-08-20, com três baterias
    // (`testa-observar-offset`, `testa-memoria-recuperacao`,
    // `testa-memoria-recuperacao-ponta-a-ponta`) ficando vermelhas de uma vez.
    const versao = conexao.prepare('PRAGMA user_version').get().user_version;
    if (versao >= VERSAO_ESQUEMA) {
      return;
    }

    // Limpar todas as linhas da tabela e carimbar a versão, para não repetir.
    conexao.exec(`DELETE FROM marca_dagua;`);
    conexao.exec(`PRAGMA user_version = ${VERSAO_ESQUEMA};`);

    if (process.env.DEBUG_SCHEMA) {
      console.error(`Migração: marca_dagua limpa (linhas com projeto velho descartadas)`);
    }
  } catch (e) {
    // Falha na limpeza não trava — a tabela pode estar em estado inesperado
    if (process.env.DEBUG_SCHEMA) {
      console.error(`AVISO: falha ao limpar marca_dagua: ${e.message}`);
    }
  }
}

// Executa o schema SQL no banco.
function criarSchema(conexao) {
  const caminhoSchema = path.resolve(__dirname, 'esquema-memoria.sql');
  if (!fs.existsSync(caminhoSchema)) {
    console.error(`ERRO: ${caminhoSchema} não encontrado`);
    process.exit(1);
  }

  let sql = fs.readFileSync(caminhoSchema, 'utf8');
  // Remover comentários de linha SQL (--) antes de fazer split.
  sql = sql.split('\n').filter(linha => !linha.trim().startsWith('--')).join('\n');

  // Parser especial para triggers: reconhecer BEGIN...END como blocos únicos.
  // Estratégia: encontrar CREATE TRIGGER...BEGIN...END; e trata-lo como um statement único.
  const statements = [];
  let i = 0;
  while (i < sql.length) {
    // Procurar pelo próximo CREATE TRIGGER
    const triggerMatch = sql.indexOf('CREATE TRIGGER', i);
    if (triggerMatch === -1) {
      // Nenhum trigger a partir daqui: processar o resto por split normal
      const resto = sql.substring(i).trim();
      if (resto.length > 0) {
        const ultimos = resto
          .split(';')
          .map(s => s.trim())
          .filter(s => s.length > 0);
        statements.push(...ultimos);
      }
      break;
    }

    // Procurar por `;` antes do trigger (para capturar statements anteriores)
    const prevSemicolon = sql.lastIndexOf(';', triggerMatch);
    if (prevSemicolon > i) {
      const antes = sql.substring(i, prevSemicolon).trim();
      if (antes.length > 0) {
        const stmts = antes
          .split(';')
          .map(s => s.trim())
          .filter(s => s.length > 0);
        statements.push(...stmts);
      }
    }

    // Encontrar o final do trigger (END;)
    const endIdx = sql.indexOf('END;', triggerMatch);
    if (endIdx === -1) {
      throw new Error(`Trigger sem fechamento encontrado em ${triggerMatch}`);
    }

    // Extrair o trigger inteiro
    const trigger = sql.substring(triggerMatch, endIdx + 4).trim();
    statements.push(trigger);

    i = endIdx + 4;
  }

  for (const stmt of statements) {
    try {
      conexao.exec(stmt);
    } catch (e) {
      // Ignorar erro de "já existe" para IF NOT EXISTS
      if (!e.message.includes('already exists')) {
        throw e;
      }
    }
  }

  // Migração 1: separar "visto" de "processado" na marca_dagua.
  // Tarefa 11 (D12, D13) decidiu que:
  // - offset_visto: tamanho do transcrito conforme visto pelo harness (Stop/SessionEnd)
  // - offset_processado: tamanho processado pela passada de LLM (observar.cjs)
  // - A recuperação detecta (offset_visto > offset_processado) mas não avança offset_processado
  // Esta migração é idempotente: ADD COLUMN IF NOT EXISTS garante segurança.
  try {
    // Tentar adicionar offset_processado. Se já existir, será no-op.
    conexao.exec(`
      ALTER TABLE marca_dagua ADD COLUMN offset_processado INTEGER DEFAULT 0;
    `);
  } catch (e) {
    // Se falhar com "duplicate column name", é porque já existe — ok.
    // Qualquer outro erro é inesperado, mas não trava a sessão (é schema creation).
    if (!e.message.includes('duplicate column')) {
      // Nota: não relançamos. Schema pode estar parcialmente aplicado
      // (offset_processado já existe), e é ok continuar.
    }
  }

  // Se a tabela é nova, offset e offset_processado são criados da mesma forma
  // na criação inicial. Se é legado, offset já existe (será usado como offset_visto)
  // e offset_processado foi acabado de adicionar (default 0).
  // Não precisamos renomear offset para offset_visto nesta versão, pois
  // o código vai continuar a usar 'offset' na INSERT/SELECT para retrocompatibilidade.

  // Migração 2: renomear constraint UNIQUE de observacoes.
  // Achado 2: esquema novo tem UNIQUE(projeto, origem), mas bancos legados têm
  // UNIQUE(projeto, conteudo) ou nenhuma constraint UNIQUE.
  // SQLite não altera constraints com ALTER TABLE, então precisa recriar a tabela.
  // Esta migração é idempotente: detecta se já tem a constraint correta e pula.
  try {
    migraoesObservacoes(conexao);
  } catch (e) {
    // Falha na migração não trava schema creation — log e continua.
    // O banco pode estar em estado intermediário, mas deve ser recuperável.
    if (process.env.DEBUG_SCHEMA) {
      console.error(`AVISO: falha na migração de observacoes: ${e.message}`);
    }
  }

  // Migração 3: limpar marca_dagua sob rótulo velho de projeto.
  // Tarefa 4 (D1): O projeto muda de derivação (de raiz global para diretório da sessão).
  // Linhas antigas com projeto constante nunca mais casam com a sessão que as escreveu.
  // UNIQUE(projeto, sessao) garante que qualquer sessão nova cria linha nova, então é seguro deletar.
  // Idempotente: DELETE de tabela vazia não causa erro.
  try {
    limparMarcaDagua(conexao);
  } catch (e) {
    // Falha na migração não trava schema creation — log e continua.
    if (process.env.DEBUG_SCHEMA) {
      console.error(`AVISO: falha na migração de marca_dagua: ${e.message}`);
    }
  }

  // Migração 4: adicionar coluna consolidada_em em observacoes (idempotente).
  // Tarefa 4 (D4): consolidar marca observações já consolidadas, para não reconsolidar.
  // ADD COLUMN IF NOT EXISTS garante que roda só uma vez — a coluna já existe em
  // novos bancos (schema acima), e é adicionada em legados (sem erro se já existe).
  try {
    conexao.exec(`
      ALTER TABLE observacoes ADD COLUMN consolidada_em TEXT;
    `);
  } catch (e) {
    // Se falhar com "duplicate column name", é porque já existe — ok.
    // Qualquer outro erro é inesperado, mas não trava a sessão.
    if (!e.message.includes('duplicate column')) {
      // Nota: não relançamos — a coluna pode estar parcialmente aplicada.
    }
  }

  // Migração 5: migração do FTS legado (C1).
  // Achado: CREATE VIRTUAL TABLE IF NOT EXISTS observacoes_fts é no-op quando
  // a tabela ANTIGA (`fts5(conteudo)` sem content=) existe — banco nunca migra
  // e buscar morre em silêncio (fase 2 não consegue achar observações recentes).
  // Estratégia: detectar se o DDL de observacoes_fts NÃO contém content= →
  // DROP TABLE observacoes_fts + recriar com content externo + rebuild FTS.
  // Idempotente: segunda rodada é no-op (a tabela já terá content=).
  try {
    const temFTS = conexao.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='observacoes_fts'
    `).all().length > 0;

    if (temFTS) {
      // Ler o DDL da tabela virtual
      const ddlRow = conexao.prepare(`
        SELECT sql FROM sqlite_master
        WHERE type='table' AND name='observacoes_fts'
      `).all()[0];

      if (ddlRow && ddlRow.sql) {
        const ddl = ddlRow.sql.toLowerCase();
        // Detectar se tem content=
        if (!ddl.includes('content=')) {
          // Tabela antiga sem content= — migrar
          if (process.env.DEBUG_SCHEMA) {
            console.error(`Migração FTS: detectada tabela observacoes_fts legada (sem content=)`);
          }

          // Apagar a tabela antiga
          conexao.exec(`DROP TABLE observacoes_fts;`);

          // Recriar com content externo
          conexao.exec(`
            CREATE VIRTUAL TABLE IF NOT EXISTS observacoes_fts USING fts5(
              conteudo,
              content='observacoes',
              content_rowid='id'
            );
          `);

          // Rebuild: fazer rebuild do índice FTS a partir da tabela externa
          conexao.exec(`
            INSERT INTO observacoes_fts(observacoes_fts) VALUES('rebuild');
          `);

          if (process.env.DEBUG_SCHEMA) {
            console.error(`Migração FTS: tabela recriada com content externo e índice rebuildo`);
          }
        }
      }
    }
  } catch (e) {
    // Falha na migração FTS não trava — banco pode estar em estado inesperado
    if (process.env.DEBUG_SCHEMA) {
      console.error(`AVISO: falha na migração FTS: ${e.message}`);
    }
  }

  // Migração 6: adicionar colunas substituida_por e reconciliada_em em
  // observacoes (idempotente). Tarefa 1 (D3, D6): `substituida_por` tira a
  // linha da injeção e da busca sem apagar nada; `reconciliada_em` marca
  // quando a observação passou pelo passo de reconciliação. ADD COLUMN
  // garante que roda só uma vez — as colunas já existem em novos bancos
  // (schema acima), e são adicionadas em legados (sem erro se já existem).
  try {
    conexao.exec(`
      ALTER TABLE observacoes ADD COLUMN substituida_por INTEGER;
    `);
  } catch (e) {
    // Se falhar com "duplicate column name", é porque já existe — ok.
    // Qualquer outro erro é inesperado, mas não trava a sessão.
    if (!e.message.includes('duplicate column')) {
      // Nota: não relançamos — a coluna pode estar parcialmente aplicada.
    }
  }
  try {
    conexao.exec(`
      ALTER TABLE observacoes ADD COLUMN reconciliada_em TEXT;
    `);
  } catch (e) {
    // Se falhar com "duplicate column name", é porque já existe — ok.
    // Qualquer outro erro é inesperado, mas não trava a sessão.
    if (!e.message.includes('duplicate column')) {
      // Nota: não relançamos — a coluna pode estar parcialmente aplicada.
    }
  }
}

// Migração de observacoes: garantir que tem UNIQUE(projeto, origem).
// Detecta se a constraint está correta, e se não, recria a tabela.
// Tarefa 20 (D20): TRANSAÇÃO ATÔMICA — RENAME, CREATE, INSERT, DROP numa transação.
// RECUPERAÇÃO: também detecta e recupera de estado quebrado (observacoes_backup órfã, observacoes ausente).
function migraoesObservacoes(conexao) {
  // Verificar se a tabela observacoes existe
  const temTabela = conexao.prepare(`
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='observacoes'
  `).all().length > 0;

  // Verificar se observacoes_backup existe (tabela órfã de uma migração interrompida)
  const temBackup = conexao.prepare(`
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='observacoes_backup'
  `).all().length > 0;

  // RECUPERAÇÃO: Se observacoes não existe mas observacoes_backup sim, recuperar
  if (!temTabela && temBackup) {
    try {
      conexao.exec('BEGIN TRANSACTION');

      // Criar tabela nova com constraint correto
      conexao.exec(`
        CREATE TABLE observacoes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          projeto TEXT NOT NULL,
          conteudo TEXT NOT NULL,
          criada_em TEXT NOT NULL,
          origem TEXT,
          UNIQUE(projeto, origem)
        );
      `);

      // Copiar dados de backup para observacoes
      conexao.exec(`
        INSERT INTO observacoes (id, projeto, conteudo, criada_em, origem)
        SELECT id, projeto, conteudo, criada_em, origem FROM observacoes_backup
      `);

      // Remover backup
      conexao.exec(`DROP TABLE observacoes_backup;`);

      // Recriar índices
      conexao.exec(`CREATE INDEX IF NOT EXISTS idx_observacoes_projeto ON observacoes(projeto);`);

      conexao.exec('COMMIT');

      if (process.env.DEBUG_SCHEMA) {
        console.error(`Recuperação: tabela observacoes restaurada de backup`);
      }
      return;
    } catch (e) {
      try {
        conexao.exec('ROLLBACK');
      } catch { }
      throw new Error(`Falha na recuperação de observacoes_backup: ${e.message}`);
    }
  }

  if (!temTabela) {
    // Tabela não existe — será criada pelo CREATE TABLE IF NOT EXISTS acima.
    return;
  }

  // Verificar se há constraint UNIQUE(projeto, origem) correta — reutilizar função existente (Tarefa 23 - D18)
  const temConstraintCorreta = verificarConstraintUniqueProjetoOrigem(conexao);

  if (temConstraintCorreta) {
    // Constraint já está correta — nada a fazer.
    return;
  }

  // Constraint está errada ou faltando — migrar.
  // CRÍTICO: Preservar TODAS as linhas. Nenhuma pode ser descartada em silêncio.
  // 1. Contar quantas linhas vamos migrar
  const contagem = conexao.prepare(`SELECT COUNT(*) as cnt FROM observacoes`).all();
  const cntAntes = contagem[0].cnt;

  // 2. Ler todos os dados em memória
  const dados = conexao.prepare(`
    SELECT id, projeto, conteudo, criada_em, origem
    FROM observacoes
    ORDER BY id
  `).all();

  // 3. Detectar colisões: (projeto, origem) duplicado OU origem NULL
  // Estratégia: para qualquer linha que colida, adicionar sufixo _dedup_N na origem.
  const chaveParaIds = {}; // (projeto, origem) → lista de IDs
  const origemNova = {}; // ID → nova origem (com sufixo se necessário)

  for (const row of dados) {
    const chave = row.projeto + '\x00' + (row.origem || ''); // Separador \x00 para disambiguar
    if (!chaveParaIds[chave]) {
      chaveParaIds[chave] = [];
    }
    chaveParaIds[chave].push(row.id);
  }

  // Aplicar sufixos apenas a linhas que colidem
  let temColidentes = false;
  let sufixoCounter = 0;
  for (const [chave, ids] of Object.entries(chaveParaIds)) {
    if (ids.length > 1) {
      temColidentes = true;
      // Múltiplas linhas com mesma chave: adicionar sufixo a todas
      for (const id of ids) {
        const row = dados.find(r => r.id === id);
        origemNova[id] = row.origem === null
          ? `_dedup_${sufixoCounter}`
          : `${row.origem}_dedup_${sufixoCounter}`;
        sufixoCounter++;
      }
    } else {
      // Sem colisão: mantém origem como está
      origemNova[ids[0]] = dados.find(r => r.id === ids[0]).origem;
    }
  }

  if (process.env.DEBUG_SCHEMA && temColidentes) {
    console.error(`Migração de observacoes: ${cntAntes} linhas com colisões detectadas`);
    console.error(`  Estratégia: adicionar sufixo _dedup_N para origem(s) colidentes`);
  }

  // TRANSAÇÃO: Tarefa 20 — RENAME, CREATE, INSERT, DROP são ATÔMICOS.
  // Se falhar em qualquer ponto, ROLLBACK desfaz tudo e tabela fica intacta.
  // Se completar, COMMIT persiste tudo.
  try {
    conexao.exec('BEGIN TRANSACTION');

    // 4. Renomear tabela antiga
    conexao.exec(`ALTER TABLE observacoes RENAME TO observacoes_backup;`);

    // 5. Criar nova tabela com constraint correto
    conexao.exec(`
      CREATE TABLE observacoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projeto TEXT NOT NULL,
        conteudo TEXT NOT NULL,
        criada_em TEXT NOT NULL,
        origem TEXT,
        UNIQUE(projeto, origem)
      );
    `);

    // 6. Copiar dados — TODOS, com origem modificada se colidia
    const insertStmt = conexao.prepare(`
      INSERT INTO observacoes (id, projeto, conteudo, criada_em, origem)
      VALUES (?, ?, ?, ?, ?)
    `);

    for (const row of dados) {
      insertStmt.run(
        row.id,
        row.projeto,
        row.conteudo,
        row.criada_em,
        origemNova[row.id]
      );
    }

    // 7. Apagar tabela de backup
    conexao.exec(`DROP TABLE observacoes_backup;`);

    // 8. Recriar os índices (são idempotentes com IF NOT EXISTS)
    conexao.exec(`CREATE INDEX IF NOT EXISTS idx_observacoes_projeto ON observacoes(projeto);`);

    // 9. Verificar que nenhuma linha foi perdida
    const cntDepois = conexao.prepare(`SELECT COUNT(*) as cnt FROM observacoes`).all()[0].cnt;
    if (cntDepois !== cntAntes) {
      throw new Error(`MIGRAÇÃO ABORTADA: ${cntAntes} linhas antes, ${cntDepois} depois. Dados perdidos!`);
    }

    // COMMIT persiste a migração
    conexao.exec('COMMIT');

    if (process.env.DEBUG_SCHEMA) {
      console.error(`Migração de observacoes: ${cntAntes} linhas antes, ${cntDepois} linhas depois`);
      if (temColidentes) {
        console.error(`  OK: colisões resolvidas com sufixos _dedup_N (nenhuma linha perdida)`);
      }
    }
  } catch (e) {
    // ROLLBACK desfaz tudo se algo falhar
    try {
      conexao.exec('ROLLBACK');
    } catch {
      // Se ROLLBACK falhar, pelo menos tentamos
    }
    // Relançar o erro para o chamador tratar
    throw e;
  }
}

// Retorna schema como JSON (comando `esquema --json`).
function extrairSchema(conexao) {
  const tabelas = {};

  // Listar todas as tabelas criadas por nós (excluir sqlite_* internas).
  const resultado = conexao.prepare(
    `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'`
  ).all();

  for (const { name: tabela } of resultado) {
    // PRAGMA table_info retorna info de cada coluna.
    const colunas = conexao.prepare(`PRAGMA table_info(${tabela})`).all();
    const colunasFormatadas = {};

    for (const { name: nome, type: tipo, notnull, pk } of colunas) {
      colunasFormatadas[nome] = {
        tipo,
        naoNulo: notnull === 1,
        chavePrimaria: pk === 1,
      };
    }

    tabelas[tabela] = colunasFormatadas;
  }

  return tabelas;
}

// Popula o índice FTS5 com observações existentes no banco.
// Tarefa 1 (D24): Com conteúdo externo (content='observacoes'), usa comando 'rebuild'
// em vez de DELETE+INSERT individual, por segurança e performance.
function popularFts5(conexao) {
  try {
    // Reconstruir índice FTS5 do zero via comando 'rebuild'.
    // Com conteúdo externo, o comando 'rebuild' reconstrói a partir da tabela
    // observacoes sem duplicação ou risco de dessincronização.
    conexao.exec('INSERT INTO observacoes_fts(observacoes_fts) VALUES(\'rebuild\')');
  } catch (e) {
    // Não é crítico falhar aqui; FTS5 pode ser reconstruída depois.
    // Mas logamos para debug.
    console.error(`AVISO: não consegui popular FTS5: ${e.message}`);
  }
}

// Garante que o esquema do banco em `raiz` está em dia: cria o diretório,
// abre/cria o banco, recupera de estado quebrado e roda as migrações
// idempotentes de `criarSchema` + a repopulação do FTS5. É a MESMA lógica
// que `iniciar` sempre rodou — extraída para cá (Tarefa 5, emenda
// 2026-09-18) porque `manutencao` também precisa garanti-lo antes de
// reconciliar/consolidar: o banco real do usuário nunca passou por `iniciar`
// com as colunas novas, e sem isto a passada diária falharia para sempre
// com "no such column: substituida_por". Lança se `abrirBanco`/`criarSchema`
// falharem — mesmo comportamento de antes, quando esse código vivia dentro
// de `cmdIniciar`.
function garantirEsquema() {
  const { raiz, caminhoDb } = resolverCaminhos();

  // Criar diretório se não existe.
  fs.mkdirSync(raiz, { recursive: true });

  const conexao = abrirBanco(caminhoDb);

  // Recuperar de estado quebrado (observacoes_backup órfã) ANTES de criar schema
  recuperarSeNecessario(conexao);

  criarSchema(conexao);

  // Popular índice FTS5 (idempotente).
  popularFts5(conexao);

  conexao.close();
}

// Comando: iniciar — criar/abrir o banco, verificar schema.
function cmdIniciar() {
  const { caminhoDb, projeto } = resolverCaminhos();

  garantirEsquema();

  console.log(`ok: banco em ${caminhoDb} (projeto: ${projeto})`);

  // Retornar exit 0 implicitamente.
}

// Comando: esquema [--json] — listar o schema do banco.
function cmdEsquema() {
  const { caminhoDb } = resolverCaminhos();

  if (!fs.existsSync(caminhoDb)) {
    console.error(`ERRO: banco não existe em ${caminhoDb}`);
    console.error('rode: node scripts/memoria.cjs iniciar');
    process.exit(1);
  }

  const conexao = abrirBanco(caminhoDb);
  const schema = extrairSchema(conexao);
  conexao.close();

  // Verificar se --json foi passado (segunda linha de CLI).
  const args = process.argv.slice(3);
  const ehJson = args.includes('--json');

  if (ehJson) {
    console.log(JSON.stringify(schema, null, 2));
  } else {
    // Formato legível para humanos.
    for (const [tabela, colunas] of Object.entries(schema)) {
      console.log(`\n${tabela}:`);
      for (const [nome, info] of Object.entries(colunas)) {
        const flags = [
          info.chavePrimaria ? 'PK' : '',
          info.naoNulo ? 'NOT NULL' : 'NULL',
        ].filter(f => f).join(' ');
        console.log(`  ${nome}: ${info.tipo} (${flags})`);
      }
    }
  }
}

// Comando: buscar [--texto "..."] [--projeto "..."] [--limite N] [--json]
// Busca observações usando FTS5. Degradação: banco ausente/vazio/corrompido
// devolve resultado vazio com exit 0, nunca erro.
function cmdBuscar() {
  const { caminhoDb } = resolverCaminhos();

  // Parser de argumentos simples.
  function arg(nome) {
    const i = process.argv.indexOf(`--${nome}`);
    if (i === -1 || i + 1 >= process.argv.length) return null;
    return process.argv[i + 1];
  }

  const texto = arg('texto') || '';
  const projeto = arg('projeto') || null;
  const limite = parseInt(arg('limite') || '10', 10);
  const ehJson = process.argv.includes('--json');

  // Resultado padrão: array vazio (degradação).
  let resultados = [];

  try {
    // Degradação: banco não existe — devolver array vazio, exit 0.
    if (!fs.existsSync(caminhoDb)) {
      if (ehJson) {
        console.log(JSON.stringify(resultados, null, 2));
      } else {
        console.log('(banco não existe)');
      }
      return;
    }

    const conexao = abrirBanco(caminhoDb);

    // Se há texto, usar FTS5; senão, listar recentes.
    let query;
    const params = { limite };

    if (texto) {
      // Busca FTS5: combinar conteúdo com projeto se fornecido.
      // Tarefa 3 (D3): filtroVivas('o.') tira a substituída da busca.
      query = `
        SELECT o.id, o.projeto, o.conteudo, o.criada_em
        FROM observacoes o
        WHERE o.id IN (
          SELECT rowid FROM observacoes_fts WHERE conteudo MATCH :fts_query
        )
        ${filtroVivas('o.')}
      `;
      params.fts_query = texto; // FTS5 syntax: "palavra" ou "palavra1 AND palavra2"

      if (projeto) {
        query += ' AND o.projeto = :projeto';
        params.projeto = projeto;
      }
    } else {
      // Sem texto: listar recentes de um projeto (se fornecido).
      // Tarefa 3 (D3): WHERE 1=1 ancora o AND de filtroVivas() mesmo sem --projeto.
      query = `SELECT id, projeto, conteudo, criada_em FROM observacoes WHERE 1=1 ${filtroVivas()}`;

      if (projeto) {
        query += ' AND projeto = :projeto';
        params.projeto = projeto;
      }
    }

    query += ' ORDER BY criada_em DESC LIMIT :limite';

    const stmt = conexao.prepare(query);
    try {
      resultados = stmt.all(params);
    } catch (e) {
      // Texto livre com pontuação ("claude-mem", "a:b", aspas) é sintaxe
      // inválida de FTS5 e caía no catch de fora como banco com defeito,
      // devolvendo vazio. A sintaxe crua continua valendo quando é válida;
      // só no erro repete com cada termo citado, unidos por AND implícito.
      const termos = texto && (String(texto).match(/[\p{L}\p{N}]+/gu) || []);
      if (!termos) throw e;
      params.fts_query = termos.map(t => `"${t}"`).join(' ');
      resultados = termos.length ? stmt.all(params) : [];
    }
    conexao.close();
  } catch (e) {
    // Degradação: banco corrompido ou outro erro — resultado vazio, exit 0.
    // Aviso só no stderr para não poluir JSON de saída.
    if (!ehJson) {
      console.error(`AVISO: não consegui buscar no banco: ${e.message}`);
    }
    resultados = [];
  }

  // Saída.
  if (ehJson) {
    console.log(JSON.stringify(resultados, null, 2));
  } else {
    if (!resultados.length) {
      console.log('(nenhum resultado)');
      return;
    }
    for (const obs of resultados) {
      console.log(`[${obs.id}] ${obs.projeto} - ${obs.criada_em}`);
      console.log(`  ${obs.conteudo.substring(0, 100)}`);
    }
  }
}

// Comando: backup — copiar o banco para pasta de backup com timestamp.
// Garante consistência com WAL ativo (D7) usando VACUUM INTO.
function cmdBackup() {
  const { raiz, caminhoDb } = resolverCaminhos();

  if (!fs.existsSync(caminhoDb)) {
    console.error(`ERRO: banco não existe em ${caminhoDb}`);
    process.exit(1);
  }

  const dirBackup = path.join(raiz, '.rainforest-backups');
  fs.mkdirSync(dirBackup, { recursive: true });

  // Timestamp ISO local (não UTC).
  const agora = new Date();
  const ano = agora.getFullYear();
  const mes = String(agora.getMonth() + 1).padStart(2, '0');
  const dia = String(agora.getDate()).padStart(2, '0');
  const horas = String(agora.getHours()).padStart(2, '0');
  const minutos = String(agora.getMinutes()).padStart(2, '0');
  const segundos = String(agora.getSeconds()).padStart(2, '0');

  const timestamp = `${ano}-${mes}-${dia}T${horas}-${minutos}-${segundos}`;
  const caminhoBackup = path.join(dirBackup, `rainforest-${timestamp}.db`);

  // Garantir consistência com WAL ativo (D7): usar VACUUM para consolidar WAL,
  // depois fazer checkpoint e cópia simples. Isso garante que o .db tem tudo
  // e pode ser copiado de forma consistente.
  //
  // CRÍTICO: Tarefa 23 (D18 refinado) — banco corrompido é erro FATAL. Separamos
  // em dois try/catch: (1) abertura do banco é obrigatória, (2) consolidação é
  // degradação. Antes disso, abertura era capturada junto com consolidação,
  // permitindo backup de banco corrompido → perda de dado de usuário.
  let conexao;
  try {
    conexao = abrirBanco(caminhoDb);
  } catch (e) {
    console.error(`ERRO: banco corrompido ou inacessível (${e.message})`);
    process.exit(1);
  }

  // Agora que temos conexão válida, tentar consolidar (nice-to-have)
  try {
    // VACUUM consolida todo conteúdo no arquivo .db, eliminando WAL
    conexao.exec('VACUUM');

    // Fazer checkpoint TRUNCATE para fechar qualquer WAL restante
    conexao.exec('PRAGMA wal_checkpoint(TRUNCATE)');

    conexao.close();
  } catch (e) {
    // Consolidação falhou, mas banco é válido — ignorar e continuar
    console.error(`AVISO: não consegui consolidar WAL (${e.message}), continuando`);
    try { conexao.close(); } catch (_) {}
  }

  // Agora copiar arquivo binário. Sem WAL ativo, é seguro.
  try {
    fs.copyFileSync(caminhoDb, caminhoBackup);
  } catch (e) {
    console.error(`ERRO: não consegui copiar banco para backup: ${e.message}`);
    process.exit(1);
  }

  console.log(`backup: ${caminhoBackup}`);

  // Rotação: manter apenas os N backups mais recentes, nunca apagando o mais recente.
  // Teto conservador (5 cópias) para não encher disco — cada banco é ~MB.
  // Regra crítica (D7): a rotação NUNCA apaga a cópia mais recente.
  const teto = 5;
  const arquivos = fs.readdirSync(dirBackup)
    .filter(f => f.startsWith('rainforest-') && f.endsWith('.db'))
    .sort()
    .reverse(); // Ordena descendente por timestamp: mais recente primeiro

  for (let i = teto; i < arquivos.length; i++) {
    const antigo = path.join(dirBackup, arquivos[i]);
    fs.unlinkSync(antigo);
  }
}

// Função auxiliar: ler FOCO.md e extrair campos estruturados (datas, prazos, pastas).
// Retorna array de objetos {campo, valor, linha}.
function lerFoco(caminhoFoco) {
  if (!fs.existsSync(caminhoFoco)) {
    return [];
  }

  try {
    const conteudo = fs.readFileSync(caminhoFoco, 'utf8');
    const resultados = [];

    // Extrair datas em formato YYYY-MM-DD
    const reData = /\d{4}-\d{2}-\d{2}/g;
    let match;
    while ((match = reData.exec(conteudo)) !== null) {
      resultados.push({
        campo: 'data',
        valor: match[0],
        tipo: 'data',
      });
    }

    // Extrair seções de Headers (## Titulo)
    const reHeader = /^##\s+(.+)$/gm;
    while ((match = reHeader.exec(conteudo)) !== null) {
      resultados.push({
        campo: 'titulo',
        valor: match[1].trim(),
        tipo: 'header',
      });
    }

    // Extrair caminhos/pastas (linhas com `/` indicando estrutura)
    const reFolder = /^-\s+(.+?\/[^\n]+)$/gm;
    while ((match = reFolder.exec(conteudo)) !== null) {
      resultados.push({
        campo: 'pasta',
        valor: match[1].trim(),
        tipo: 'folder',
      });
    }

    return resultados;
  } catch (e) {
    console.error(`AVISO: não consegui ler FOCO.md: ${e.message}`);
    return [];
  }
}

// Função auxiliar: ler ideias.jsonl e extrair metadados das ideias.
// Retorna array de objetos com campos: id, titulo, projeto, status, tipo, plantada_em, gancho, conteudo.
function lerIdeias(caminhoIdeias) {
  if (!fs.existsSync(caminhoIdeias)) {
    return [];
  }

  try {
    const conteudo = fs.readFileSync(caminhoIdeias, 'utf8');
    const linhas = conteudo.split('\n').filter(l => l.trim());
    const ideias = [];

    for (const linha of linhas) {
      try {
        const ideia = JSON.parse(linha);
        ideias.push({
          id: ideia.id || null,
          titulo: ideia.titulo || '',
          projeto: ideia.projeto || 'desconhecido',
          status: ideia.status || 'plantada',
          tipo: ideia.tipo || 'ideia',
          plantada_em: ideia.plantada_em || ideia.data || null,
          gancho: ideia.gancho || '',
          // Concatenar campos para busca textual
          conteudo: [
            ideia.titulo,
            ideia.descricao,
            ideia.contexto,
            ideia.ao_colher,
          ].filter(x => x).join(' '),
        });
      } catch (e) {
        // Ignorar linhas malformadas
      }
    }

    return ideias;
  } catch (e) {
    console.error(`AVISO: não consegui ler ideias.jsonl: ${e.message}`);
    return [];
  }
}

// Comando: reindexar — reconstruir índice DERIVADO do zero a partir de FOCO.md e ideias.jsonl.
// Garantia: apagar o índice não perde dado nenhum — tudo é rederivável dos arquivos fonte.
// Tabelas DERIVADAS: indice_foco e indice_ideias. Nunca toca observacoes, resumos, prompts, marca_dagua.
function cmdReindexar() {
  const { raiz, caminhoDb, projeto } = resolverCaminhos();

  // Degradação: banco não existe — criar.
  if (!fs.existsSync(caminhoDb)) {
    fs.mkdirSync(raiz, { recursive: true });
    const conexao = abrirBanco(caminhoDb);
    criarSchema(conexao);
    conexao.close();
  }

  try {
    const conexao = abrirBanco(caminhoDb);

    // Limpar APENAS as tabelas derivadas. Nunca tocar em observacoes, resumos, prompts ou marca_dagua.
    try {
      conexao.exec('DELETE FROM indice_foco');
    } catch (e) {
      // Ignorar se não existe.
    }

    try {
      conexao.exec('DELETE FROM indice_ideias');
    } catch (e) {
      // Ignorar se não existe.
    }

    // Ler fontes de verdade.
    const caminhoFoco = path.join(raiz, 'FOCO.md');
    const caminhoIdeias = path.join(raiz, 'ideias.jsonl');

    const focoItems = lerFoco(caminhoFoco);
    const ideias = lerIdeias(caminhoIdeias);

    const agora = new Date().toISOString();

    // Popular indice_ideias com metadados das ideias (para busca e join).
    // Campos: id, titulo, projeto, status, tipo, plantada_em, gancho, conteudo_busca.
    const stmtInsertIdeias = conexao.prepare(
      `INSERT INTO indice_ideias
       (projeto, ideia_id, titulo, status, tipo, plantada_em, gancho, conteudo_busca, indexada_em)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );

    for (const ideia of ideias) {
      if (ideia.titulo) {
        try {
          stmtInsertIdeias.run(
            projeto,
            ideia.id,
            ideia.titulo,
            ideia.status,
            ideia.tipo,
            ideia.plantada_em,
            ideia.gancho,
            ideia.conteudo,
            agora
          );
        } catch (e) {
          // Ignorar duplicatas
        }
      }
    }

    // Popular indice_foco com campos estruturados de FOCO.md.
    const stmtInsertFoco = conexao.prepare(
      `INSERT INTO indice_foco (projeto, tipo, valor, indexada_em)
       VALUES (?, ?, ?, ?)`
    );

    for (const item of focoItems) {
      try {
        stmtInsertFoco.run(
          projeto,
          item.tipo,
          item.valor,
          agora
        );
      } catch (e) {
        // Ignorar duplicatas
      }
    }

    // Reconstruir índice FTS5 a partir das observações.
    // Tarefa 1 (D24): Com conteúdo externo, usa 'rebuild' em vez de DELETE.
    try {
      conexao.exec('INSERT INTO observacoes_fts(observacoes_fts) VALUES(\'rebuild\')');
    } catch (e) {
      // Ignorar se não existe ou falha — não é crítico.
    }

    console.log(`ok: índice derivado reconstruído (${caminhoDb})`);
    conexao.close();
  } catch (e) {
    // Degradação: erro ao reindexar — exit 0 com aviso.
    console.error(`AVISO: não consegui reindexar: ${e.message}`);
  }
}

// Chamada à LLM isolada atrás de função para permitir mock em testes.
// Mesmo padrão que observar.cjs, Tarefa 12 (D14).
// Retorna promise com resumo (string) ou null se falhar.
async function chamarLLMParaConsolidar(textoDasObservacoes) {
  // Permitir mock via variável de ambiente (testes)
  if (process.env.TESTADOR_CHAMAR_LLM) {
    try {
      const modulo = require(process.env.TESTADOR_CHAMAR_LLM);
      const resultado = await modulo.chamarLLM(textoDasObservacoes);
      return resultado;
    } catch (e) {
      console.error(`AVISO: não consegui carregar mock de LLM: ${e.message}`);
      return null;
    }
  }

  // Invocar CLI claude com spawn (mesmo padrão que observar.cjs).
  const { spawn } = require('child_process');
  const os = require('os');

  const executavel = acharExecutavelClaude();
  if (!executavel) {
    console.error('AVISO: não encontrei o executável `claude` no PATH');
    return null;
  }

  const tempDir = os.tmpdir();
  const TETO_ARGUMENTO = 16000;

  if (textoDasObservacoes.length > TETO_ARGUMENTO) {
    console.error(`AVISO: texto acima do teto (${textoDasObservacoes.length} > ${TETO_ARGUMENTO})`);
    return null;
  }

  const prompt = `Resuma as seguintes 10 observacoes em uma sintese curta (2-3 frases):\n\n${textoDasObservacoes}`;

  return new Promise((resolve) => {
    const timeout = 60000;
    const timer = setTimeout(() => {
      console.error('AVISO: chamada à LLM expirou (timeout 60s)');
      resolve(null);
    }, timeout);

    try {
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
        console.error(`AVISO: erro ao chamar claude em "${executavel}": ${error.message}`);
        resolve(null);
      });

      child.on('close', (code) => {
        clearTimeout(timer);

        if (code !== 0) {
          console.error(`AVISO: claude retornou exit code ${code}`);
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
      console.error(`AVISO: erro ao invocar claude em "${executavel}": ${e.message}`);
      resolve(null);
    }
  });
}


// Grava resumo no banco.
// Retorna true se sucesso, false se falha.
function gravarResumo(conexao, { projeto, titulo, conteudo }) {
  try {
    const agora = new Date().toISOString();

    const stmt = conexao.prepare(`
      INSERT INTO resumos (projeto, titulo, conteudo, criada_em)
      VALUES (?, ?, ?, ?)
    `);

    stmt.run(projeto, titulo, conteudo, agora);
    return true;
  } catch (e) {
    console.error(`AVISO: erro ao gravar resumo: ${e.message}`);
    return false;
  }
}

// Marca observações com consolidada_em (atomicamente em transação).
// Retorna true se sucesso, false se falha.
function marcarConsolidadas(conexao, { projeto, ids }) {
  if (!ids || ids.length === 0) {
    return true;
  }

  try {
    const agora = new Date().toISOString();

    // Usar transação para garantir atomicidade
    conexao.exec('BEGIN TRANSACTION');

    const placeholders = ids.map(() => '?').join(',');
    const stmt = conexao.prepare(`
      UPDATE observacoes
      SET consolidada_em = ?
      WHERE projeto = ? AND id IN (${placeholders})
    `);

    const params = [agora, projeto, ...ids];
    stmt.run(...params);

    conexao.exec('COMMIT');
    return true;
  } catch (e) {
    try {
      conexao.exec('ROLLBACK');
    } catch (_) {}
    console.error(`AVISO: erro ao marcar consolidadas: ${e.message}`);
    return false;
  }
}

// C4: Consolida resumo + marca observações ATOMICAMENTE numa transação.
// Se qualquer parte falha, ROLLBACK descarta ambas (nem resumo nem marca ficam gravados).
// `quando` (opcional): timestamp ISO a gravar em criada_em (resumo) e
// consolidada_em (marca). Tarefa 4 (D7): cmdConsolidar passa um relógio
// monotônico por pedaço, para garantir consolidada_em DISTINTO entre
// pedaços mesmo que o mock de LLM responda rápido demais para o relógio de
// parede avançar — é por esse valor que o critério 1 prova que nenhum
// resumo mistura dois grupos. Sem argumento, usa o relógio de parede.
// Retorna true se sucesso, false se falha.
function consolidarAtomico(conexao, { projeto, titulo, conteudo, ids, quando }) {
  if (!ids || ids.length === 0) {
    return true;
  }

  try {
    const agora = quando || new Date().toISOString();

    // Uma transação única para ambas operações
    conexao.exec('BEGIN TRANSACTION');

    // 1. Gravar resumo
    const stmtResumo = conexao.prepare(`
      INSERT INTO resumos (projeto, titulo, conteudo, criada_em)
      VALUES (?, ?, ?, ?)
    `);
    stmtResumo.run(projeto, titulo, conteudo, agora);

    // 2. Marcar observações consolidadas
    const placeholders = ids.map(() => '?').join(',');
    const stmtMarca = conexao.prepare(`
      UPDATE observacoes
      SET consolidada_em = ?
      WHERE projeto = ? AND id IN (${placeholders})
    `);
    const params = [agora, projeto, ...ids];
    stmtMarca.run(...params);

    // Commit: ambas operações persistem juntas
    conexao.exec('COMMIT');
    return true;
  } catch (e) {
    // Rollback: desfaz ambas se qualquer uma falhar
    try {
      conexao.exec('ROLLBACK');
    } catch (_) {}
    console.error(`AVISO: erro ao consolidar atomicamente: ${e.message}`);
    return false;
  }
}

// Comando: consolidar — agrupar observações por grupo de origem, sintetizar
// via LLM, gravar resumos (Tarefa 4, D7).
//
// D7: em vez de lotes cronológicos de 10 a partir de 60 dias (misturava
// assuntos sem relação num resumo só, e nunca disparava — a observação mais
// antiga do acervo real tem 45 dias), agrupa por sqlGrupoDeOrigem() — a
// sessão de origem quando `origem` é `sessao:<id>:offset:<n>`; para o resto
// (as importadas do claude-mem, sem sessão nenhuma), (projeto, dia de
// criada_em) — a partir de DIAS_CONSOLIDACAO dias. Grupo com menos de 2
// observações não consolida (nada a sintetizar de uma linha só). Grupo maior
// que TETO_POR_GRUPO é fatiado em pedaços de até TETO_POR_GRUPO — o maior
// grupo de recurso medido tem 521 observações, e o TETO_ARGUMENTO de 16.000
// caracteres da chamada de LLM não aguenta isso. Cada pedaço vira UM resumo:
// nenhum resumo mistura dois grupos, porque todo pedaço nasce da leitura de
// um único grupo. No máximo TETO_GRUPOS pedaços por execução — sem esse teto
// a primeira execução dispararia ~340 chamadas de LLM de uma vez (medição do
// plano). NOTA: processa todos os grupos elegíveis, de todos os projetos —
// sessão de origem não pertence a um projeto só na consulta, é global.
const DIAS_CONSOLIDACAO = 30;
const TETO_GRUPOS = 10;

async function cmdConsolidar() {
  const { caminhoDb } = resolverCaminhos();

  if (!fs.existsSync(caminhoDb)) {
    // Lança em vez de `process.exit(1)` (Tarefa 5, emenda 2026-09-18): quem
    // chama via CLI (`main()`) captura e sai 1 do mesmo jeito; quem chama
    // via `cmdManutencao` precisa poder capturar sem o processo morrer no
    // meio da passada.
    throw new Error(`banco não existe em ${caminhoDb} — rode: node scripts/memoria.cjs iniciar`);
  }

  const conexao = abrirBanco(caminhoDb);

  try {
    // 1. Data limite: DIAS_CONSOLIDACAO dias atrás.
    const agora = new Date();
    const dataLimiteObj = new Date(agora.getTime() - DIAS_CONSOLIDACAO * 24 * 60 * 60 * 1000);
    const dataLimite = dataLimiteObj.toISOString();

    const grupoOrigem = sqlGrupoDeOrigem();

    // 2. Grupos elegíveis: vivos, não consolidados, DIAS_CONSOLIDACAO+ dias,
    // com 2+ observações. Mais antigos primeiro (MIN(criada_em) do grupo) —
    // os grupos mais velhos entram primeiro no teto de execução.
    const grupos = conexao.prepare(`
      SELECT (${grupoOrigem}) AS grupo, COUNT(*) as cnt, MIN(criada_em) as mais_antiga
      FROM observacoes
      WHERE consolidada_em IS NULL AND criada_em < ? ${filtroVivas()}
      GROUP BY grupo
      HAVING COUNT(*) >= 2
      ORDER BY mais_antiga ASC
    `).all(dataLimite);

    if (grupos.length === 0) {
      console.log(`nenhum grupo com 2+ observações de ${DIAS_CONSOLIDACAO}+ dias, nada a fazer`);
      conexao.close();
      return;
    }

    console.log(`${grupos.length} grupo(s) com 2+ observações de ${DIAS_CONSOLIDACAO}+ dias`);

    let totalResumosGravados = 0;
    // Relógio monotônico: cada pedaço grava consolidada_em em baseMs +
    // (índice do pedaço já gravado), garantindo timestamps distintos entre
    // pedaços mesmo que o mock de LLM responda no mesmo milissegundo.
    const baseMs = Date.now();

    // 3. Processar cada grupo, do mais velho ao mais novo, até TETO_GRUPOS
    // pedaços no total.
    for (const { grupo } of grupos) {
      if (totalResumosGravados >= TETO_GRUPOS) break;

      // Teto de observações por pedaço — o ponto único que a catraca de
      // mutação inverte (Tarefa 4). Grupo maior que isto vira mais de um
      // resumo; nenhum pedaço passa deste número.
      const TETO_POR_GRUPO = 30;

      // 4. Ler as observações vivas deste grupo, mais antigas primeiro.
      const observacoesGrupo = conexao.prepare(`
        SELECT id, projeto, conteudo, criada_em
        FROM observacoes
        WHERE consolidada_em IS NULL AND criada_em < ? AND (${grupoOrigem}) = ? ${filtroVivas()}
        ORDER BY criada_em ASC
      `).all(dataLimite, grupo);

      console.log(`grupo "${grupo}": ${observacoesGrupo.length} observação(ões) consolidáveis`);

      // 5. Fatiar em pedaços de até TETO_POR_GRUPO — cada pedaço vem da
      // leitura de UM grupo só, então nenhum resumo mistura dois grupos.
      for (let i = 0; i < observacoesGrupo.length; i += TETO_POR_GRUPO) {
        if (totalResumosGravados >= TETO_GRUPOS) break;

        const pedaco = observacoesGrupo.slice(i, i + TETO_POR_GRUPO);
        const ids = pedaco.map(o => o.id);
        const projetoPedaco = pedaco[0].projeto;

        // Formatar para LLM: concatenar conteúdos.
        const textoDasObservacoes = pedaco
          .map((obs, idx) => `${idx + 1}. ${obs.conteudo}`)
          .join('\n');

        console.log(`  grupo "${grupo}": chamando LLM para ${pedaco.length} observações`);

        // 6. Chamar LLM (falha deixa o pedaço intacto para a próxima rodada).
        const resumo = await chamarLLMParaConsolidar(textoDasObservacoes);

        if (!resumo) {
          console.log(`  grupo "${grupo}": LLM falhou, pedaço intacto para próxima rodada`);
          continue;
        }

        // 7. C4: Consolidar atomicamente (resumo + marca numa transação).
        // Se falhar em qualquer parte, ROLLBACK desfaz ambas — nem resumo
        // nem marca ficam. `quando` vem do relógio monotônico por pedaço.
        const titulo = resumo.substring(0, 80); // Primeiros 80 caracteres como título
        const quando = new Date(baseMs + totalResumosGravados).toISOString();
        const sucesso = consolidarAtomico(conexao, {
          projeto: projetoPedaco,
          titulo,
          conteudo: resumo,
          ids,
          quando,
        });

        if (!sucesso) {
          console.log(`  grupo "${grupo}": falha ao consolidar atomicamente, pedaço intacto`);
          continue;
        }

        totalResumosGravados++;
        console.log(`  grupo "${grupo}": ok (resumo gravado, ${pedaco.length} observações marcadas)`);
      }
    }

    // 8. Relatório final.
    console.log(`consolidacao completa: ${totalResumosGravados} resumo(s) total gravado(s)`);

    conexao.close();
  } catch (e) {
    // Lança em vez de `process.exit(1)` (Tarefa 5, emenda 2026-09-18) — mesmo
    // motivo do `throw` acima: `main()` (CLI direta) captura isto e imprime
    // `ERRO: <mensagem>` antes de sair 1, preservando o exit code de quem
    // chama `consolidar` direto da linha de comando; `cmdManutencao` captura
    // e segue para o passo seguinte sem matar o processo destacado.
    try { conexao.close(); } catch (_) {}
    throw e;
  }
}

// Comando `reconciliar` (Tarefa 2, D2/D3/D4/D6).
//
// K = 5 candidatas por observação sondada, do FTS5, mesmo `projeto`, ordenadas
// por bm25(observacoes_fts) — sem limiar numérico de similaridade: quem decide
// parecença é a LLM (D4). N = 200 observações reconciliadas por execução,
// mais recentes primeiro — teto do D6, para não estourar custo de LLM numa
// passada só.
const K_CANDIDATAS = 5;
const TETO_RECONCILIAR = 200;

// Ações válidas na resposta da LLM. Qualquer outra coisa cai em 'store' — o
// lado seguro do D3 (nunca inventa update/merge a partir de resposta que não
// entendemos).
const ACOES_RECONCILIACAO_VALIDAS = new Set(['store', 'update', 'merge', 'skip']);

// Constrói uma query MATCH segura para o FTS5 a partir de texto livre.
// Passar o conteúdo cru (com pontuação, aspas, dois-pontos) direto como MATCH
// quebra a sintaxe do FTS5 (reservada para AND/OR/NOT/coluna:termo/etc). Aqui
// tokenizamos por letra/dígito (Unicode, cobre acento) e citamos cada termo
// entre aspas duplas — frase literal, sem sintaxe especial — unindo por OR.
// Retorna null se não sobrar termo nenhum (ex.: texto só com pontuação).
function construirQueryFts5(texto) {
  const tokens = (String(texto || '').match(/[\p{L}\p{N}]+/gu) || []).filter(t => t.length > 0);
  if (tokens.length === 0) return null;
  return tokens.map(t => `"${t.replace(/"/g, '""')}"`).join(' OR ');
}

// Busca até K_CANDIDATAS observações parecidas com `obs`, no mesmo projeto,
// via FTS5 + bm25. Exclui a própria observação e as já substituídas
// (substituida_por IS NOT NULL) — candidata substituída não é alvo válido.
// Degradação: erro de SQL (ex.: query MATCH malformada) devolve lista vazia,
// nunca lança.
function buscarCandidatas(conexao, obs) {
  const query = construirQueryFts5(obs.conteudo);
  if (!query) return [];

  try {
    return conexao.prepare(`
      SELECT o.id, o.conteudo, o.criada_em
      FROM observacoes_fts
      JOIN observacoes o ON o.id = observacoes_fts.rowid
      WHERE observacoes_fts MATCH :query
        AND o.projeto = :projeto
        AND o.id != :id
        AND o.substituida_por IS NULL
      ORDER BY bm25(observacoes_fts)
      LIMIT :k
    `).all({ query, projeto: obs.projeto, id: obs.id, k: K_CANDIDATAS });
  } catch (e) {
    console.error(`AVISO: falha ao buscar candidatas para observação ${obs.id}: ${e.message}`);
    return [];
  }
}

// Monta o texto que vai para a LLM: a observação sondada e suas candidatas.
//
// Achado 1 da revisão (2026-09-16): rotular a sondada como "nova" é falso
// quando a varredura do acervo (D6) sonda observações antigas — 88% do
// corpus são as importadas do claude-mem, as mais antigas dele. Sem data
// nenhuma, a LLM decide a direção só pela etiqueta, e "nova" numa observação
// velha inverte o update. Carrega `criada_em` da sondada e de cada candidata
// e chama a sondada pelo que ela é (a observação em exame), nunca "nova" —
// a LLM decide a direção pela data, não pela etiqueta.
function formatarPromptReconciliacao(observacao, candidatas) {
  const linhasCandidatas = candidatas
    .map((c) => `- [id=${c.id}, criada_em=${c.criada_em}] ${c.conteudo}`)
    .join('\n');

  return [
    'Observacao sondada (em exame), com a data em que foi criada:',
    `[id=${observacao.id}, criada_em=${observacao.criada_em}] ${observacao.conteudo}`,
    '',
    'Candidatas parecidas, mesmo projeto, com a data em que foram criadas (busca por texto, nao por LLM):',
    linhasCandidatas || '(nenhuma)',
    '',
    'Use as datas para decidir a direcao: em "update", quem esta desatualizado e quem corrige se decide pela data, nao pela ordem em que aparecem aqui.',
    '',
    'Decida a acao para a observacao sondada:',
    '- store: nova, sem relacao com nenhuma candidata',
    '- update: a observacao sondada atualiza uma candidata desatualizada (informe alvo_id)',
    '- merge: a observacao sondada e uma candidata sao complementares e devem se fundir (informe alvo_id)',
    '- skip: a observacao sondada ja esta coberta por uma candidata, descarte',
    '',
    'Responda em JSON estrito, sem texto antes ou depois:',
    '{"acao": "store"|"update"|"merge"|"skip", "alvo_id": <id da candidata ou null>}',
  ].join('\n');
}

// Interpreta a resposta bruta da LLM. Resposta ausente, que não é JSON válido,
// ou com ação desconhecida caem em 'store' — o lado seguro do D3. Nunca em
// 'update'/'merge' por adivinhação.
function interpretarDecisaoReconciliacao(respostaBruta) {
  const seguro = { acao: 'store', alvo_id: null };
  if (!respostaBruta || typeof respostaBruta !== 'string') return seguro;

  let bruto = respostaBruta.trim();
  let obj = null;
  try {
    obj = JSON.parse(bruto);
  } catch (e) {
    // Tolerar CLI real que envolve o JSON em texto/markdown: extrair o
    // primeiro bloco {...} e tentar de novo antes de desistir.
    const match = bruto.match(/\{[\s\S]*\}/);
    if (match) {
      try {
        obj = JSON.parse(match[0]);
      } catch (e2) {
        return seguro;
      }
    } else {
      return seguro;
    }
  }

  if (!obj || typeof obj !== 'object' || !ACOES_RECONCILIACAO_VALIDAS.has(obj.acao)) {
    return seguro;
  }

  let alvoId = null;
  if (obj.alvo_id !== null && obj.alvo_id !== undefined) {
    const n = Number(obj.alvo_id);
    if (Number.isFinite(n)) alvoId = n;
  }

  return { acao: obj.acao, alvo_id: alvoId };
}

// Chamada à LLM isolada atrás de função para permitir mock em testes — mesmo
// padrão que chamarLLMParaConsolidar (D14). Respeita TESTADOR_CHAMAR_LLM
// (módulo que exporta chamarLLM(texto)); a bateria roda inteira sob esse mock,
// então o caminho de spawn do `claude` real nunca é alcançado nela.
// Retorna a resposta bruta (string) ou null se falhar — null vira 'store' em
// interpretarDecisaoReconciliacao.
async function chamarLLMParaReconciliar(observacao, candidatas) {
  const prompt = formatarPromptReconciliacao(observacao, candidatas);

  if (process.env.TESTADOR_CHAMAR_LLM) {
    try {
      const modulo = require(process.env.TESTADOR_CHAMAR_LLM);
      return await modulo.chamarLLM(prompt);
    } catch (e) {
      console.error(`AVISO: não consegui carregar mock de LLM: ${e.message}`);
      return null;
    }
  }

  const { spawn } = require('child_process');
  const os = require('os');

  const executavel = acharExecutavelClaude();
  if (!executavel) {
    console.error('AVISO: não encontrei o executável `claude` no PATH');
    return null;
  }

  const tempDir = os.tmpdir();
  const TETO_ARGUMENTO = 16000;

  if (prompt.length > TETO_ARGUMENTO) {
    console.error(`AVISO: prompt de reconciliação acima do teto (${prompt.length} > ${TETO_ARGUMENTO})`);
    return null;
  }

  return new Promise((resolve) => {
    const timeout = 60000;
    const timer = setTimeout(() => {
      console.error('AVISO: chamada à LLM expirou (timeout 60s)');
      resolve(null);
    }, timeout);

    try {
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

      child.stdout.on('data', (data) => {
        stdout += data.toString();
      });

      child.stderr.on('data', () => {});

      child.stdin.end();

      child.on('error', (error) => {
        clearTimeout(timer);
        console.error(`AVISO: erro ao chamar claude em "${executavel}": ${error.message}`);
        resolve(null);
      });

      child.on('close', (code) => {
        clearTimeout(timer);

        if (code !== 0) {
          console.error(`AVISO: claude retornou exit code ${code}`);
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
      console.error(`AVISO: erro ao invocar claude em "${executavel}": ${e.message}`);
      resolve(null);
    }
  });
}

// Aplica a decisão de reconciliação a UMA observação sondada, atomicamente
// (mesmo padrão que consolidarAtomico): falha no meio faz ROLLBACK e a
// observação continua pendente (reconciliada_em fica NULL) para a próxima
// rodada de `reconciliar`.
//
// update: a candidata-alvo (mais antiga, o `alvo_id`) recebe substituida_por
// igual ao id da observação sondada — ela é quem corrige o alvo. Nada é
// apagado: as duas continuam na tabela.
//
// merge: insere uma TERCEIRA observação com a síntese das duas, origem
// determinística `reconciliacao:<id_menor>+<id_maior>` (UNIQUE(projeto,
// origem) impede duplicar ao reprocessar o mesmo par — se o INSERT colidir,
// reaproveita a linha já existente em vez de falhar), e marca as DUAS antigas
// (a sondada e o alvo) com substituida_por apontando para a nova.
//
// store/skip: nada é substituído; só marca reconciliada_em na sondada.
//
// alvo_id ausente, inexistente, de outro projeto, já substituída, igual à
// própria observação, ou FORA DO CONJUNTO de candidatas que `buscarCandidatas`
// de fato ofereceu a esta sondagem: cai no lado seguro (equivalente a store)
// em vez de confiar cego numa resposta de LLM que aponta para algo que nunca
// foi mostrado a ela. `buscarCandidatas` protegia o que é OFERECIDO (mesmo
// projeto, viva); nada protegia o que a LLM DEVOLVE — achado 2 da revisão
// (2026-09-16): um `alvo_id` de resposta de LLM podia apontar para uma
// candidata morta (`substituida_por` já preenchido) ou para qualquer id de
// outra sondagem, sobrescrevendo um `substituida_por` correto e ressuscitando
// conteúdo morto numa observação nova.
//
// Para 'update' há ainda a guarda de direção temporal — achado 1 da mesma
// revisão: a varredura do acervo (D6) sonda observações antigas (88% do
// corpus são as importadas do claude-mem), e uma LLM sem soubesse a data
// podia decidir "update" apontando da sondada ANTIGA para uma candidata mais
// NOVA e correta, invertendo a direção — a correta acabava marcada
// `substituida_por` e a desatualizada continuava viva. `update` só é
// aplicado quando a sondada não é mais antiga que o alvo
// (`obs.criada_em >= alvo.criada_em`); do contrário cai no lado seguro. Isto
// é backstop determinístico — o prompt (formatarPromptReconciliacao) já
// carrega as datas para a LLM decidir certo na maioria dos casos, mas uma
// resposta errada não pode inverter o invariante do D3.
function aplicarDecisaoReconciliacao(conexao, obs, decisao, candidatas = []) {
  const agora = new Date().toISOString();
  const idsOferecidos = new Set(candidatas.map((c) => c.id));

  try {
    conexao.exec('BEGIN TRANSACTION');

    if (decisao.acao === 'merge' || decisao.acao === 'update') {
      const alvo = decisao.alvo_id !== null
        ? conexao.prepare('SELECT id, conteudo, criada_em FROM observacoes WHERE id = ? AND projeto = ? AND substituida_por IS NULL')
            .get(decisao.alvo_id, obs.projeto)
        : null;

      const alvoInvalido = !alvo
        || alvo.id === obs.id
        || !idsOferecidos.has(alvo.id)
        || (decisao.acao === 'update' && obs.criada_em < alvo.criada_em);

      if (alvoInvalido) {
        // alvo_id inválido (ou update na direção errada) — lado seguro:
        // nada é substituído.
        conexao.prepare('UPDATE observacoes SET reconciliada_em = ? WHERE id = ?').run(agora, obs.id);
        conexao.exec('COMMIT');
        return true;
      }

      if (decisao.acao === 'update') {
        conexao.prepare('UPDATE observacoes SET substituida_por = ?, reconciliada_em = ? WHERE id = ?')
          .run(obs.id, agora, alvo.id);
        conexao.prepare('UPDATE observacoes SET reconciliada_em = ? WHERE id = ?')
          .run(agora, obs.id);
      } else {
        // merge: insere a terceira observação com origem determinística.
        const idMenor = Math.min(obs.id, alvo.id);
        const idMaior = Math.max(obs.id, alvo.id);
        const origemMerge = `reconciliacao:${idMenor}+${idMaior}`;
        const conteudoNovo = `${obs.conteudo}\n${alvo.conteudo}`;

        let novoId;
        try {
          const resultado = conexao.prepare(`
            INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
            VALUES (?, ?, ?, ?)
          `).run(obs.projeto, conteudoNovo, agora, origemMerge);
          novoId = Number(resultado.lastInsertRowid);
        } catch (e) {
          if (!String(e.message).includes('UNIQUE constraint')) throw e;
          // Reprocessando o mesmo par: a fusão já existe, reaproveitar.
          const existente = conexao.prepare('SELECT id FROM observacoes WHERE projeto = ? AND origem = ?')
            .get(obs.projeto, origemMerge);
          novoId = existente.id;
        }

        conexao.prepare('UPDATE observacoes SET substituida_por = ?, reconciliada_em = ? WHERE id = ?')
          .run(novoId, agora, obs.id);
        conexao.prepare('UPDATE observacoes SET substituida_por = ?, reconciliada_em = ? WHERE id = ?')
          .run(novoId, agora, alvo.id);
        // A própria síntese nasce reconciliada: ela é o RESULTADO da
        // reconciliação da sondada com o alvo, não mais uma pendência. Sem
        // isto, ela reentraria em `pendentes` na próxima execução e seria
        // processada contra as mesmas duas observações que a originaram.
        conexao.prepare('UPDATE observacoes SET reconciliada_em = ? WHERE id = ?')
          .run(agora, novoId);
      }
    } else {
      // store ou skip: nada é substituído.
      conexao.prepare('UPDATE observacoes SET reconciliada_em = ? WHERE id = ?').run(agora, obs.id);
    }

    conexao.exec('COMMIT');
    return true;
  } catch (e) {
    try {
      conexao.exec('ROLLBACK');
    } catch (_) {}
    console.error(`AVISO: falha ao aplicar reconciliação da observação ${obs.id}: ${e.message}`);
    return false;
  }
}

// Comando: reconciliar — store/update/merge/skip contra o acervo pendente.
// Tarefa 2 (D2, D3, D4, D6). Seleciona até TETO_RECONCILIAR observações
// pendentes (reconciliada_em IS NULL AND substituida_por IS NULL), mais
// recentes primeiro; para cada uma, busca até K_CANDIDATAS parecidas no FTS5
// do mesmo projeto e pede à LLM a decisão. Degradação: banco ausente/
// corrompido ou LLM indisponível vira aviso no stderr e exit 0 — nenhum
// caminho novo derruba a sessão (D1: fora do hook de captura).
async function cmdReconciliar() {
  const { caminhoDb } = resolverCaminhos();

  if (!fs.existsSync(caminhoDb)) {
    console.error(`AVISO: banco não existe em ${caminhoDb}`);
    console.error('rode: node scripts/memoria.cjs iniciar');
    return;
  }

  let conexao;
  try {
    conexao = abrirBanco(caminhoDb);
  } catch (e) {
    console.error(`AVISO: não consegui abrir o banco: ${e.message}`);
    return;
  }

  try {
    const pendentes = conexao.prepare(`
      SELECT id, projeto, conteudo, criada_em
      FROM observacoes
      WHERE reconciliada_em IS NULL AND substituida_por IS NULL
      ORDER BY criada_em DESC
      LIMIT ?
    `).all(TETO_RECONCILIAR);

    if (pendentes.length === 0) {
      console.log('nenhuma observação pendente de reconciliação');
      conexao.close();
      return;
    }

    console.log(`${pendentes.length} observação(ões) pendente(s) de reconciliação`);

    let processadas = 0;
    let pulos = 0;
    let jaTratadas = 0;

    for (const obs of pendentes) {
      // `pendentes` foi lida de uma vez, antes do laço começar. Uma decisão
      // anterior DESTE MESMO laço pode já ter marcado `obs` (ela era o alvo
      // de um update/merge de outra observação processada primeiro) — sem
      // reler o estado atual, ela seria sondada de novo contra candidatas que
      // agora incluem sua própria substituta, e uma LLM real poderia decidir
      // reconciliar uma observação já substituída contra o que a substituiu.
      const atual = conexao.prepare('SELECT substituida_por, reconciliada_em FROM observacoes WHERE id = ?').get(obs.id);
      if (!atual || atual.substituida_por !== null || atual.reconciliada_em !== null) {
        jaTratadas++;
        continue;
      }

      const candidatas = buscarCandidatas(conexao, obs);

      let decisao;
      if (candidatas.length === 0) {
        // Nada parecido no acervo: não há o que reconciliar, poupa a chamada.
        decisao = { acao: 'store', alvo_id: null };
      } else {
        const respostaBruta = await chamarLLMParaReconciliar(obs, candidatas);
        decisao = interpretarDecisaoReconciliacao(respostaBruta);
      }

      const sucesso = aplicarDecisaoReconciliacao(conexao, obs, decisao, candidatas);
      if (sucesso) {
        processadas++;
      } else {
        pulos++;
      }
    }

    console.log(`reconciliação completa: ${processadas} processada(s), ${pulos} pulo(s) (falha, pendente para a próxima rodada), ${jaTratadas} já tratada(s) por outra decisão neste laço`);
    conexao.close();
  } catch (e) {
    console.error(`AVISO: erro durante reconciliação: ${e.message}`);
    try { conexao.close(); } catch (_) {}
  }
}

// Comando `utilidade` (Tarefas 1 e 4, D1-D11): inspeção do extrator
// (`--extrair <transcrito>`) e relatório da régua D9 (`--relatorio`). Nunca
// escreve no banco — quem grava é `pontuarSessoesPendentes`, chamada só de
// dentro de `cmdManutencao`.
function cmdUtilidade() {
  const args = process.argv.slice(3);

  const iExtrair = args.indexOf('--extrair');
  if (iExtrair !== -1) {
    const caminhoTranscrito = args[iExtrair + 1];
    if (!caminhoTranscrito) {
      console.error('ERRO: --extrair requer o caminho do transcrito');
      process.exit(1);
    }
    const { servidas, texto } = extrairSessao(caminhoTranscrito);
    console.log(JSON.stringify({ servidas: servidas.length, bytesTexto: Buffer.byteLength(texto, 'utf8') }));
    return;
  }

  if (args.includes('--relatorio')) {
    const { caminhoDb } = resolverCaminhos();
    if (!fs.existsSync(caminhoDb)) {
      console.log('(banco não existe, nada a relatar)');
      return;
    }
    // Somente-leitura de propósito (D2: o relatório só lê) — sem fallback
    // para abrirBanco() em caso de falha, que abriria para ESCRITA.
    const conexao = abrirBancoSomenteLeitura(caminhoDb);
    if (!conexao) {
      console.log('(banco indisponível, nada a relatar)');
      return;
    }
    try {
      console.log(gerarRelatorio(conexao));
    } finally {
      conexao.close();
    }
    return;
  }

  console.error('Use: utilidade --extrair <transcrito> | utilidade --relatorio');
  process.exit(1);
}

// Comando `manutencao` (Tarefa 5, D1/D5): a passada que roda de verdade
// garante o esquema, reconcilia e DEPOIS consolida, nessa ordem, registrando
// cada passo em `<raiz>/manutencao.log`. Quem dispara isto é o hook fino
// `hooks/memoria-manutencao-session-start.cjs`, num filho destacado — nunca
// o hook em si (D1: o hook de captura já pagou o preço de uma chamada de
// LLM no caminho síncrono, #282).
//
// Formato do log (uma linha por evento, `<ISO timestamp> <evento>`):
//   - `esquema: inicio` / `reconciliar: inicio` / `consolidar: inicio` — o
//     passo começou.
//   - `esquema: fim` / `reconciliar: fim` / `consolidar: fim` — o passo
//     terminou SEM lançar. Não significa "sem nada a fazer": consolidar/
//     reconciliar podem legitimamente não achar trabalho e ainda gravar `fim`.
//   - `esquema: falhou: <motivo>` / `reconciliar: falhou: <motivo>` /
//     `consolidar: falhou: <motivo>` — o passo lançou; `<motivo>` é
//     `e.message`. O passo seguinte roda do mesmo jeito (cada um é tentado
//     independente dos outros; ver o `try/catch` de cada bloco abaixo).
//   - Linha final da passada: `manutencao: completa` (todo passo terminou em
//     `fim`) ou `manutencao: completa com falhas` (algum passo gravou
//     `falhou:`). Esta é a única linha que fecha uma passada.
// Achar a última passada: leia o arquivo de trás para frente até a última
// linha que começa com `manutencao: completa` — o timestamp dela é quando a
// última passada terminou, e o texto diz se terminou limpa ou com falha (é
// isto que a Tarefa 6 lê para avisar na abertura da sessão). Um arquivo cujo
// fim não é uma dessas duas linhas indica passada ainda em andamento (ou um
// processo morto por fora, ex.: kill -9) — não deveria mais acontecer por
// falha interna, já que nenhum passo aqui chama `process.exit`/lança sem ser
// capturado.
//
// Nenhum passo mata o processo: `cmdReconciliar()` já degrada por dentro
// (nunca lança), e `garantirEsquema()`/`cmdConsolidar()` foram ajustados
// (Tarefa 5, emenda 2026-09-18) para LANÇAR em vez de `process.exit` no
// caminho de erro — o `try/catch` de cada passo abaixo é o que captura isso.
// Quem chama `consolidar`/`reconciliar` direto da CLI continua saindo 1 em
// erro, via o `catch` de `main()`.
async function cmdManutencao() {
  const { raiz, caminhoDb } = resolverCaminhos();
  fs.mkdirSync(raiz, { recursive: true });
  const caminhoLog = path.join(raiz, 'manutencao.log');

  function registrar(linha) {
    try {
      fs.appendFileSync(caminhoLog, `${new Date().toISOString()} ${linha}\n`);
    } catch (e) {
      console.error(`AVISO: não consegui gravar em ${caminhoLog}: ${e.message}`);
    }
  }

  // Banco ausente = nada a reconciliar e nada a consolidar. A manutenção
  // MIGRA um banco que já existe (é para isso que garantirEsquema() ganhou o
  // recuperarSeNecessario()/criarSchema() aqui), mas nunca CRIA um banco que
  // não existe: `abrirBanco()` usa `new DatabaseSync(caminhoDb)`, que cria o
  // arquivo ao abrir. Se este passo chamasse garantirEsquema() incondicional,
  // a passada de manutenção (disparada pelo hook de SessionStart) estaria
  // escrevendo o rainforest.db durante a abertura da sessão — o invariante
  // que scripts/testa-memoria-somente-leitura.sh existe para proteger.
  if (!fs.existsSync(caminhoDb)) {
    registrar('manutencao: banco ausente, nada a fazer');
    registrar('manutencao: completa');
    console.log(`manutencao: banco ausente em ${caminhoDb}, nada a fazer`);
    return;
  }

  let houveFalha = false;

  registrar('esquema: inicio');
  try {
    garantirEsquema();
    registrar('esquema: fim');
  } catch (e) {
    houveFalha = true;
    registrar(`esquema: falhou: ${e.message}`);
  }

  registrar('reconciliar: inicio');
  try {
    await cmdReconciliar();
    registrar('reconciliar: fim');
  } catch (e) {
    houveFalha = true;
    registrar(`reconciliar: falhou: ${e.message}`);
  }

  registrar('consolidar: inicio');
  try {
    await cmdConsolidar();
    registrar('consolidar: fim');
  } catch (e) {
    houveFalha = true;
    registrar(`consolidar: falhou: ${e.message}`);
  }

  // Tarefa 3 (D7): pontua as sessões pendentes da marca_dagua, depois de
  // reconciliar e consolidar. Conexão própria, fechada neste bloco — os
  // passos acima abrem e fecham a própria conexão dentro de cada cmd*().
  // Conta via uso_memoria_sessoes (antes/depois): cobre tanto a sessão
  // pontuada de verdade quanto a marcada sem transcrito (as duas terminam
  // ali) — ao contrário de contar por uso_memoria, que ficaria mudo para
  // uma sessão com transcrito mas sem servida/contrafactual nenhum.
  registrar('utilidade: inicio');
  try {
    const { caminhoDb: caminhoDbUtilidade } = resolverCaminhos();
    const conexao = abrirBanco(caminhoDbUtilidade);
    try {
      const antes = conexao.prepare('SELECT COUNT(*) c FROM uso_memoria_sessoes').get().c;
      const resultadoUtilidade = pontuarSessoesPendentes(conexao);
      const depois = conexao.prepare('SELECT COUNT(*) c FROM uso_memoria_sessoes').get().c;
      // Tarefa 7 (D7, D8): N continua vindo do antes/depois (cobre tanto a
      // sessão pontuada de verdade quanto a marcada sem transcrito — mesma
      // razão do comentário acima); M e R vêm do retorno de
      // pontuarSessoesPendentes, que é quem aplicou o teto TETO_PONTUAR.
      registrar(
        `utilidade: ${depois - antes} sessao(oes) pontuada(s), ${resultadoUtilidade.servidasSemId} servida(s) sem id, ${resultadoUtilidade.pendentesParaProxima} pendente(s) para a proxima`
      );
    } finally {
      conexao.close();
    }
    registrar('utilidade: fim');
  } catch (e) {
    houveFalha = true;
    registrar(`utilidade: falhou: ${e.message}`);
  }

  registrar(houveFalha ? 'manutencao: completa com falhas' : 'manutencao: completa');
  console.log(`manutencao completa: log em ${caminhoLog}`);
}

// ---- CLI

async function main() {
  const cmd = process.argv[2];

  switch (cmd) {
    case 'iniciar':
      return cmdIniciar();
    case 'esquema':
      return cmdEsquema();
    case 'buscar':
      return cmdBuscar();
    case 'backup':
      return cmdBackup();
    case 'reindexar':
      return cmdReindexar();
    case 'consolidar':
      return await cmdConsolidar();
    case 'reconciliar':
      return await cmdReconciliar();
    case 'manutencao':
      return await cmdManutencao();
    case 'utilidade':
      return cmdUtilidade();
    default:
      console.error(`Comando desconhecido: ${cmd}`);
      console.error('Use: iniciar | esquema | buscar | backup | reindexar | consolidar | reconciliar | manutencao | utilidade');
      process.exit(1);
  }
}

if (require.main === module) {
  try {
    main().catch(e => {
      console.error(`ERRO: ${e.message}`);
      process.exit(1);
    });
  } catch (e) {
    console.error(`ERRO: ${e.message}`);
    process.exit(1);
  }
}

module.exports = {
  abrirBanco, abrirBancoSomenteLeitura, chaveHarness, criarSchema, extrairSchema, popularFts5,
  resolverCaminhos, verificarConstraintUniqueProjetoOrigem,
  K_CANDIDATAS, TETO_RECONCILIAR, construirQueryFts5, buscarCandidatas,
  interpretarDecisaoReconciliacao, aplicarDecisaoReconciliacao,
  formatarPromptReconciliacao,
  filtroVivas, DIAS_CONSOLIDACAO, TETO_GRUPOS,
};
