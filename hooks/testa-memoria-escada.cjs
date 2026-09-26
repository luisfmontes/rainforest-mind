#!/usr/bin/env node
"use strict";
/* Bateria da escada de encaixe do bloco de memória (D1–D4 do design
 * 2026-09-26-memoria-encurta.md).
 *
 * As observações imitam o formato real do banco (`conteudo` = "## Título\n\n
 * Subtítulo\n\n### ..."), com títulos do tamanho medido em 2026-09-26
 * (mediana 254 caracteres, máximo 435) e subtítulos longos (mediana 188 B).
 * Texto fictício,
 * sem dado de ninguém. Chama `montarMemoria` direto: é função pura, sem banco
 * nem disco.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const path = require("path");
const ms = require(path.join(__dirname, "lib", "memoria-sessao.cjs"));

let ok = 0;
let falhou = 0;
function caso(nome, cond, detalhe) {
  if (cond) { ok++; console.log(`  ok   ${nome}`); }
  else { falhou++; console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 400)}` : ""}`); }
}
const B = (s) => Buffer.byteLength(s, "utf8");
const TETO = ms.TETOS.MEMORIA_MAX_BYTES;

const FRASE = "Revisou a entrega do fluxo contra o design e o plano, rodou as baterias, conferiu a mutação na catraca e registrou os achados numerados com arquivo e linha, deixando a premissa aceita sem conferir no fim do relato para quem despachou decidir o que falta";
const SUB = "O subtítulo também é longo no banco real: conta o que mudou, onde, e o que ficou de fora para depois, com o arquivo e o motivo de cada decisão tomada na sessão.";
function obs(i, tamTitulo, sub = SUB) {
  const titulo = (`Obs ${i}: ` + FRASE + " " + FRASE).slice(0, tamTitulo);
  const dia = String(26 - Math.floor(i / 3)).padStart(2, "0");
  return { id: i, projeto: "rainforest-mind", criada_em: `2026-09-${dia}T10:00:00Z`, conteudo: `## ${titulo}\n\n${sub}\n\n### Detalhe\n\ntexto` };
}
const longas = Array.from({ length: 14 }, (_, i) => obs(i, [254, 300, 337, 435, 260, 280][i % 6]));
const textoDe = (l) => l.replace(/^\[[^\]]*\]\s*/, "");

console.log("== escada de encaixe da memória ==");

// 1. Título e subtítulo longos: as 14 entram, encurtadas, com o degrau no aviso.
let s = ms.montarMemoria({ observacoes: longas });
const linhas = s.split("\n").filter((l) => l.startsWith("[2026-"));
caso("14 observações com títulos longos cabem todas com textos encurtados", linhas.length === 14, `${linhas.length} linhas`);
caso("bloco dentro do teto", B(s) <= TETO, `${B(s)} B`);
caso("aviso no topo nomeia o degrau", /^⚠️ Memória acima do orçamento: textos encurtados a \d+ caracteres/.test(s), s.slice(0, 160));
caso("aviso não fala em corte quando nada saiu", !/não couberam/.test(s));
caso("textos (título — subtítulo) terminam em … e não passam do degrau", linhas.every((l) => l.endsWith("…")) &&
  linhas.every((l) => { const m = s.match(/encurtados a (\d+)/); return Array.from(textoDe(l)).length <= Number(m[1]); }));
caso("o texto encurtado mantém o começo do título (corta o fim, não o começo)", linhas.every((l, i) => textoDe(l).startsWith(`Obs ${i}: Revisou`)));
caso("corte cai na palavra (não termina com palavra partida)", linhas.every((l) => / \S+…|[^\s]…/.test(l) && !/\s…/.test(l)));

// 2. Degrau mais alto que cabe é o escolhido: com 10 observações de texto
// longo, algum degrau cabe, e nenhum degrau acima dele caberia.
const medias = Array.from({ length: 10 }, (_, i) => obs(i, 120));
s = ms.montarMemoria({ observacoes: medias });
const degrauMedia = Number((s.match(/encurtados a (\d+)/) || [])[1]);
caso("desce só o necessário (primeiro degrau que cabe)", B(s) <= TETO && ms.DEGRAUS_TEXTO.includes(degrauMedia) &&
  ms.DEGRAUS_TEXTO.filter((d) => d > degrauMedia).every((d) => {
    const linhasD = medias.map((o) => ms.formatarObservacao(o, null, d));
    const aviso = ms.construirAvisoCorteMemoria(0, medias.length, TETO, d);
    return B(aviso + "## Memória (corpus residentes)\n" + linhasD.join("\n") + '\n\nmais: node scripts/memoria.cjs buscar --texto "<termo>"') > TETO;
  }), `degrau ${degrauMedia}, ${B(s)} B`);

// 3. Cabendo inteiro: igual ao de hoje, sem aviso.
const curtas = Array.from({ length: 5 }, (_, i) => obs(i, 60, "Resumo curto."));
s = ms.montarMemoria({ observacoes: curtas });
const esperado = "## Memória (corpus residentes)\n" + curtas.map((o) => ms.formatarObservacao(o)).join("\n") + '\n\nmais: node scripts/memoria.cjs buscar --texto "<termo>"';
caso("cabendo inteiro, saída idêntica à de hoje e sem aviso", s === esperado, s.slice(0, 200));

// 4. Nem 120 basta (mais observações que cabem, mesmo encurtadas): corta as
// mais antigas, aviso diz o degrau e quantas saíram.
const gordas = Array.from({ length: 30 }, (_, i) => obs(i, 435));
s = ms.montarMemoria({ observacoes: gordas });
const linhasG = s.split("\n").filter((l) => l.startsWith("[2026-"));
caso("sem caber em 120, corta observação e diz o degrau", /não couberam/.test(s) && /com textos encurtados a 120 caracteres/.test(s) && linhasG.length < 30 && linhasG.every((l) => Array.from(textoDe(l)).length <= 120), s.slice(0, 200));
caso("corte leva as mais antigas (as primeiras ficam)", linhasG.length > 0 && linhasG[0].includes("Obs 0"));
caso("bloco dentro do teto no corte", B(s) <= TETO, `${B(s)} B`);

// 5. Aviso de pipeline continua presente e acima do corpus.
s = ms.montarMemoria({ observacoes: longas, avisos: ["⚠️ captura parada há 30 h"] });
caso("aviso de pipeline segue no topo do corpus", s.includes("captura parada") && s.indexOf("captura parada") < s.indexOf("## Memória") && B(s) <= TETO);

// 6. encurtarNaPalavra
caso("encurtarNaPalavra: curto não muda", ms.encurtarNaPalavra("abc def", 20) === "abc def");
const e = ms.encurtarNaPalavra("uma frase com várias palavras bem longas aqui", 20);
caso("encurtarNaPalavra: cabe no limite e termina em …", Array.from(e).length <= 20 && e.endsWith("…") && !e.includes(" …"), e);
const g = ms.encurtarNaPalavra("C:/caminho/muito/longo/sem/espaco/nenhum/aqui", 20);
caso("encurtarNaPalavra: palavra única gigante cai no corte por caractere", Array.from(g).length === 20 && g.endsWith("…"), g);

console.log("-----------------------------------------");
console.log(`ok: ${ok}   falhou: ${falhou}`);
process.exit(falhou === 0 ? 0 : 1);
