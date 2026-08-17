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
  UNIQUE(projeto, conteudo)
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
  processada_em TEXT NOT NULL,
  UNIQUE(projeto, sessao)
);

-- Índices para acesso rápido
CREATE INDEX IF NOT EXISTS idx_observacoes_projeto ON observacoes(projeto);
CREATE INDEX IF NOT EXISTS idx_resumos_projeto ON resumos(projeto);
CREATE INDEX IF NOT EXISTS idx_prompts_projeto ON prompts(projeto);
CREATE INDEX IF NOT EXISTS idx_marca_dagua_projeto ON marca_dagua(projeto);

-- Full-Text Search para busca rapida em observacoes
CREATE VIRTUAL TABLE IF NOT EXISTS observacoes_fts USING fts5(conteudo);
