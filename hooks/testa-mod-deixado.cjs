#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura do "deixado para depois" (hooks/deixado-puro.mjs).
// Uso: node hooks/testa-mod-deixado.cjs
//
// O .mjs nao roda em Node dentro do mod, mas aqui e importado como biblioteca. Os textos
// de entrada que vieram do repo estao COLADOS abaixo (nao lidos do arquivo): o arquivo
// muda, a frase que a regex precisa distinguir nao.
//
// A mutacao (`DITO.test(semCitacao(parte))` -> `DITO.test(parte)` na pipeline de
// `deferimentos`) e rodada por `scripts/conferir-mutacao.cjs`; o caso "frase entre aspas
// ou crase nao conta como adiamento" precisa ficar vermelho.

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const MJS = pathToFileURL(path.resolve(__dirname, "deixado-puro.mjs")).href;

function afirma(cond, msg) {
  if (!cond) throw new Error(msg);
}
function igual(a, b, msg) {
  const x = JSON.stringify(a);
  const y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}\n        esperado: ${y}\n        veio    : ${x}`);
}

// ------------------------------------------------------- linhas reais do repo (coladas)
const L_CONSOLIDADO_111 = "9. **Fluxo 4 (território)** fica para depois do núcleo estável —";
const L_HANDOVER_60 = "- Saída direcionada a IA, não a humanos (sem HTML bonito por enquanto; INDEX.md + graph.json bastam)";
// design/2026-10-07-desk-no-mod.md linhas 33 e 34: as mesmas frases, mas entre aspas.
const L_DESIGN_33 = '  (a) varredura de frases em português e inglês ("por enquanto", "não rodei", "fica para';
const L_DESIGN_34 = '  depois", "próxima fase", "placeholder"…); (b) marcadores em arquivo como no original';
// "TODO" como palavra portuguesa (achado 6 do plano): as cinco linhas reais.
const TODO_PT = [
  " * corpo de TODO heredoc, citado ou nao, como se fosse sempre dado literal.",
  "    // negaria TODO despacho justamente no repositorio que a implementa.",
  "# ele encareceria TODO tool call para servir um caso so.",
  "  // portaria, que e fail-closed, negar TODO despacho no repositorio que a",
  " * O fonte é restaurado em TODO caminho de saída, inclusive erro e sinal: deixar",
];

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);

(async () => {
  const m = await import(MJS);

  // ---------------------------------------------------------------- deferimentos
  caso("linha real do consolidado: 'fica para depois' acha 1", () => {
    igual(m.deferimentos(L_CONSOLIDADO_111).length, 1, "consolidado:111");
    afirma(m.deferimentos(L_CONSOLIDADO_111)[0].includes("fica para depois"), "a frase some do item");
  });
  caso("linha real do handover: 'por enquanto' acha 1", () => {
    igual(m.deferimentos(L_HANDOVER_60).length, 1, "handover:60");
    afirma(m.deferimentos(L_HANDOVER_60)[0].includes("por enquanto"), "a frase some do item");
  });
  caso("linhas 33 e 34 do design: as mesmas frases entre aspas, 0", () => {
    igual(m.deferimentos(L_DESIGN_33 + " " + L_DESIGN_34).length, 0, "design:33-34");
  });
  caso("frase entre aspas ou crase nao conta como adiamento", () => {
    igual(m.deferimentos('O comentario do commit diz "por enquanto" e nada mais que isso.').length, 0, "aspas retas");
    igual(m.deferimentos("O comentario do commit diz “por enquanto” e nada mais que isso.").length, 0, "aspas curvas");
    igual(m.deferimentos("O comentario do commit diz `por enquanto` e nada mais que isso.").length, 0, "crase");
    igual(m.deferimentos("Deixei isso por enquanto, depois eu volto nele.").length, 1, "a mesma frase sem aspas conta");
  });
  caso("positivo em ingles", () => {
    igual(m.deferimentos("I haven't run the tests yet.").length, 1, "haven't");
    igual(m.deferimentos("Handling the retry is out of scope for this change.").length, 1, "out of scope");
    igual(m.deferimentos("That path is stubbed for now so the rest compiles.").length, 1, "stubbed");
  });
  caso("'nao rodei' com e sem acento, e em caixa alta", () => {
    igual(m.deferimentos("Não rodei a bateria completa depois da mudança.").length, 1, "com acento");
    igual(m.deferimentos("Nao rodei a bateria completa depois da mudanca.").length, 1, "sem acento");
    igual(m.deferimentos("NÃO RODEI a bateria completa depois da mudança.").length, 1, "caixa alta");
    igual(m.deferimentos("A proxima fase cuida do relatorio mensal.").length, 1, "proxima fase sem acento");
    igual(m.deferimentos("A próxima fase cuida do relatório mensal.").length, 1, "próxima fase com acento");
  });
  caso("bloco de codigo e ignorado", () => {
    const resposta = "Segue o trecho:\n```js\n// por enquanto retorna vazio\nreturn [];\n```\nTudo certo com a leitura.";
    igual(m.deferimentos(resposta).length, 0, "adiamento dentro de bloco");
  });
  caso("no maximo 3 por resposta, cada um com ate 200 caracteres", () => {
    const cinco = [1, 2, 3, 4, 5].map(n => "Item " + n + " fica para depois, por enquanto.").join("\n");
    igual(m.deferimentos(cinco).length, 3, "teto de 3");
    const longa = "Isso fica para depois " + "x".repeat(400) + ".";
    igual(m.deferimentos(longa)[0].length, 200, "corte em 200");
  });
  caso("frases comuns de relato concluido nao acusam", () => {
    igual(m.deferimentos("Rodei os testes e todos passaram. O commit foi para a branch.").length, 0, "relato limpo");
    igual(m.deferimentos("").length, 0, "vazio");
    igual(m.deferimentos(undefined).length, 0, "undefined");
  });

  // ------------------------------------------------------- marcadoresEmArquivo
  caso("marcador: // TODO: tratar timeout (sintetico, nao existe positivo real no repo)", () => {
    igual(m.marcadoresEmArquivo("function f() {\n  // TODO: tratar timeout\n}").length, 1, "TODO:");
  });
  caso("marcador: FIXME(ana)", () => {
    igual(m.marcadoresEmArquivo("// FIXME(ana) vazamento aqui").length, 1, "FIXME(");
  });
  caso("marcador: .skip( em teste", () => {
    igual(m.marcadoresEmArquivo("it.skip('mede o cache', () => {});").length, 1, ".skip(");
  });
  caso("marcador: TODO como palavra portuguesa nao acusa (as 5 linhas reais do achado 6)", () => {
    for (const linha of TODO_PT) igual(m.marcadoresEmArquivo(linha).length, 0, "linha: " + linha.trim());
    igual(m.marcadoresEmArquivo(TODO_PT.join("\n")).length, 0, "as cinco juntas");
  });
  caso("marcador: devolve a linha, ate 3", () => {
    const achados = m.marcadoresEmArquivo(["// TODO: a", "// TODO: b", "// TODO: c", "// TODO: d"].join("\n"));
    igual(achados.length, 3, "teto de 3");
    igual(achados[0], "// TODO: a", "a linha, aparada");
  });

  // ------------------------------------------------------ resumirFerramentas
  caso("resumo das ferramentas: Bash x12 (2 erros), Edit x3, Write x1 (1 negada)", () => {
    const f = [];
    for (let i = 0; i < 12; i++) f.push({ tool: "Bash", isError: i < 2 });
    for (let i = 0; i < 3; i++) f.push({ tool: "Edit" });
    f.push({ tool: "Write", deny: true });
    igual(m.resumirFerramentas(f), "Bash x12 (2 erros), Edit x3, Write x1 (1 negada)", "resumo");
    igual(m.resumirFerramentas([{ tool: "Bash", isError: true }]), "Bash x1 (1 erro)", "singular");
    igual(m.resumirFerramentas([]), "", "vazio");
  });

  // ----------------------------------------------------- montarPromptChecker
  caso("prompt do checker leva pedido, ferramentas com falhas e os ultimos 6000 do relato", () => {
    const relato = "INICIO-" + "a".repeat(7000) + "-FIM";
    const ferramentas = [{ tool: "Bash", isError: true }, { tool: "Bash" }, { tool: "Edit" }];
    const p = m.montarPromptChecker({ pedido: "me diga o status do fluxo 4", relato, ferramentas });
    afirma(p.includes("me diga o status do fluxo 4"), "o pedido some");
    afirma(p.includes("Bash x2 (1 erro), Edit x1"), "a lista de ferramentas some");
    afirma(p.includes("-FIM"), "o fim do relato some");
    afirma(!p.includes("INICIO-"), "o comeco do relato nao devia entrar");
    afirma(p.endsWith(relato.slice(-6000)), "os ultimos 6000 caracteres nao entram inteiros");
    afirma(p.includes("NENHUM"), "falta a palavra NENHUM");
    afirma(/no maximo 3 linhas/i.test(p) && /verbo/.test(p), "falta o pedido de 3 linhas por verbo");
    afirma(/Voce compara/.test(p), "o prompt nao esta em portugues");
  });

  // ---------------------------------------------------- lerRespostaChecker
  caso("resposta do checker: NENHUM vira lista vazia; itens limpos e limitados a 3", () => {
    igual(m.lerRespostaChecker("NENHUM"), [], "NENHUM");
    igual(m.lerRespostaChecker("nenhum."), [], "nenhum.");
    igual(m.lerRespostaChecker(""), [], "vazio");
    igual(m.lerRespostaChecker("Rodar a bateria da tarefa 2"), ["Rodar a bateria da tarefa 2"], "um item");
    igual(m.lerRespostaChecker("1. Rodar a bateria\n- Abrir o PR\n* Atualizar o README\n4. Fechar a issue"),
      ["Rodar a bateria", "Abrir o PR", "Atualizar o README"], "numeracao e teto");
  });

  // -------------------------------------------------------- rascunhoFazAgora
  caso("rascunho do 'Faz agora' esta em portugues e leva a frase", () => {
    const r = m.rascunhoFazAgora("Rodar a bateria da tarefa 2");
    afirma(r.includes("Rodar a bateria da tarefa 2"), "a frase some");
    afirma(/Faça agora/.test(r), "o rascunho nao esta em portugues, com acento");
  });

  // -------------------------------------------- texto do modelo sem controle (achado A)
  const PERIGO = /[\u0000-\u001f\u007f-\u009f‪-‮]/;
  caso("deferimentos: ESC, BEL e override bidi nao chegam ao item", () => {
    const r = m.deferimentos("Fica para depois a parte \x1b]0;pwn\x07 do relatorio ‮ final.");
    igual(r.length, 1, "a frase continua acusando");
    afirma(!PERIGO.test(r[0]), "sobrou controle em " + JSON.stringify(r[0]));
  });
  caso("lerRespostaChecker: ESC, BEL e override bidi nao chegam ao item", () => {
    const r = m.lerRespostaChecker("Rodar a bateria \x1b[31m vermelha\x07 agora ‮ fim\n- Abrir \x1b]0;x\x07 o PR");
    igual(r.length, 2, "dois itens");
    afirma(r.every(x => !PERIGO.test(x)), "sobrou controle em " + JSON.stringify(r));
  });
  caso("marcadoresEmArquivo: ESC, BEL e override bidi nao chegam a linha", () => {
    const r = m.marcadoresEmArquivo("// TODO: \x1b]0;pwn\x07 tratar ‮ timeout");
    igual(r.length, 1, "TODO acha");
    afirma(!PERIGO.test(r[0]), "sobrou controle em " + JSON.stringify(r[0]));
  });

  // ---------------------------------------------------- varredura de frases (achado G)
  caso("falsos negativos: ficou/fica/ficaram para ou pra depois e ficou faltando acusam", () => {
    for (const f of [
      "A parte do relatorio ficou para depois por falta de tempo.",
      "A parte do relatorio fica pra depois, sem pressa nenhuma.",
      "A parte do relatorio ficou pra depois, sem pressa nenhuma.",
      "Os ajustes de layout ficaram para depois da entrega.",
      "O tratamento de timeout ficou faltando na versao final.",
      "Dois casos de borda ficaram faltando na bateria nova.",
    ]) igual(m.deferimentos(f).length, 1, f);
  });
  caso("falso positivo: negacao desfaz o adiamento", () => {
    igual(m.deferimentos("Nada fica para depois nesta entrega, tudo foi feito.").length, 0, "nada fica para depois");
    igual(m.deferimentos("Nenhum item ficou pra depois nesta entrega, tudo foi feito.").length, 0, "nenhum item ficou pra depois");
    igual(m.deferimentos("Nao ficou faltando nada nesta entrega, tudo foi feito.").length, 0, "nao ficou faltando");
    igual(m.deferimentos("Nada fica para depois, mas o relatorio ficou para depois mesmo.").length, 1, "negacao nao apaga outra frase positiva");
  });
  caso("CHECAR_MIN_FERRAMENTAS e 5", () => {
    igual(m.CHECAR_MIN_FERRAMENTAS, 5, "limiar");
  });
  // Issue #424: itens abertos no prompt, linhas RESOLVIDO e decisao Q<n>.
  caso("prompt do checker leva os itens abertos com id, ou (nenhuma)", () => {
    const p = m.montarPromptChecker({ pedido: "x", relato: "y", ferramentas: [], abertos: [{ id: 3, texto: "Criar card Jira" }, { id: 5, texto: "Baixar XML" }] });
    afirma(p.includes("PENDENCIAS ABERTAS:\n3: Criar card Jira\n5: Baixar XML"), "abertos com id");
    afirma(p.includes("RESOLVIDO <id>"), "formato da resolucao");
    afirma(m.montarPromptChecker({ pedido: "x", relato: "y", ferramentas: [] }).includes("PENDENCIAS ABERTAS:\n(nenhuma)"), "sem abertos");
  });
  caso("lerResolvidosChecker: so ids abertos, sem repetir, aceita D3 e caixa baixa", () => {
    igual(m.lerResolvidosChecker("RESOLVIDO 3: card criado\nresolvido D5: xml baixado\nRESOLVIDO 9: nao existe\nRESOLVIDO 3: de novo\nBaixar PDF", [3, 5, 7]), [3, 5], "ids");
    igual(m.lerResolvidosChecker("NENHUM", [3]), [], "nenhum");
  });
  caso("lerRespostaChecker nao devolve linha RESOLVIDO e ela nao come a cota de 3", () => {
    igual(m.lerRespostaChecker("RESOLVIDO 1: a\nRESOLVIDO 2: b\nFazer A\nFazer B\nFazer C"), ["Fazer A", "Fazer B", "Fazer C"], "novos");
  });
  caso("perguntaDecisao: Q1., **Q2**, Q3: e > Q4 acusam; Q em codigo ou no meio da frase nao", () => {
    for (const r of ["Feito.\n\nQ1. Mando?", "Feito.\n**Q2** Mando?", "Feito.\n- Q3: Mando?", "Feito.\n> Q4. Mando?"]) afirma(m.perguntaDecisao(r), r);
    for (const r of ["Feito, sem pendencias.", "```\nQ1. dentro de codigo\n```", "Fechei o Q1 do trimestre."]) afirma(!m.perguntaDecisao(r), r);
  });
  caso("deferimentos ignora a linha Q de decisao e mantem a frase fora dela", () => {
    igual(m.deferimentos("Q1. Fica para depois o envio, ou mando agora?").length, 0, "linha Q");
    igual(m.deferimentos("O relatorio ficou para depois.\nQ1. Fica para depois o envio?").length, 1, "frase fora da Q");
  });

  let ok = 0;
  let falhou = 0;
  for (const [nome, fn] of casos) {
    try {
      await fn();
      ok += 1;
      console.log(`  ok    ${nome}`);
    } catch (e) {
      falhou += 1;
      console.log(`  FALHA ${nome}`);
      console.log(`        ${String((e && e.message) || e).split("\n").join("\n        ")}`);
    }
  }
  console.log(`resultado: ${ok} ok, ${falhou} falha(s), 0 skipped`);
  process.exit(falhou === 0 ? 0 : 1);
})();
