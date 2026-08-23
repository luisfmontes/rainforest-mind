#!/usr/bin/env node
/**
 * Confere ENCODING dos arquivos de texto rastreados pelo git — mojibake, BOM e
 * (opcionalmente) CRLF — e RECUSA com exit code, no estilo de conferir-publicacao.cjs
 * e conferir-entrega.cjs.
 *
 * POR QUE EXISTE, com número. O `README.md` renderizava
 * "O problema nAo A(c) falta de ideia" no GitHub: 387 linhas de mojibake, mais BOM.
 * O arquivo inteiro passou por um round-trip que leu UTF-8 como CP1252 e regravou
 * como UTF-8 com BOM (assinatura de `Get-Content` lido como ANSI, seguido de
 * `Out-File -Encoding utf8`). Entrou no commit `daee1d6` (PR #55) e atravessou o PR
 * inteiro sem nada pegar: 44 baterias verdes, CI verde, revisao feita. So apareceu
 * quando alguem abriu o README no navegador, dois dias depois. Consertado no
 * commit `a1433d1` (PR #64). NENHUMA bateria deste repositorio olhava encoding de
 * arquivo versionado — e essa e a lacuna que este script fecha.
 *
 * DETECCAO DE MOJIBAKE — sequencia, nao heuristica frouxa. UTF-8 lido como
 * CP1252/Latin-1 tem uma assinatura MECANICA: todo caractere acentuado
 * portugues (U+00C0-U+00FF) vira 2 bytes em UTF-8, primeiro byte 0xC3, segundo
 * byte 0x80-0xBF. Decodificado como CP1252, 0xC3 vira sempre "Ã" (ou "Â" para o
 * bloco anterior, U+0080-U+00BF via primeiro byte 0xC2), e o segundo byte vira UM
 * dos ~62 caracteres fixos da tabela CP1252 para 0x80-0xBF (pontuacao tipografica
 * — "€‚ƒ„…†‡ˆ‰Š‹Œ..."–—..." — mais o bloco Latin-1 "¡¢£¤¥¦§¨©ª«¬..."). Aspas e
 * travessao tipografico (—, ", ", …) sao 3 bytes UTF-8 (0xE2 0x80 0xXX) e viram
 * "â€" + um desses MESMOS caracteres da tabela. Este script constroi essa tabela
 * (CP1252_ESPECIAIS, abaixo — copia literal da secao 0x80-0x9F do Windows-1252) e
 * casa "Ã"/"Â"/"â€" seguido de um membro dela. E preciso porque a condicao nao e
 * "contem Ã" (letra valida em portugues, ainda que rara) — e "Ã seguido de um
 * caractere que SO aparece nessa tabela de round-trip", o que uma palavra legitima
 * jamais produz (nenhuma palavra portuguesa tem "Ã" seguido de "©" ou de um
 * travessao colado). Reconstrua daee1d6:README.md para ver a assinatura real —
 * e o teste de regressao deste script faz exatamente isso.
 *
 * QUAIS ARQUIVOS ENTRAM. `git ls-files` (rastreados — arquivo nao commitado nao e
 * o problema que este script existe para pegar) menos os que `git check-attr text`
 * reporta como `unset` — e a via CANONICA, porque e a mesma fonte que o Git usa
 * para decidir binario/texto (`*.png binary` etc. no .gitattributes), entao um
 * binario novo so precisa de UMA regra, no .gitattributes, para ficar de fora dos
 * dois lugares. Como cinto-e-suspensorio para o binario que ainda nao ganhou regra,
 * todo arquivo tambem passa por deteccao de byte NUL nos primeiros 8000 bytes
 * (heuristica padrao de "e binario" — a mesma que o proprio Git usa). `assets/*.svg`
 * E TEXTO (XML) e ENTRA na varredura — SVG sofre o mesmo round-trip que qualquer
 * outro texto, e excluir por extensao "porque e asset" deixaria peixe passando
 * pela rede so por causa da pasta.
 *
 * O QUE FAZER COM O PASSADO (CONTRIBUTING.md, "campo obrigatorio novo vem com o
 * passado resolvido"). Este gate e novo, mas o INCIDENTE que ele existe para pegar
 * ja foi corrigido, no mesmo repositorio, ANTES desta trava nascer: o commit
 * `a1433d1` (PR #64) e a base deste commit (`adb3b96`) ja carregam o README limpo.
 * Rodar este script contra a arvore inteira na base (bloco 3 do relatorio de
 * entrega) da exit 0 — ZERO arquivos violam. Isso nao e um caso do menu de tres
 * caminhos do CONTRIBUTING (backfill / anistia por data / opcional para quem
 * nasceu antes): esses tres existem para uma divida que PERSISTE no acervo e
 * precisa de uma decisao sobre como tratar o que ja existe. Aqui nao ha divida —
 * o passado ja estava resolvido antes do gate existir, e um gate que nasce verde
 * porque a arvore ja esta limpa nao precisa de anistia para nada. Se um mojibake
 * novo entrar amanha, o gate pega no commit que o introduziu, sem exceber ninguem.
 *
 * FALSO POSITIVO MEDIDO, e a supressao que ele ganhou (nao inventada, achada rodando
 * este script contra a arvore inteira na base): `vigias/run-vigia.ps1:77` documenta
 * a PROPRIA assinatura de mojibake num comentario ("...mojibake (Ã§, â€")..."),
 * como exemplo para quem le o script entender o sintoma. E texto correto, em UTF-8
 * legitimo, que so bate no detector porque o detector faz exatamente o que devia:
 * reconhecer a sequencia. Apertar a heuristica para excluir este caso especifico
 * (ex.: "ignora se a linha contiver a palavra mojibake") abriria uma fresta generica
 * que um mojibake de verdade poderia atravessar so por citar essa palavra por perto.
 * A saida e supressao PONTUAL, na linha: o marcador `rf-encoding-exemplo` (texto
 * puro, funciona dentro de comentario de qualquer linguagem) faz este script pular
 * a linha que o contem. Sem o marcador, a linha reprova normalmente — a excecao e
 * nomeada e visivel no arquivo que a usa, nao escondida numa lista neste script.
 *
 * BOM — arquivo de texto rastreado comecando com EF BB BF (BOM de UTF-8) reprova.
 * O `Out-File -Encoding utf8` do PowerShell grava BOM por padrao; e a segunda
 * metade da assinatura do incidente.
 *
 * CRLF — coberto aqui, e NAO E DUPLICATA do preflight de
 * `.github/workflows/baterias.yml` ("Preflight — ... a arvore veio em LF"): aquele
 * preflight roda `git ls-files --eol skills hooks` — SO essas duas pastas. Este
 * script varre a MESMA lista completa de arquivos rastreados (raiz, scripts/,
 * commands/, agents/, docs/, .github/, etc.), entao cobre o que o preflight
 * deliberadamente deixa de fora. Reusa a mesma tecnica do preflight
 * (`git ls-files --eol`), so que no universo inteiro.
 *
 * Uso:
 *   node scripts/conferir-encoding.cjs                 # varre git ls-files do repo (cwd)
 *   node scripts/conferir-encoding.cjs <arquivo...>     # confere so os arquivos dados
 *   node scripts/conferir-encoding.cjs --json [...]
 *
 * Exit:
 *   0  nada encontrado
 *   1  erro de uso (arquivo inexistente, fora de repo git no modo de arvore)
 *   2  RECUSADO — mojibake, BOM ou CRLF achado
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// Tabela literal Windows-1252 para bytes 0x80-0x9F (indice 0 = byte 0x80).
// Posicoes indefinidas na tabela classica (0x81, 0x8D, 0x8F, 0x90, 0x9D) o WHATWG
// Encoding Standard define como o proprio codepoint de controle C1 — e o que
// `TextDecoder('windows-1252')` de fato devolve, entao e o que um round-trip real
// produziria se aparecesse.
const CP1252_80_9F = [
  0x20ac, 0x0081, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
  0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008d, 0x017d, 0x008f,
  0x0090, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
  0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x009d, 0x017e, 0x0178,
];

// Bloco 0xA0-0xBF mapeia direto para Latin-1 (mesmo codepoint), sempre.
const FECHADORES = new Set(CP1252_80_9F);
for (let b = 0xa0; b <= 0xbf; b++) FECHADORES.add(b);

/**
 * Varre um texto e devolve os achados de mojibake: "Ã"/"Â"/"â€" imediatamente
 * seguido de um caractere que SO aparece por round-trip UTF-8-como-CP1252.
 */
const MARCADOR_SUPRESSAO = 'rf-encoding-exemplo';

function achaMojibake(texto) {
  const achados = [];
  const linhas = texto.split(/\r\n|\r|\n/);
  linhas.forEach((linha, i) => {
    if (linha.includes(MARCADOR_SUPRESSAO)) return; // supressao pontual, ver cabecalho
    for (let j = 0; j < linha.length; j++) {
      const ch = linha[j];
      let tam = 0;
      if (ch === 'Ã' || ch === 'Â') {
        tam = 1;
      } else if (ch === 'â' && linha[j + 1] === '€') {
        tam = 2;
      }
      if (!tam) continue;
      const prox = linha.codePointAt(j + tam);
      if (prox !== undefined && FECHADORES.has(prox)) {
        const inicio = Math.max(0, j - 8);
        const trecho = linha.slice(inicio, j + tam + 2);
        achados.push({ linha: i + 1, trecho });
      }
    }
  });
  return achados;
}

/** BOM de UTF-8 no inicio do buffer. */
function temBOM(buf) {
  return buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf;
}

/** Heuristica padrao de binario: byte NUL nos primeiros 8000 bytes. */
function pareceBinario(buf) {
  const limite = Math.min(buf.length, 8000);
  for (let i = 0; i < limite; i++) {
    if (buf[i] === 0) return true;
  }
  return false;
}

function git(dir, args) {
  const r = spawnSync('git', args, { cwd: dir, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  return { rc: r.status, out: (r.stdout || '').replace(/\r?\n$/, ''), err: r.stderr || '' };
}

/** Lista arquivos rastreados que valem a checagem: texto (attr) e nao-binario (conteudo). */
function arquivosDaArvore(repoDir) {
  const ls = git(repoDir, ['ls-files', '-z']);
  if (ls.rc !== 0) return null; // nao e repo git
  const todos = ls.out.length ? ls.out.split('\0').filter(Boolean) : [];
  if (!todos.length) return [];

  const attrRaw = git(repoDir, ['check-attr', 'text', '--', ...todos]);
  const binarioPorAttr = new Set();
  if (attrRaw.rc === 0) {
    for (const linha of attrRaw.out.split(/\r?\n/)) {
      const m = linha.match(/^(.*): text: (.*)$/);
      if (m && m[2].trim() === 'unset') binarioPorAttr.add(m[1]);
    }
  }
  return todos.filter((f) => !binarioPorAttr.has(f));
}

/** CRLF na arvore de trabalho, via `git ls-files --eol` (mesma tecnica do preflight de CI). */
function crlfNaArvore(repoDir, arquivos) {
  if (!arquivos.length) return [];
  const r = git(repoDir, ['ls-files', '--eol', '--', ...arquivos]);
  if (r.rc !== 0) return [];
  const achados = [];
  for (const linha of r.out.split(/\r?\n/)) {
    if (!linha) continue;
    const m = linha.match(/^i\/\S+\s+w\/(\S+)\s+\S+\s+(.*)$/);
    if (m && (m[1] === 'crlf' || m[1] === 'mixed')) {
      achados.push({ arquivo: m[2], eol: m[1] });
    }
  }
  return achados;
}

function confereArquivo(caminhoAbs, nomeExibido) {
  const problemas = [];
  let buf;
  try {
    buf = fs.readFileSync(caminhoAbs);
  } catch (e) {
    return [{ tipo: 'erro-leitura', detalhe: String(e.message || e) }];
  }
  if (pareceBinario(buf)) return []; // fora do escopo, silenciosamente

  if (temBOM(buf)) problemas.push({ tipo: 'bom' });

  const texto = buf.toString('utf8');
  for (const a of achaMojibake(texto)) {
    problemas.push({ tipo: 'mojibake', linha: a.linha, trecho: a.trecho });
  }
  return problemas;
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const alvos = args.filter((a) => !a.startsWith('--'));

  const achadosPorArquivo = []; // { arquivo, problemas: [...] }
  let crlf = [];

  if (alvos.length) {
    // Modo arquivo(s) explicito(s) — sem git ls-files, sem checagem de CRLF (nao
    // ha "arvore de trabalho git" garantida; quem quer CRLF usa o modo de arvore).
    for (const alvo of alvos) {
      if (!fs.existsSync(alvo)) {
        console.error(`erro: arquivo nao encontrado: ${alvo}`);
        process.exit(1);
      }
      const problemas = confereArquivo(alvo, alvo);
      if (problemas.length) achadosPorArquivo.push({ arquivo: alvo, problemas });
    }
  } else {
    // Modo arvore — varre git ls-files do repo em cwd.
    const repoDir = process.cwd();
    const arquivos = arquivosDaArvore(repoDir);
    if (arquivos === null) {
      console.error('erro: nao estou dentro de um repositorio git (modo de arvore exige --, ou passe arquivos explicitos)');
      process.exit(1);
    }
    for (const rel of arquivos) {
      const abs = path.join(repoDir, rel);
      const problemas = confereArquivo(abs, rel);
      if (problemas.length) achadosPorArquivo.push({ arquivo: rel, problemas });
    }
    crlf = crlfNaArvore(repoDir, arquivos);
  }

  const totalMojibakeBom = achadosPorArquivo.reduce((n, a) => n + a.problemas.length, 0);
  const reprovado = totalMojibakeBom > 0 || crlf.length > 0;

  if (json) {
    console.log(JSON.stringify({ achados: achadosPorArquivo, crlf }, null, 2));
    process.exit(reprovado ? 2 : 0);
  }

  if (!reprovado) {
    console.log('CONFERIDO — nenhum mojibake, BOM ou CRLF nos arquivos varridos.');
    process.exit(0);
  }

  console.log(`RECUSADO — problema(s) de encoding encontrado(s).\n`);
  for (const a of achadosPorArquivo) {
    for (const p of a.problemas) {
      if (p.tipo === 'bom') {
        console.log(`  ${a.arquivo}  [bom]  arquivo comeca com BOM de UTF-8`);
      } else if (p.tipo === 'mojibake') {
        console.log(`  ${a.arquivo}:${p.linha}  [mojibake]  ...${p.trecho}...`);
      } else {
        console.log(`  ${a.arquivo}  [${p.tipo}]  ${p.detalhe || ''}`);
      }
    }
  }
  for (const c of crlf) {
    console.log(`  ${c.arquivo}  [crlf]  fim de linha ${c.eol} na arvore de trabalho (esperado LF)`);
  }
  console.log('\nCorrija o encoding (regrave como UTF-8 sem BOM, com LF) e rode de novo.');
  process.exit(2);
}

if (require.main === module) main();
module.exports = { achaMojibake, temBOM, pareceBinario, FECHADORES, CP1252_80_9F };
