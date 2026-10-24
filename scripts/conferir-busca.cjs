#!/usr/bin/env node
// @categoria: sensor
/**
 * conferir-busca — tarefa que cria código novo declara a busca antes de construir (D7)
 *
 * Uso:
 *   node scripts/conferir-busca.cjs plano --slug <s> [--plano <arquivo>]
 *
 * Regra: tarefa `implementar` (ou sem tipo) cujo `arquivos:` declara caminho
 * concreto de código que não existe no commit HEAD precisa do bloco `busca:`
 * (uma linha por canal, e o canal `repo`) e de `desfecho:`. Teste e `.md` não
 * contam; glob é ignorado.
 *
 * Exit: 0 ok, 2 recusa, 1 erro de uso, 69 nao-verificavel (sem git)
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoDoc } = require(path.join(__dirname, '..', 'hooks', 'lib', 'pastas-docs.cjs'));
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

const SCRIPT_DIR = path.dirname(__filename);
const { extrairTarefas, lerMarkdown } = require(path.join(SCRIPT_DIR, 'conferir-fluxo.cjs'));

const TIPOS_NAO_COBRADOS = ['docs', 'pesquisar', 'pesquisa', 'configurar', 'teste'];
const DESFECHOS = ['adotar', 'estender', 'compor', 'enxertar', 'construir'];
const FORMATO_LINHA = '- <canal> | <consulta> | <resultado>  ou  - <canal> | pulado: <motivo>';

// ================================================================ Utilitários

function arg(nome, obrigatorio = true) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1 || i + 1 >= process.argv.length) {
    if (obrigatorio) {
      console.error(`erro: falta --${nome}`);
      process.exit(1);
    }
    return null;
  }
  return process.argv[i + 1];
}

function git(cwd, args) {
  return spawnSync(caminhoExecutavel('git'), args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

/** Raiz do repo que contém o plano, ou null. */
function raizDoRepo(dirPlano) {
  const r = git(dirPlano, ['rev-parse', '--show-toplevel']);
  if (r.error || r.status !== 0) return null;
  return r.stdout.trim();
}

/** `arquivos:` com glob não entra: não há um caminho concreto para checar. */
function ehGlob(caminho) {
  return /[*?[{]/.test(caminho);
}

/** Teste não exige busca: a bateria que a própria tarefa cria não é código de produto. */
function ehTeste(caminho) {
  const base = path.posix.basename(caminho);
  return /^testa-/.test(base)
    || /\.test\./.test(base)
    || /_test\./.test(base)
    || /\.spec\./.test(base)
    || /(^|\/)test\//.test(caminho)
    || /(^|\/)tests\//.test(caminho);
}

/** Caminho com `\` (Windows) vira `/` antes de qualquer checagem. A caixa não muda: o git é sensível. */
function normalizarCaminho(caminho) {
  return caminho.replace(/\\/g, '/');
}

/** Tarefa que o checador cobra: tipo vazio ou `implementar`, fora da lista de tipos isentos. */
function tarefaCobrada(tarefa) {
  if (TIPOS_NAO_COBRADOS.includes(tarefa.tipo)) return false;
  return tarefa.tipo === '' || tarefa.tipo === 'implementar';
}

/** Caminhos concretos de código da tarefa (sem glob, teste nem `.md`), já normalizados. */
function candidatosDe(tarefa) {
  return tarefa.arquivos
    .map(normalizarCaminho)
    .filter((c) => !ehGlob(c) && !ehTeste(c) && !c.endsWith('.md'));
}

function existeNoHead(repo, caminho) {
  const r = git(repo, ['cat-file', '-e', `HEAD:${caminho}`]);
  return r.status === 0;
}

// ================================================================ Linhas do bloco

/**
 * Divide a linha em campos pelo `|` que fica fora de aspas duplas. Um `|` entre
 * aspas é parte da consulta (`rg "a|b"`), não separa campo.
 */
function dividirCampos(linha) {
  const campos = [];
  let atual = '';
  let dentro = false;
  for (const ch of linha) {
    if (ch === '"') dentro = !dentro;
    if (ch === '|' && !dentro) {
      campos.push(atual.trim());
      atual = '';
    } else {
      atual += ch;
    }
  }
  campos.push(atual.trim());
  return campos;
}

/**
 * Valida uma linha `- <canal> | ...` do bloco `busca:`. Devolve o canal, se o
 * canal é `pulado:` (`pulado`) e o problema, se houver.
 *
 * Regra dos campos, separados por `|` fora de aspas duplas:
 *   - campo 2 `pulado: <motivo>` marca o canal como não aplicável; é o último
 *     campo da linha e o motivo não pode ser vazio;
 *   - senão, o último campo é o resultado e os campos do meio são a consulta.
 *     Só sobrou a consulta (sem resultado) ou não há consulta: é problema.
 * Consulta com `|` precisa de aspas (`rg "a|b"`); sem aspas, o `|` separa campo.
 * `pulado:` no canal `repo` não é decidido aqui: quem chama recusa.
 */
function lerLinhaBusca(linha) {
  const campos = dividirCampos(linha);
  const canal = (campos[0] || '').toLowerCase();
  if (campos.length < 2) {
    return { canal, pulado: false, problema: `linha sem resultado nem \`pulado:\`: "${linha}"` };
  }
  if (/^pulado:/i.test(campos[1])) {
    if (campos.length > 2) {
      return { canal, pulado: false, problema: `\`pulado:\` leva um campo só, depois do canal: "${linha}"` };
    }
    const motivo = campos[1].replace(/^pulado:/i, '').trim();
    if (!motivo) return { canal, pulado: true, problema: `\`pulado:\` sem motivo: "${linha}"` };
    return { canal, pulado: true, problema: null };
  }
  if (campos.length < 3) {
    return { canal, pulado: false, problema: `linha sem resultado nem \`pulado:\`: "${linha}"` };
  }
  const consulta = campos.slice(1, -1).join(' | ');
  if (!consulta) return { canal, pulado: false, problema: `linha sem consulta: "${linha}"` };
  if (!campos[campos.length - 1]) return { canal, pulado: false, problema: `linha sem resultado: "${linha}"` };
  return { canal, pulado: false, problema: null };
}

// ================================================================ Comando plano

function cmdPlano() {
  const slug = arg('slug');
  const arquivo = arg('plano', false) || path.join(RAIZ, caminhoDoc('planos', slug, { raiz: RAIZ }));

  const conteudo = lerMarkdown(arquivo);
  if (!conteudo) {
    console.error(`RECUSADO: plano não existe: ${arquivo}`);
    console.error('uso: plano --slug <s> [--plano <arquivo>]');
    process.exit(2);
  }

  // Git só é exigido quando alguma tarefa cobrada tem candidato a caminho novo.
  const cobradas = extrairTarefas(conteudo).filter(tarefaCobrada);
  if (!cobradas.some((t) => candidatosDe(t).length > 0)) {
    console.log('ok: nenhuma tarefa cria caminho novo de código sem busca:');
    return;
  }

  const repo = raizDoRepo(path.dirname(path.resolve(arquivo)));
  if (!repo) {
    console.error('nao-verificavel: o plano não está num repositório git');
    process.exit(69);
  }

  const recusas = [];
  let exigidas = 0;

  for (const tarefa of cobradas) {
    const { numero, nome, busca } = tarefa;
    const candidatos = candidatosDe(tarefa);
    const caminhosNovos = candidatos.filter((c) => !existeNoHead(repo, c));

    // Gatilho D7: caminho novo de código na tarefa. Não basta tocar arquivo existente.
    const exige = caminhosNovos.length > 0;
    if (!exige) continue;
    exigidas++;

    const quem = `tarefa ${numero}. ${nome} cria \`${caminhosNovos[0]}\``
      + (caminhosNovos.length > 1 ? ` (e mais ${caminhosNovos.length - 1})` : '');

    if (!busca.presente) {
      recusas.push(`${quem} sem bloco \`busca:\`. Falta: \`busca:\` seguido de ${FORMATO_LINHA}, com canal \`repo\`, e \`desfecho: ${DESFECHOS.join('|')}\`.`);
      continue;
    }

    let temRepo = false;
    let repoPulado = false;
    for (const linha of busca.linhas) {
      const { canal, pulado, problema } = lerLinhaBusca(linha);
      if (problema) {
        recusas.push(`${quem}; bloco \`busca:\` com linha inválida: ${problema}. Formato: ${FORMATO_LINHA}.`);
      } else if (canal === 'repo' && pulado) {
        repoPulado = true;
        recusas.push(`${quem}; o canal \`repo\` não aceita \`pulado:\`. Falta uma linha \`- repo | <consulta> | <resultado>\`, mesmo que o resultado seja "nada encontrado".`);
      } else if (canal === 'repo') {
        temRepo = true;
      }
    }
    if (busca.linhas.length === 0) {
      recusas.push(`${quem}; \`busca:\` sem nenhuma linha. Falta: ${FORMATO_LINHA}.`);
    } else if (!temRepo && !repoPulado) {
      recusas.push(`${quem}; \`busca:\` sem o canal \`repo\`. Falta uma linha \`- repo | <consulta> | <resultado>\`.`);
    }

    if (busca.desfecho === null || busca.desfecho === '') {
      recusas.push(`${quem}; falta \`desfecho:\`. Falta uma linha \`desfecho: ${DESFECHOS.join('|')}\`.`);
    } else if (!DESFECHOS.includes(busca.desfecho)) {
      recusas.push(`${quem}; \`desfecho: ${busca.desfecho}\` fora de ${DESFECHOS.join('|')}.`);
    }
  }

  if (recusas.length > 0) {
    console.error('RECUSADO:');
    for (const recusa of recusas) {
      console.error(`  ${recusa}`);
    }
    process.exit(2);
  }

  if (exigidas > 0) {
    console.log(`ok: ${exigidas} tarefa(s) com caminho novo de código, todas com busca: e desfecho:`);
  } else {
    console.log('ok: nenhuma tarefa cria caminho novo de código sem busca:');
  }
}

// ================================================================ Main

function main() {
  const subcmd = process.argv[2];
  if (subcmd === 'plano') {
    cmdPlano();
  } else {
    console.error('uso: plano --slug <s> [--plano <arquivo>]');
    process.exit(1);
  }
}

if (require.main === module) main();
module.exports = { cmdPlano, lerLinhaBusca, ehTeste, ehGlob };
