"use strict";
/* Modulo comum entre scripts/ideias.cjs e scripts/divergencias.cjs — os dois
 * eram copia quase byte a byte da trava de arquivo e da rotina de leitura do
 * jsonl, e os dois carregavam os MESMOS dois defeitos (issue de 2026-08-23):
 *
 *   Defeito A — parseLinhas lancava no primeiro erro de JSON.parse, sem
 *   distinguir "ultima linha, possivelmente escrita em andamento" (tolerada)
 *   de "linha do meio, dado corrompido de verdade" (continua erro, agora com
 *   numero da linha, caminho do arquivo e o trecho ofensor).
 *
 *   Defeito B — a classe Trava so olhava a IDADE do lock (>120s = orfa) e
 *   nunca lia o PID que ela mesma grava ao entrar. Um dono legitimamente
 *   lento (>120s na secao critica) tinha o proprio lock roubado por outro
 *   processo, e o `sair()` apagava o arquivo por CAMINHO, sem conferir que a
 *   trava ali no disco ainda era a que este processo abriu — dois processos
 *   exclusivos ao mesmo tempo, em silencio.
 *
 * So a Trava e a leitura vivem aqui. `gravar()` (backup + escrita atomica +
 * conferencia byte a byte) fica em cada script: e onde as baterias de
 * mutacao (testa-ideias.sh bloco 3, testa-divergencias.sh bloco 4) mutam o
 * `.cjs` de fato executado, ancoradas numa string literal dentro de
 * `gravar()`. Mover isso para ca quebraria as duas ancoras sem necessidade —
 * o defeito que esta tarefa resolve nao esta ali.
 */

const fs = require("fs");

class Erro extends Error {}

// --------------------------------------------------------------------------
// sleep sincrono (para o poll da trava, sem bloquear em callback)
// --------------------------------------------------------------------------

function sleepSync(ms) {
  const sab = new SharedArrayBuffer(4);
  const ia = new Int32Array(sab);
  Atomics.wait(ia, 0, 0, ms);
}

// --------------------------------------------------------------------------
// prova de que o dono morreu (defeito B) — le o PID gravado no lock e
// pergunta ao SO se ele ainda existe. `process.kill(pid, 0)` nao manda sinal
// nenhum (o 0 e o caso especial documentado do Node): so testa existencia, e
// funciona em POSIX e Windows.
// --------------------------------------------------------------------------

function donoPid(conteudoTrava) {
  const m = /^(\d+)\s/.exec(String(conteudoTrava));
  return m ? Number(m[1]) : null;
}

function processoVivo(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    // ESRCH: processo nao existe. EPERM: existe, mas sem permissao de sinal —
    // ainda assim VIVO. Qualquer outro erro: trata como vivo, por seguranca
    // (nao quebrar um lock por causa de um erro que nao entendemos).
    return e.code !== "ESRCH";
  }
}

// --------------------------------------------------------------------------
// trava e leitura
// --------------------------------------------------------------------------

class Trava {
  // Trava de arquivo entre sessoes paralelas.
  constructor(caminho, esperaSeg = 10.0) {
    this.caminho = caminho;
    this.esperaSeg = esperaSeg;
    this.fd = null;
  }

  entrar() {
    const limite = Date.now() + this.esperaSeg * 1000;
    for (;;) {
      try {
        this.fd = fs.openSync(this.caminho, "wx");
        fs.writeSync(this.fd, `${process.pid} ${new Date().toISOString()}\n`);
        return this;
      } catch (e) {
        if (e.code !== "EEXIST") throw e;
        let idadeSeg, conteudo;
        try {
          idadeSeg = (Date.now() - fs.statSync(this.caminho).mtimeMs) / 1000;
          conteudo = fs.readFileSync(this.caminho, "utf8");
        } catch (e2) {
          // trava sumiu entre o EEXIST e a leitura — tenta de novo
          continue;
        }
        const pid = donoPid(conteudo);
        // Criterio principal: prova de que o DONO morreu, nao a idade do
        // arquivo — um dono legitimamente lento passa dos 120s sem estar
        // orfao (era exatamente esse o defeito). So cai no fallback de
        // idade quando NAO ha PID gravado (lock de formato antigo, ou
        // corrompido): ali nao ha como provar a morte, e sem o fallback um
        // lock assim nunca se recuperaria sozinho.
        const semPid = pid === null;
        const donoMorto = !semPid && !processoVivo(pid);
        const orfaPorIdadeSemPid = semPid && idadeSeg > 120;
        if (donoMorto || orfaPorIdadeSemPid) {
          const motivo = donoMorto
            ? `dono (pid ${pid}) nao esta mais rodando`
            : `sem PID gravado e ${idadeSeg.toFixed(0)}s de idade (formato antigo ou corrompido)`;
          process.stderr.write(`aviso: trava orfa em ${this.caminho} (${motivo}) — quebrando\n`);
          try {
            fs.unlinkSync(this.caminho);
          } catch (e3) {
            /* ja sumiu, segue */
          }
          continue;
        }
        if (Date.now() > limite) {
          throw new Erro(
            `outra sessao esta escrevendo (trava em ${this.caminho}, pid ${pid ?? "desconhecido"}, ` +
              `ha ${idadeSeg.toFixed(0)}s). Tente de novo em instantes.`
          );
        }
        sleepSync(200);
      }
    }
  }

  sair() {
    if (this.fd !== null) {
      fs.closeSync(this.fd);
      this.fd = null;
    }
    // Confere que a trava no disco ainda e a que ESTE processo abriu antes de
    // apagar por caminho (defeito B): sem isso, um `sair()` apaga o lock de
    // quem quer que esteja la agora, inclusive de outro processo que abriu
    // depois de um roubo indevido. Melhor deixar uma trava estranha no chao
    // (o proximo `entrar()` resolve pela prova de PID) do que apagar o lock
    // de quem nao somos nos.
    let conteudo;
    try {
      conteudo = fs.readFileSync(this.caminho, "utf8");
    } catch (e) {
      return; // ja sumiu — nada para conferir nem para apagar
    }
    if (donoPid(conteudo) !== process.pid) {
      process.stderr.write(
        `aviso: trava em ${this.caminho} nao e mais a minha (pid gravado: ${donoPid(conteudo)}, ` +
          `meu pid: ${process.pid}) — nao apago\n`
      );
      return;
    }
    try {
      fs.unlinkSync(this.caminho);
    } catch (e) {
      /* ja sumiu, tudo bem */
    }
  }
}

function comTrava(caminho, fn, esperaSeg) {
  const trava = new Trava(caminho, esperaSeg);
  trava.entrar();
  try {
    return fn();
  } finally {
    trava.sair();
  }
}

function lerVivo(caminho, opts = {}) {
  // Le o arquivo VIVO agora. Nunca reaproveitar leitura de antes da operacao.
  // `exigeExistir` (default true) decide o que fazer com arquivo ausente:
  // ideias.jsonl e semeado pelo `setup.cjs` (ausencia = erro), divergencias.
  // jsonl nao tem porta de instalacao propria — a primeira `abrir` e quem o
  // cria (ausencia = zero linhas).
  const exigeExistir = opts.exigeExistir !== false;
  if (!fs.existsSync(caminho)) {
    if (exigeExistir) throw new Erro(`nao achei ${caminho}`);
    return [];
  }
  const bruto = fs.readFileSync(caminho, "utf8");
  return bruto.split("\n").filter((l) => l.trim().length > 0);
}

function parseLinhas(linhas, caminho) {
  // Defeito A: a ULTIMA linha nao-vazia e tolerada quando invalida — e o
  // caso real de uma escrita concorrente pegando o arquivo no meio do
  // caminho (dado legado, script que ignore a trava, edicao a mao no
  // instante errado). Ela e ignorada em silencio, nunca lancada.
  //
  // Qualquer linha do MEIO continua sendo erro — so que agora com numero da
  // linha, caminho do arquivo e o trecho ofensor (truncado), porque o erro
  // de antes dizia "para sempre" sem dizer ONDE.
  const saida = [];
  const ultimoIdx = linhas.length - 1;
  linhas.forEach((l, idx) => {
    try {
      saida.push(JSON.parse(l));
    } catch (e) {
      if (idx === ultimoIdx) return; // ultima linha: tolerada, ignorada
      const trecho = l.length > 120 ? `${l.slice(0, 120)}…` : l;
      throw new Erro(
        `linha ${idx + 1} de ${caminho ?? "(caminho nao informado)"} nao e JSON valido: ` +
          `${e.message} — trecho: "${trecho}"`
      );
    }
  });
  return saida;
}

function indicePorId(linhas, alvoId, caminho) {
  const objs = parseLinhas(linhas, caminho);
  for (let i = 0; i < objs.length; i++) {
    if (objs[i] && objs[i].id === alvoId) return i;
  }
  throw new Erro(`id '${alvoId}' nao existe no arquivo`);
}

module.exports = {
  Erro,
  Trava,
  comTrava,
  lerVivo,
  parseLinhas,
  indicePorId,
  sleepSync,
  donoPid,
  processoVivo,
};
