-- Esquema do banco de dados do rainforest-mind.
--
-- Por que existe: o rainforest tem seu próprio store de memória, independente
-- do claude-mem (decisão D2). O corpus passa de importação frágil a banco
-- consultável, resolvendo tanto a queda de injeção por timout de worker quanto
-- o spawn de 46 mil processos em oito dias (motivação, design D14).
--
-- Organização:
--   observacoes   — observações capturadas do transcrito, verdade de máquina
--   resumos       — sínteses e índices sobre conjuntos de observações
--   prompts       — registro dos prompts usados na passada de LLM
--   marca_dagua   — ponto de recuperação: sessão, arquivo, offset processado
--
-- Tabelas DERIVADAS (apagar nunca perde dados — tudo é rederivável do texto):
--   indice_foco   — campos estruturados de FOCO.md (datas, headers, pastas)
--   indice_ideias — metadados de ideias.jsonl (id, titulo, status, tipo, etc)
-- cmdReindexar é o único que popula essas tabelas. Fase 2 não as toca.
--
-- Coluna `projeto` em observacoes (decisão D9): a raiz resolve por cadeia
-- de quatro níveis (RFM_ROOT > projeto/.rainforest > ~/.rainforest > plugin),
-- e isolamento por projeto é propósito — quem aponta raiz por projeto quer
-- dados separados. Gravar o projeto dentro garante que uma consulta global
-- sabe de quem vem cada linha.

CREATE TABLE IF NOT EXISTS observacoes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projeto TEXT NOT NULL,
  conteudo TEXT NOT NULL,
  criada_em TEXT NOT NULL,
  origem TEXT,
  consolidada_em TEXT,
  UNIQUE(projeto, origem)
);

CREATE TABLE IF NOT EXISTS resumos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projeto TEXT NOT NULL,
  titulo TEXT NOT NULL,
  conteudo TEXT NOT NULL,
  criada_em TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS prompts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projeto TEXT NOT NULL,
  prompt TEXT NOT NULL,
  modelo TEXT,
  criada_em TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS marca_dagua (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projeto TEXT NOT NULL,
  sessao TEXT NOT NULL,
  arquivo TEXT NOT NULL,
  offset INTEGER NOT NULL DEFAULT 0,
  offset_processado INTEGER NOT NULL DEFAULT 0,
  processada_em TEXT NOT NULL,
  UNIQUE(projeto, sessao)
);

CREATE TABLE IF NOT EXISTS indice_foco (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projeto TEXT NOT NULL,
  tipo TEXT NOT NULL,
  valor TEXT NOT NULL,
  indexada_em TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS indice_ideias (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projeto TEXT NOT NULL,
  ideia_id TEXT,
  titulo TEXT NOT NULL,
  status TEXT,
  tipo TEXT,
  plantada_em TEXT,
  gancho TEXT,
  conteudo_busca TEXT,
  indexada_em TEXT NOT NULL
);

-- Índices para acesso rápido
CREATE INDEX IF NOT EXISTS idx_observacoes_projeto ON observacoes(projeto);
CREATE INDEX IF NOT EXISTS idx_resumos_projeto ON resumos(projeto);
CREATE INDEX IF NOT EXISTS idx_prompts_projeto ON prompts(projeto);
CREATE INDEX IF NOT EXISTS idx_marca_dagua_projeto ON marca_dagua(projeto);
CREATE INDEX IF NOT EXISTS idx_indice_foco_projeto ON indice_foco(projeto);
CREATE INDEX IF NOT EXISTS idx_indice_ideias_projeto ON indice_ideias(projeto);
CREATE INDEX IF NOT EXISTS idx_indice_ideias_id ON indice_ideias(ideia_id);

-- Full-Text Search para busca rapida em observacoes
-- Tarefa 1 (D24): FTS5 com conteudo externo sincronizado por triggers.
-- A tabela observacoes e a fonte de verdade; observacoes_fts apenas indexa.
-- Triggers mantêm sincronização automática em INSERT/UPDATE/DELETE.
CREATE VIRTUAL TABLE IF NOT EXISTS observacoes_fts USING fts5(
  conteudo,
  content='observacoes',
  content_rowid='id'
);

-- Trigger: sincronizar INSERT em observacoes_fts após INSERT em observacoes
CREATE TRIGGER IF NOT EXISTS observacoes_ai AFTER INSERT ON observacoes BEGIN
  INSERT INTO observacoes_fts(rowid, conteudo)
  VALUES (new.id, new.conteudo);
END;

-- Trigger: sincronizar UPDATE em observacoes_fts após UPDATE em observacoes
CREATE TRIGGER IF NOT EXISTS observacoes_au AFTER UPDATE ON observacoes BEGIN
  INSERT INTO observacoes_fts(observacoes_fts, rowid, conteudo)
  VALUES('delete', old.id, old.conteudo);
  INSERT INTO observacoes_fts(rowid, conteudo)
  VALUES (new.id, new.conteudo);
END;

-- Trigger: sincronizar DELETE em observacoes_fts após DELETE em observacoes
CREATE TRIGGER IF NOT EXISTS observacoes_ad AFTER DELETE ON observacoes BEGIN
  INSERT INTO observacoes_fts(observacoes_fts, rowid, conteudo)
  VALUES('delete', old.id, old.conteudo);
END;
