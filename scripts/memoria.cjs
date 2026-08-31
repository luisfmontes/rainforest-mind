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
//     C:\Microsiga\protheus-totvs-agro\inovacao → C--Microsiga-protheus-totvs-agro-inovacao
// Função pura, sem I/O.
function chaveHarness(diretorio) {
  if (!diretorio) return '';
  // Normalizar separadores (\ e /) e : para -
  return diretorio.replace(/[\\/:]/g, '-');
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

// Comando: iniciar — criar/abrir o banco, verificar schema.
function cmdIniciar() {
  const { raiz, caminhoDb, projeto } = resolverCaminhos();

  // Criar diretório se não existe.
  fs.mkdirSync(raiz, { recursive: true });

  const conexao = abrirBanco(caminhoDb);

  // Recuperar de estado quebrado (observacoes_backup órfã) ANTES de criar schema
  recuperarSeNecessario(conexao);

  criarSchema(conexao);

  // Popular índice FTS5 (idempotente).
  popularFts5(conexao);

  console.log(`ok: banco em ${caminhoDb} (projeto: ${projeto})`);

  // Retornar exit 0 implicitamente.
  conexao.close();
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
      query = `
        SELECT o.id, o.projeto, o.conteudo, o.criada_em
        FROM observacoes o
        WHERE o.id IN (
          SELECT rowid FROM observacoes_fts WHERE conteudo MATCH :fts_query
        )
      `;
      params.fts_query = texto; // FTS5 syntax: "palavra" ou "palavra1 AND palavra2"

      if (projeto) {
        query += ' AND o.projeto = :projeto';
        params.projeto = projeto;
      }
    } else {
      // Sem texto: listar recentes de um projeto (se fornecido).
      query = 'SELECT id, projeto, conteudo, criada_em FROM observacoes';

      if (projeto) {
        query += ' WHERE projeto = :projeto';
        params.projeto = projeto;
      }
    }

    query += ' ORDER BY criada_em DESC LIMIT :limite';

    const stmt = conexao.prepare(query);
    resultados = stmt.all(params);
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

// ---- CLI

function main() {
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
    default:
      console.error(`Comando desconhecido: ${cmd}`);
      console.error('Use: iniciar | esquema | buscar | backup | reindexar');
      process.exit(1);
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

module.exports = { abrirBanco, abrirBancoSomenteLeitura, chaveHarness, criarSchema, extrairSchema, popularFts5, resolverCaminhos, verificarConstraintUniqueProjetoOrigem };
