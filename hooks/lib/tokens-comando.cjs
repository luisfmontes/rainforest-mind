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

// Flags que cada wrapper reconhece e que CONSOMEM VALOR: o proprio token
// mais o seguinte — ou so o proprio, se o valor vier colado com `=`
// (`--chdir=X`). Wrapper (ou flag) NAO listado aqui e tratado como SEM
// valor: so o proprio token e pulado — a mesma regra vale para toda flag
// DESCONHECIDA que comece com `-` (postura conservadora: e melhor pular de
// menos um argumento estranho do que engolir o comando de verdade).
//
// P1 (rodada 8, lote 3, 2026-09-04): a versao anterior so sabia `env -C`/
// `--chdir` e `sudo -u/-g/--user/--group` — qualquer outra flag destes
// wrappers (`env -u FOO`, `sudo -E`, `sudo -i`, ...) parava a busca ALI,
// tratando a propria flag como se fosse o comando efetivo (o proximo `while`
// da tabela nunca era alcancado, e o `while` externo tambem parava, porque a
// flag nao e nome de wrapper). `env -u OneDrive git add -A` e
// `env -u FOO codex exec --yolo` atravessavam os gates assim.
const FLAGS_COM_VALOR = {
  env: new Set(["-u", "--unset", "-C", "--chdir"]),
  sudo: new Set(["-u", "-g", "-p", "-C", "--user", "--group"]),
  nice: new Set(["-n"]),
  xargs: new Set(["-n", "-I", "-d", "-P"]),
};

/** `NOME=valor` isolado — atribuicao de variavel antes do comando de verdade. */
function ehAtribuicao(tok) {
  return /^[A-Za-z_][A-Za-z0-9_]*=/.test(tok);
}

/** Nome "base" de uma flag, sem o `=valor` colado (`--chdir=X` -> `--chdir`). */
function baseDaFlag(tok) {
  const eq = tok.indexOf("=");
  return eq === -1 ? tok : tok.slice(0, eq);
}

/**
 * Pula, a partir do indice `i`, toda flag reconhecida (e desconhecida —
 * tratada como sem valor) de `wrapper`. Devolve o novo indice, na primeira
 * posicao que ja nao e flag.
 *
 * `nice -n5` (colado, sem `=` nem espaco) e o unico caso de valor grudado
 * sem separador — tratado a parte, antes de consultar a tabela.
 */
function pularFlagsDoWrapper(toks, i, wrapper) {
  const comValor = FLAGS_COM_VALOR[wrapper];
  while (i < toks.length && !toks[i].q && toks[i].v.startsWith("-")) {
    const tok = toks[i].v;
    if (wrapper === "nice" && /^-n\d+$/.test(tok)) {
      i += 1;
      continue;
    }
    const base = baseDaFlag(tok);
    if (comValor && comValor.has(base)) {
      i += tok.includes("=") ? 1 : 2;
    } else {
      i += 1; // sem valor (conhecida ou nao) — so o proprio token
    }
  }
  return i;
}

/**
 * Acha o INDICE do token que e a posicao de comando de um segmento
 * tokenizado, pulando atribuicoes `NOME=valor` soltas e os wrappers
 * conhecidos (e os argumentos deles que consomem valor, via
 * `pularFlagsDoWrapper`/`FLAGS_COM_VALOR`). `null` se o segmento acaba
 * dentro dos proprios prefixos (`env` sozinho, sem comando depois).
 *
 * `timeout` continua a parte: qualquer flag (`-s`, `--signal=...`) e pulada
 * de forma generica, e o primeiro token que sobra e sempre a duracao
 * posicional (nunca a flag em si).
 *
 * `exec`, `nohup`, `command`, `time` nao tem flags proprias na tabela: caem
 * no mesmo `pularFlagsDoWrapper`, que trata qualquer `-flag` deles como sem
 * valor (cobre `time -p`, `command -p`).
 */
function posicaoDeComando(toks) {
  let i = 0;
  for (;;) {
    if (i < toks.length && !toks[i].q && ehAtribuicao(toks[i].v)) {
      i += 1;
      continue;
    }
    if (i < toks.length && !toks[i].q && WRAPPERS_QUE_REPASSAM.has(toks[i].v)) {
      const wrapper = toks[i].v;
      i += 1;
      if (wrapper === "timeout") {
        while (i < toks.length && !toks[i].q && toks[i].v.startsWith("-")) i += 1;
        if (i < toks.length) i += 1; // a duracao
      } else {
        i = pularFlagsDoWrapper(toks, i, wrapper);
      }
      continue;
    }
    break;
  }
  return i < toks.length ? i : null;
}

module.exports = {
  tokensComAspas,
  ehComando,
  WRAPPERS_QUE_REPASSAM,
  posicaoDeComando,
};
