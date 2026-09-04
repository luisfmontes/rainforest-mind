#!/usr/bin/env node
/**
 * Tokenização de um segmento de comando e localização da POSIÇÃO DE COMANDO
 * dentro dele — quem é o comando de verdade, pulando wrappers que só
 * repassam (`env`, `sudo`, `time`, ...) e as flags deles que consomem valor.
 *
 * Extraído de `hooks/gate-worktree.cjs` (nasceram ali para `procuraCLI`) e
 * generalizado para uso também em `hooks/lib/cwd-efetivo.cjs` (rodada 6,
 * lote 3, 2026-09-03): o K2 do auditor achou `cwdPorSegmento` decidindo se
 * um segmento é um comando `git` por SUBSTRING (`seg.includes("git")`), que
 * casava "git" dentro de "gitignore" citado como argumento de outro comando
 * (`grep -rn -C 3 "gitignore" .`). A mesma noção de posição de comando que
 * `procuraCLI` já usa para achar CLI que escreve resolve o mesmo problema
 * para `git` — em vez de reimplementar, os dois consumidores compartilham
 * este módulo.
 */

/**
 * Quebra em tokens preservando se cada um veio de DENTRO de aspas.
 *
 * `q: true` significa "este texto estava entre aspas" — e um `>` ali e TEXTO,
 * nunca redirecionamento. E o conserto de 2026-09-01: um avaliador de repo de
 * terceiro foi barrado rodando
 *   grep -n "qualified_name\|<project>" README.md
 * — comando sem redirecionamento nenhum. O gate casava o `>` de `<project>` no
 * texto cru do comando. `->`, `=>`, generics e tag HTML sao rotina em busca de
 * codigo, entao o falso positivo era diario e empurrava o agente a reescrever
 * comando legitimo ate passar. `palavras()` ja sabia respeitar aspas para achar
 * subcomando de git; a deteccao de escrita e que tinha ficado no regex cru.
 */
function tokensComAspas(cmd) {
  const out = [];
  let atual = "", aspa = null, temAlgo = false, citado = false;
  for (let i = 0; i < cmd.length; i += 1) {
    const c = cmd[i];
    if (aspa) {
      if (c === aspa) aspa = null;
      else atual += c;
      temAlgo = true;
    } else if (c === '"' || c === "'") {
      aspa = c; temAlgo = true; citado = true;
    } else if (/\s/.test(c)) {
      if (temAlgo) out.push({ v: atual, q: citado });
      atual = ""; temAlgo = false; citado = false;
    } else {
      atual += c; temAlgo = true;
    }
  }
  if (temAlgo) out.push({ v: atual, q: citado });
  return out;
}

/** Nome de comando, ignorando caminho: um binario com caminho resolve para seu nome. */
function ehComando(tok, nome) {
  return !tok.q && new RegExp("(^|[\\\\/])" + nome + "(\\.exe)?$").test(tok.v);
}

// Wrappers que REPASSAM o comando adiante, na MESMA posicao de comando — o
// nome da CLI aparece DEPOIS deles. H3 (rodada 5, lote 3, 2026-09-03): antes
// disto, `procuraCLI` casava o nome em QUALQUER posicao do segmento (so
// pulando token citado em posicao de argumento), e `grep -rn claude .` virava
// falso positivo — "claude" ali e um PADRAO DE BUSCA, argumento do grep,
// nunca um comando.
const WRAPPERS_QUE_REPASSAM = new Set([
  "env", "command", "exec", "nohup", "nice", "timeout", "xargs", "sudo", "time",
]);

/**
 * Acha o INDICE do token que e a posicao de comando de um segmento
 * tokenizado, pulando os wrappers conhecidos (e os argumentos deles que
 * consomem valor). `null` se o segmento acaba dentro dos proprios wrappers
 * (`env` sozinho, sem comando depois).
 *
 * `env`: pula `NOME=valor` (um ou mais) e `-C <dir>`/`--chdir=<dir>`.
 * `nice`: pula `-n <N>` (ou `-N` colado).
 * `timeout`: pula as flags (`-s`, `--signal=...`) e a duracao posicional.
 * `sudo`: pula `-u <usuario>`/`-g <grupo>` (e as formas longas
 * `--user`/`--group`, com `=` ou espaco) — sem isso, `sudo -u x git add -A`
 * parava na flag do wrapper (M1, auditor, 5a revisao, 2026-09-03).
 * Os demais (`command`, `exec`, `nohup`, `xargs`, `time`) so pulam o proprio
 * nome — o comando de verdade e o token seguinte.
 */
function posicaoDeComando(toks) {
  let i = 0;
  while (i < toks.length && !toks[i].q && WRAPPERS_QUE_REPASSAM.has(toks[i].v)) {
    const wrapper = toks[i].v;
    i += 1;
    if (wrapper === "env") {
      while (i < toks.length && !toks[i].q && /^[A-Za-z_][A-Za-z0-9_]*=/.test(toks[i].v)) i += 1;
      while (i < toks.length && !toks[i].q && toks[i].v === "-C") i += 2;
      while (i < toks.length && !toks[i].q && /^--chdir(=.*)?$/.test(toks[i].v)) {
        i += toks[i].v.includes("=") ? 1 : 2;
      }
    } else if (wrapper === "nice") {
      if (i < toks.length && !toks[i].q && toks[i].v === "-n") i += 2;
      else if (i < toks.length && !toks[i].q && /^-n\d+$/.test(toks[i].v)) i += 1;
    } else if (wrapper === "timeout") {
      while (i < toks.length && !toks[i].q && toks[i].v.startsWith("-")) i += 1;
      if (i < toks.length) i += 1; // a duracao
    } else if (wrapper === "sudo") {
      while (
        i < toks.length && !toks[i].q &&
        (/^(-u|-g|--user|--group)$/.test(toks[i].v) || /^--(user|group)=/.test(toks[i].v))
      ) {
        i += /=/.test(toks[i].v) ? 1 : 2;
      }
    }
  }
  return i < toks.length ? i : null;
}

module.exports = {
  tokensComAspas,
  ehComando,
  WRAPPERS_QUE_REPASSAM,
  posicaoDeComando,
};
