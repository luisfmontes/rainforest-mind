#!/usr/bin/env node
"use strict";
/**
 * Catraca do vocabulário de veredito do `vigias/livro-de-repos.md`: lê a tabela
 * "Avaliados" e RECUSA linha cuja data seja posterior ao corte e cujo veredito
 * não esteja no vocabulário fechado da trilha declarada naquela linha.
 *
 * POR QUE EXISTE, com data e incidente (D7 do design de 2026-08-25,
 * `docs/rainforest/design/2026-08-25-regua-do-batedor-enxertar.md`):
 *
 *   "O vocabulário de hoje já está escrito no livro e mesmo assim seis rodadas
 *    o furaram." — a prosa teve 40 oportunidades de segurar o vocabulário
 *    fechado (`instala|nao instala`, `enxerta|nao enxerta`, `vale voltar|nao
 *    vale voltar`, `fora da ancora`) e falhou em 6: `olhar de perto`,
 *    `testar, custo zero (npx)`, `ler, não copiar`, `referência de estrutura`,
 *    `índice de descoberta` e `candidato, não avaliado`. Regra em prosa que o
 *    próprio autor da linha interpreta não trava nada — é a mesma frase que
 *    originou o `conferir-entrega.cjs`: "enquanto o veredito de uma checagem
 *    for redigido pelo mesmo agente que ela deveria travar, ela não trava
 *    nada".
 *
 * D8 — A DATA DE CORTE É O PONTO TODO. As seis linhas de veredito inventado
 * acima foram julgadas sob a régua ANTIGA. Recusá-las agora seria REJULGÁ-LAS
 * sob a régua nova, o erro que a seção "Por que a pergunta 4 aceita código" do
 * próprio livro já documenta: mudar critério de veredito com a peça em cima da
 * régua é reescrever a medida para caber no que se mediu. Por isso o corte
 * (padrão `2026-08-25`, o dia em que este checador nasceu) só valida linha com
 * data POSTERIOR a ele — estritamente maior, nunca igual: as linhas já
 * existentes datadas no próprio dia do corte (o dia em que a mudança foi
 * integrada) continuam sendo produto da régua antiga e passam sem serem
 * olhadas.
 *
 * FORMATO DA CÉLULA DE VEREDITO exigido para linha POSTERIOR ao corte —
 * registra o CAMINHO da cascata (D10), não só a trilha final:
 *
 *   "<Trilha> [→ <Trilha> [→ <Trilha>]]: <veredito>"     ex.: "Instalar → Enxertar: enxerta"
 *   "fora da ancora"                                       (terminal — reprovou na pergunta 1, sem cascata)
 *
 * <Trilha> é um de `Instalar`, `Enxertar`, `Ler` (acentos e caixa ignorados na
 * comparação), a sequência tem de ser um trecho contíguo e crescente da ordem
 * fixa Instalar → Enxertar → Ler (pode começar em qualquer degrau — a âncora
 * já declarou a trilha antes da busca, D1 — mas nunca pula, repete ou inverte
 * degrau), e o <veredito> final tem de bater com o vocabulário fechado do
 * ÚLTIMO degrau do caminho:
 *
 *   Instalar   ->  instala      |  nao instala
 *   Enxertar   ->  enxerta      |  nao enxerta
 *   Ler        ->  vale voltar  |  nao vale voltar
 *   terminal   ->  fora da ancora        (reprovou na pergunta 1, sem cascata)
 *
 * Uso:
 *   node scripts/conferir-livro-de-repos.cjs [--arquivo <caminho>] [--corte <AAAA-MM-DD>]
 *
 *   --arquivo  <caminho>   livro a conferir (padrão: vigias/livro-de-repos.md deste repo)
 *   --corte    <AAAA-MM-DD> data de corte (padrão: 2026-08-25, D8) — só existe como
 *                          flag para o próprio teste de mutação da tarefa 5 conseguir
 *                          provar que a anistia é load-bearing sem editar o fonte à mão
 *
 * Exit:
 *   0  todas as linhas com data posterior ao corte (se houver) batem o vocabulário
 *   1  erro de uso — arquivo/tabela "Avaliados" não encontrado, ou linha da tabela
 *      estruturalmente quebrada (não tem as 5 colunas)
 *   2  VEREDITO FORA DO VOCABULÁRIO — pelo menos uma linha pós-corte declara caminho
 *      válido mas termina num veredito que não é um dos dois da trilha final
 *   3  TRILHA AUSENTE — pelo menos uma linha pós-corte não declara nenhuma trilha
 *      reconhecível na célula de veredito (nem "fora da ancora", nem "Trilha: ...")
 *   4  CAMINHO DE CASCATA MALFORMADO — pelo menos uma linha pós-corte declara um
 *      caminho com degrau desconhecido, fora de ordem, repetido ou com salto
 *
 * Quando mais de um tipo de recusa aparece na mesma rodada, o exit code sai pela
 * ordem de severidade 4 > 3 > 2 (o texto impresso lista TODAS as recusas, de todos
 * os tipos, com o repo e a linha — o exit code é só o resumo para quem só olha o
 * número). A família não faz o chamador ler mensagem para saber o que houve: cada
 * checagem imprime o comando e a evidência antes do veredito, no mesmo desenho do
 * `conferir-entrega.cjs` e do `conferir-mutacao.cjs`.
 */

const fs = require("fs");
const path = require("path");

const CORTE_PADRAO = "2026-08-25";
const ARQUIVO_PADRAO = path.join(__dirname, "..", "vigias", "livro-de-repos.md");

const USO = `uso: node scripts/conferir-livro-de-repos.cjs [--arquivo <caminho>] [--corte <AAAA-MM-DD>]

  --arquivo  <caminho>    livro a conferir (padrão: ${path.relative(process.cwd(), ARQUIVO_PADRAO)})
  --corte    <AAAA-MM-DD> data de corte, exclusiva (padrão: ${CORTE_PADRAO})

exit: 0 tudo bate | 1 erro de uso | 2 veredito fora do vocabulário |
      3 trilha ausente | 4 caminho de cascata malformado`;

function erroUso(msg) {
  console.error(`erro: ${msg}`);
  console.error("");
  console.error(USO);
  process.exit(1);
}

function ler(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1) return null;
  if (i + 1 >= process.argv.length) erroUso(`--${nome} veio sem valor`);
  return process.argv[i + 1];
}

// ============================================================ Vocabulário

const ORDEM = ["instalar", "enxertar", "ler"];
const VOCAB = {
  instalar: ["instala", "nao instala"],
  enxertar: ["enxerta", "nao enxerta"],
  ler: ["vale voltar", "nao vale voltar"],
};
const TERMINAL = "fora da ancora";

function normalizar(s) {
  return String(s == null ? "" : s)
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove diacritico, deixa a letra base
    .toLowerCase()
    .trim()
    .replace(/\s+/g, " ");
}

/** Classifica o texto ANTES do primeiro ':' da célula de veredito. */
function classificarCaminho(caminhoTexto) {
  const pedacos = caminhoTexto
    .split(/→|->/)
    .map((s) => normalizar(s))
    .filter((s) => s.length > 0);

  if (pedacos.length === 0) return { tipo: "ausente" };

  const reconhecidos = pedacos.filter((p) => ORDEM.includes(p));
  if (reconhecidos.length === 0) return { tipo: "ausente" };

  const indices = pedacos.map((p) => ORDEM.indexOf(p));
  if (indices.some((i) => i === -1)) {
    return {
      tipo: "malformado",
      motivo: `degrau desconhecido no caminho (${JSON.stringify(pedacos)}) — só Instalar, Enxertar ou Ler`,
    };
  }
  for (let i = 1; i < indices.length; i++) {
    if (indices[i] !== indices[i - 1] + 1) {
      return {
        tipo: "malformado",
        motivo: `caminho fora da ordem fixa Instalar → Enxertar → Ler, sem pular nem repetir (${JSON.stringify(pedacos)})`,
      };
    }
  }
  return { tipo: "ok", ultimaTrilha: pedacos[pedacos.length - 1] };
}

/** Classifica a célula inteira de Veredito de uma linha pós-corte. */
function classificarVeredito(veredictoCru) {
  const cru = String(veredictoCru || "").replace(/^\*+|\*+$/g, "").trim();
  if (normalizar(cru) === normalizar(TERMINAL)) {
    return { tipo: "ok" };
  }

  const idx = cru.indexOf(":");
  if (idx === -1) {
    return {
      tipo: "ausente",
      motivo: `nenhum caminho de cascata declarado — esperado "Trilha: veredito" ou "${TERMINAL}", veio ${JSON.stringify(cru)}`,
    };
  }

  const caminhoTexto = cru.slice(0, idx);
  const veredictoTexto = cru.slice(idx + 1).trim();
  const classCaminho = classificarCaminho(caminhoTexto);

  if (classCaminho.tipo === "ausente") {
    return {
      tipo: "ausente",
      motivo: `nenhuma trilha reconhecível no caminho declarado (${JSON.stringify(caminhoTexto.trim())})`,
    };
  }
  if (classCaminho.tipo === "malformado") {
    return { tipo: "malformado", motivo: classCaminho.motivo };
  }

  const opcoes = VOCAB[classCaminho.ultimaTrilha];
  const vNorm = normalizar(veredictoTexto);
  if (!opcoes.includes(vNorm)) {
    return {
      tipo: "veredito_invalido",
      motivo: `veredito ${JSON.stringify(veredictoTexto)} não está no vocabulário de ${classCaminho.ultimaTrilha} (esperado: ${opcoes.join(" | ")})`,
    };
  }
  return { tipo: "ok" };
}

// =========================================================== Leitura da tabela

/** Divide uma linha `| a | b | c |` em ["a","b","c"], sem depender de lib externa. */
function celulasDaLinha(linha) {
  const partes = linha.split("|");
  // remove o vazio antes do primeiro '|' e depois do último '|'
  if (partes.length && partes[0].trim() === "") partes.shift();
  if (partes.length && partes[partes.length - 1].trim() === "") partes.pop();
  return partes.map((c) => c.trim());
}

function ehLinhaSeparadora(cels) {
  return cels.length > 0 && cels.every((c) => /^:?-+:?$/.test(c));
}

/**
 * Extrai as linhas de dados da tabela sob o cabeçalho "## Avaliados". Devolve
 * `{ linhas, erro }` — `erro` string quando a tabela não foi encontrada ou uma
 * linha de dados não tem 5 colunas (falha estrutural, exit 1).
 */
function extrairTabelaAvaliados(texto) {
  const linhas = texto.split(/\r?\n/);
  const inicio = linhas.findIndex((l) => /^##\s+Avaliados\s*$/.test(l.trim()));
  if (inicio === -1) {
    return { erro: 'seção "## Avaliados" não encontrada no arquivo' };
  }
  let fim = linhas.length;
  for (let i = inicio + 1; i < linhas.length; i++) {
    if (/^##\s+/.test(linhas[i].trim())) {
      fim = i;
      break;
    }
  }
  const bloco = linhas.slice(inicio + 1, fim);
  const linhasTabela = [];
  for (let i = 0; i < bloco.length; i++) {
    const bruta = bloco[i];
    if (!bruta.trim().startsWith("|")) continue;
    const cels = celulasDaLinha(bruta);
    if (ehLinhaSeparadora(cels)) continue;
    linhasTabela.push({ numeroNoArquivo: inicio + 2 + i, cels, bruta });
  }
  if (linhasTabela.length === 0) {
    return { erro: 'tabela sob "## Avaliados" não tem nenhuma linha de dados' };
  }
  // A primeira linha remanescente é o cabeçalho ("| Repo | Data | ... |").
  const [, ...dados] = linhasTabela;
  for (const l of dados) {
    if (l.cels.length < 3) {
      return {
        erro: `linha ${l.numeroNoArquivo} da tabela "Avaliados" não tem as colunas mínimas (Repo, Data, Veredito): ${JSON.stringify(l.bruta)}`,
      };
    }
  }
  return { linhas: dados };
}

// ===================================================================== main

function main() {
  const arquivo = ler("arquivo") || ARQUIVO_PADRAO;
  const corte = ler("corte") || CORTE_PADRAO;

  if (!/^\d{4}-\d{2}-\d{2}$/.test(corte)) {
    erroUso(`--corte precisa estar no formato AAAA-MM-DD, veio ${JSON.stringify(corte)}`);
  }

  if (!fs.existsSync(arquivo) || !fs.statSync(arquivo).isFile()) {
    console.error(`erro: --arquivo não existe: ${arquivo}`);
    process.exit(1);
  }

  const texto = fs.readFileSync(arquivo, "utf8");
  const { linhas, erro } = extrairTabelaAvaliados(texto);
  if (erro) {
    console.error(`erro: ${erro}`);
    process.exit(1);
  }

  console.log(`arquivo : ${arquivo}`);
  console.log(`corte   : ${corte} (exclusivo — data igual ao corte NÃO é validada)`);
  console.log(`linhas  : ${linhas.length} na tabela "Avaliados"`);
  console.log("");

  const recusas = { veredito_invalido: [], ausente: [], malformado: [] };
  let checadas = 0;
  let ignoradasPreCorte = 0;

  for (const l of linhas) {
    const [repo, data, veredito] = l.cels;
    const dataNorm = String(data || "").trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dataNorm)) {
      console.error(
        `erro: linha ${l.numeroNoArquivo} tem data ilegível na coluna Data: ${JSON.stringify(data)}`
      );
      process.exit(1);
    }

    // Comparação lexicográfica basta: formato ISO AAAA-MM-DD é largura fixa e
    // ordena igual à comparação de datas de verdade.
    if (!(dataNorm > corte)) {
      ignoradasPreCorte += 1;
      continue;
    }

    checadas += 1;
    const classificacao = classificarVeredito(veredito);
    if (classificacao.tipo === "ok") continue;

    const registro = `${repo} (linha ${l.numeroNoArquivo}, data ${dataNorm}): ${classificacao.motivo} — veredito bruto: ${JSON.stringify(veredito)}`;
    recusas[classificacao.tipo].push(registro);
  }

  console.log(`ignoradas (data <= corte, D8) : ${ignoradasPreCorte}`);
  console.log(`checadas  (data > corte)      : ${checadas}`);
  console.log("");

  const totalRecusas =
    recusas.veredito_invalido.length + recusas.ausente.length + recusas.malformado.length;

  if (totalRecusas === 0) {
    console.log(`APROVADO — nenhuma recusa entre as ${checadas} linha(s) posteriores ao corte.`);
    process.exit(0);
  }

  console.log(`REPROVADO — ${totalRecusas} recusa(s):`);
  if (recusas.malformado.length) {
    console.log(`\n  CAMINHO DE CASCATA MALFORMADO (${recusas.malformado.length}):`);
    for (const r of recusas.malformado) console.log(`    - ${r}`);
  }
  if (recusas.ausente.length) {
    console.log(`\n  TRILHA AUSENTE (${recusas.ausente.length}):`);
    for (const r of recusas.ausente) console.log(`    - ${r}`);
  }
  if (recusas.veredito_invalido.length) {
    console.log(`\n  VEREDITO FORA DO VOCABULÁRIO (${recusas.veredito_invalido.length}):`);
    for (const r of recusas.veredito_invalido) console.log(`    - ${r}`);
  }
  console.log("");

  if (recusas.malformado.length) process.exit(4);
  if (recusas.ausente.length) process.exit(3);
  process.exit(2);
}

main();
