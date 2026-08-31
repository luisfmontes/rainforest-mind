// Funções compartilhadas de ponte: corpo() e raizDeDados()
//
// Extraído de scripts/ponte.cjs e scripts/conferir-ponte.cjs para evitar
// duplicação de código. Ambos os scripts geram o mesmo bloco de regras,
// e a lógica de resolução de raiz é compartilhada.
//
// Incidente 2026-08-10: duas CLAUDE.md sincronizadas à mano divergiram
// em silêncio porque cada uma tinha uma cópia da mesma regra. A dupli-
// cação de código é um incidente de confiabilidade quando o código é
// derivado de uma fonte única. Este módulo elimina a raiz do problema.

"use strict";

const path = require("path");
const fs = require("fs");

/**
 * Calcula hash curto (16 caracteres) do conteúdo de um arquivo.
 */
function hashDoArquivo(caminho) {
  try {
    const conteudo = fs.readFileSync(caminho, "utf8");
    const crypto = require("crypto");
    return crypto
      .createHash("sha256")
      .update(conteudo)
      .digest("hex")
      .slice(0, 16);
  } catch {
    return null;
  }
}

/**
 * Lê o conteúdo do bloco rainforest-mind:projeto:inicio/fim de projeto.md do alvo,
 * se o arquivo existir. Retorna null se o arquivo não existe ou se o bloco não foi encontrado.
 * Se incluirHash for true, adiciona o hash do arquivo projeto.md ao marcador de início.
 *
 * @param {string} alvo - raiz do repositório alvo
 * @param {boolean} incluirHash - se true, adiciona hash ao marcador de início
 * @returns {string|null} conteúdo completo do bloco entre os marcadores, ou null
 */
function lerProjetoMd(alvo, incluirHash = false) {
  if (!alvo) return null;
  const caminhoProjetoMd = path.join(alvo, "docs", "rainforest", "projeto.md");
  try {
    const conteudo = fs.readFileSync(caminhoProjetoMd, "utf8");
    // Procura pelos marcadores do bloco de projeto
    const marcadorInicio = "<!-- rainforest-mind:projeto:inicio -->";
    const marcadorFim = "<!-- rainforest-mind:projeto:fim -->";
    const idxInicio = conteudo.indexOf(marcadorInicio);
    const idxFim = conteudo.indexOf(marcadorFim);
    if (idxInicio >= 0 && idxFim >= 0 && idxFim > idxInicio) {
      // Extrai o bloco completo incluindo os marcadores
      let bloco = conteudo.slice(idxInicio, idxFim + marcadorFim.length);

      // Se precisar incluir hash, substitui o marcador de início
      if (incluirHash) {
        const hash = hashDoArquivo(caminhoProjetoMd);
        if (hash) {
          const marcadorComHash = `<!-- rainforest-mind:projeto:inicio — hash:${hash} -->`;
          bloco = bloco.replace(marcadorInicio, marcadorComHash);
        }
      }

      return bloco;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * O núcleo das regras, da mesma fonte e pelo mesmo caminho do hook de abertura.
 */
function nucleoDasRegras(caminhoSkill) {
  const fs = require("fs");
  let lib;
  try {
    const pluginRoot = path.resolve(__dirname, "..", "..");
    lib = require(path.join(pluginRoot, "hooks", "lib", "contexto-sessao.cjs"));
  } catch (e) {
    throw new Error(
      `não consegui carregar hooks/lib/contexto-sessao.cjs: ${e.message}`
    );
  }
  let skill;
  try {
    skill = fs.readFileSync(caminhoSkill, "utf8");
  } catch (e) {
    throw new Error(`não consegui ler ${caminhoSkill}: ${e.message}`);
  }
  const nucleo = lib.extrairNucleo(lib.filtrarRegras(skill)).trim();
  return nucleo;
}

/**
 * Resolve a raiz de dados (FOCO.md, ideias.jsonl) usando a cadeia de resolução.
 *
 * @param {string} pluginRoot - raiz do plugin (passada explicitamente)
 * @returns {string|null} caminho da raiz, ou null se não encontrado
 */
function raizDeDados(pluginRoot) {
  try {
    return (
      require(path.join(pluginRoot, "hooks", "lib", "raiz.cjs")).resolverRaiz({
        plugin: pluginRoot,
      }).raiz || null
    );
  } catch {
    return null;
  }
}

/**
 * Definições dos agentes (AGENTES.claude, AGENTES.codex, AGENTES.gemini).
 */
const AGENTES = {
  claude: {
    arquivo: "CLAUDE.md",
    nome: "Claude Code (sem o plugin)",
    comoLe: "O Claude Code le o `CLAUDE.md` da raiz do repositorio em toda sessao.",
    semTrava:
      "As duas travas do rainforest-mind (agente fora de worktree isolado, `git add -A`) " +
      "sao hooks `PreToolUse` do PLUGIN. Este arquivo entrega as regras, nao os hooks: " +
      "sem o plugin instalado elas sao combinado, nao trava. Quem quiser as travas " +
      "instala o plugin — ai este arquivo fica redundante e pode sair.",
  },
  codex: {
    arquivo: "AGENTS.md",
    nome: "Codex",
    comoLe: "O Codex le o `AGENTS.md` da raiz do repositorio em toda sessao.",
    semTrava:
      "Duas travas do rainforest-mind rodam fora do modelo no Claude Code, como hook " +
      "com exit code: a que barra agente editando fora de worktree isolado, e a que " +
      "barra `git add -A`. Elas usam o `PreToolUse`, que **nao existe** neste host. " +
      "Aqui elas sao texto — ou seja, argumentaveis. Trate-as como combinado.",
  },
  gemini: {
    arquivo: "GEMINI.md",
    nome: "Gemini CLI",
    comoLe: "O Gemini CLI le o `GEMINI.md` da raiz do repositorio em toda sessao.",
    semTrava:
      "Duas travas do rainforest-mind rodam fora do modelo no Claude Code, como hook " +
      "com exit code: a que barra agente editando fora de worktree isolado, e a que " +
      "barra `git add -A`. Elas usam o `PreToolUse`, que **nao existe** neste host. " +
      "Aqui elas sao texto — ou seja, argumentaveis. Trate-as como combinado.",
  },
};

/**
 * Gera o corpo do bloco de regras (idêntico em ponte.cjs e conferir-ponte.cjs).
 *
 * @param {object} agente - definição do agente (nome, arquivo, etc)
 * @param {string} nucleo - núcleo das regras, já extraído
 * @param {string|null} dados - raiz de dados, ou null se não encontrada
 * @param {string|null} alvo - raiz do repositório alvo (para incluir projeto.md se existir)
 * @returns {string} conteúdo do bloco, pronto para escrita
 */
function corpo(agente, nucleo, dados, alvo = null) {
  const cli = [
    [
      "`node <plugin>/scripts/estado.cjs exigir --slug <slug> --estagio <e>`",
      "gate do fluxo — **exit 2** quando o estagio anterior nao fechou",
    ],
    [
      "`node <plugin>/scripts/conferir-entrega.cjs --worktree <wt> --base <hash>`",
      "a checagem da regra 12 sobre entrega de agente — **exit 1** se reprovar",
    ],
    [
      "`node <plugin>/scripts/conferir-publicacao.cjs <arquivo>`",
      "**exit 2** se o texto tem telefone, e-mail, caminho de home ou credencial",
    ],
    [
      "`node <plugin>/scripts/ideias.cjs plantar, colher, listar, conferir`",
      "porta unica de escrita do `ideias.jsonl` (trava, backup, atomico, conferido)",
    ],
    [
      "`node <plugin>/scripts/foco.cjs caminho, rotacionar`",
      "onde mora o foco, e o teto do bloco de avancos",
    ],
    ["`node <plugin>/scripts/saude.cjs`", "o que os checadores oficiais nao sabem"],
    [
      "`node <plugin>/scripts/semear.cjs --projeto <slug>`",
      "o historico deste projeto: observacoes, ideias abertas, relatorios",
    ],
  ]
    .map(([c, p]) => `| ${c} | ${p} |`)
    .join("\n");

  return `# rainforest-mind — ponte para o ${agente.nome}

${agente.comoLe} Este bloco e **gerado**: as regras moram em
\`skills/rainforest-mind/SKILL.md\`, no plugin, e chegam aqui por
\`node <plugin>/scripts/ponte.cjs --alvo . --agente ${Object.keys(AGENTES).find((k) => AGENTES[k] === agente)} --aplicar\`.
Editar este bloco a mao cria uma segunda versao das regras que divergem em
silencio — foi o que aconteceu com duas CLAUDE.md sincronizadas a mao em
2026-08-10. Mude o SKILL.md e gere de novo.

## O que NAO vale aqui, e voce precisa saber antes de confiar

${agente.semTrava}

O que continua sendo mecanismo, porque e comando com exit code, esta na tabela
abaixo. Chame de verdade: **relato de que rodou nao e evidencia de que rodou.**

| Comando | O que ele garante |
|---|---|
${cli}

\`<plugin>\` e a pasta do rainforest-mind nesta maquina. Sua pasta de dados
(FOCO.md, ideias.jsonl, projetos.json) **nao se chumba aqui**: descubra com
\`node <plugin>/scripts/ideias.cjs conferir\`, que imprime o caminho resolvido${dados ? "" : ", e monte com `node <plugin>/scripts/setup.cjs --criar` se ainda nao existir"}.
Caminho de home dentro de arquivo versionado vaza a maquina de quem gerou — e este
arquivo nasce para ser commitado no repo de outra pessoa.

## As regras

O que segue e o **nucleo** de cada regra. Regra marcada com \`↳\` tem elaboracao
que nao esta aqui — criterio fino, comando exato, incidente datado —, e ela mora
em \`skills/rainforest-mind/references/regra-<n>.md\` (onde \`<n>\` e o numero da regra). Antes de aplicar uma regra marcada, **leia esse arquivo**.

${nucleo}`;
}

module.exports = { corpo, raizDeDados, AGENTES, nucleoDasRegras, lerProjetoMd, hashDoArquivo };
