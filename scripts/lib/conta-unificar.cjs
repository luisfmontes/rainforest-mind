'use strict';
/**
 * Migração da pasta pessoal para a pasta única (plano 2026-10-12-pasta-unica, tarefa 2;
 * design D1, D2, D3, D7). Quem orquestra (lê estado, chama schtasks e a CLI, decide o exit)
 * é scripts/conta.cjs; aqui ficam a decisão e a cópia.
 *
 *   planejar(entrada) -> plano   só lê. Nunca escreve nada.
 *   aplicar(plano, ops) -> {plugins, reagendado}   escreve, na ordem de D7.
 *   relatorio(plano, aplicado?) -> linhas de texto. Nunca imprime conteúdo de arquivo nem credencial.
 *
 * entrada = {
 *   trabalho, pessoal, aposentada        pastas (absolutas); aposentada = pessoal + '.aposentada'
 *   claudeJsonTrabalho                   ~/.claude.json (destino de mcpServers e projects)
 *   reservaArq, reservaExiste, reservaPessoalPronta   reserva-pessoal.json e o que se sabe dela
 *   processosVivos                       nomes de processo claude vivos (lista; vazia = nenhum)
 *   sessoesVivas                         boolean: há sessão viva no sessoes.json
 *   pastaForaDeCasa                      boolean: a pessoal está com login de outra conta
 *   scriptInstalado                      conta.cjs do clone instalado (destino do reagendamento)
 * }
 *
 * Nunca sobrescreve: arquivo de mesmo nome e conteúdo diferente vira <nome>.pessoal.<ext>.
 * Credencial nunca vai para o relatório nem para stdout: só entra em reserva-pessoal.json.
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { gravarAtomico: gravarCred } = require('./conta-mover.cjs');

// Só estas pastas da pessoal são copiadas (D2). cache/, sessions/, plugins/, daemon*, telemetry/ e
// o resto ficam de fora por construção: não estão na lista.
const DIRS_COPIA = ['projects', 'file-history', 'plans', 'todos', 'tasks'];
const HISTORICO = 'history.jsonl';
const LINK_MD = /\(([^()\s]+\.md)\)/;

const hashArq = (arq) => crypto.createHash('sha256').update(fs.readFileSync(arq)).digest('hex');

function renomeado(arq) {
  const { dir, name, ext } = path.parse(arq);
  return path.join(dir, `${name}.pessoal${ext}`);
}

function listarArquivos(dir, base) {
  if (!fs.existsSync(dir)) return [];
  const saida = [];
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, ent.name);
    if (ent.isDirectory()) saida.push(...listarArquivos(abs, base));
    else if (ent.isFile()) saida.push(path.relative(base, abs));
  }
  return saida.sort();
}

function lerJsonOpcional(arq, padrao) {
  if (!fs.existsSync(arq)) return padrao;
  // JSON inválido lança aqui, no planejamento: nada foi escrito ainda (fail-closed).
  return JSON.parse(fs.readFileSync(arq, 'utf8'));
}

// Um arquivo de origem contra o destino. 'igual': já está lá com o mesmo conteúdo, nada a fazer.
// 'conflito': mesmo nome e conteúdo diferente; vai para <nome>.pessoal.<ext> e o destino não é tocado.
// 'copiar': o destino não existe.
function decidirArquivo(origem, destino) {
  const conflito = fs.existsSync(destino) && !mesmoConteudo(origem, destino);
  if (fs.existsSync(destino) && !conflito) return { acao: 'igual', destino };
  if (conflito) {
    // Rodada anterior já gravou o <nome>.pessoal.<ext> com o conteúdo desta origem: já migrado, não é conflito.
    const alt = renomeado(destino);
    if (fs.existsSync(alt) && mesmoConteudo(origem, alt)) return { acao: 'igual', destino: alt };
    return { acao: 'conflito', destino: alt };
  }
  return { acao: 'copiar', destino };
}

function mesmoConteudo(a, b) {
  return hashArq(a) === hashArq(b);
}

function classeDe(rel) {
  // rel vem de path.relative: no Windows o separador é \, e a classe não pode ser o caminho inteiro.
  const partes = rel.split(/[\\/]/);
  if (partes.includes('memory')) return 'memoria';
  if (partes[0] === 'projects' && rel.endsWith('.jsonl')) return 'transcritos';
  return partes[0];
}

function mcpDivergentes(pessoal, destino) {
  const divergentes = [];
  for (const nome of Object.keys(pessoal)) {
    if (!Object.hasOwn(destino, nome)) continue;
    if (JSON.stringify(destino[nome]) !== JSON.stringify(pessoal[nome])) divergentes.push(nome);
  }
  return divergentes;
}

// Índice de memória: as linhas da pessoal cujo alvo NÃO existia na pasta de destino (snapshot
// feito antes de qualquer cópia). Linha sem alvo .md não entra.
function linhasDeIndice(textoPessoal, nomesNoDestino) {
  const vistas = new Set();
  const novas = [];
  for (const linha of textoPessoal.split('\n')) {
    const m = linha.match(LINK_MD);
    if (!m || nomesNoDestino.has(m[1]) || vistas.has(linha)) continue;
    vistas.add(linha);
    novas.push({ linha, alvo: m[1] });
  }
  return novas;
}

function planejar(e) {
  const recusas = [];
  if (e.processosVivos && e.processosVivos.length) {
    recusas.push({ motivo: 'processo_claude', detalhe: e.processosVivos.join(', ') });
  }
  if (e.sessoesVivas) recusas.push({ motivo: 'sessao_viva', detalhe: 'há sessão viva no sessoes.json' });
  if (e.pastaForaDeCasa) recusas.push({ motivo: 'pasta_fora_de_casa', detalhe: 'a pasta pessoal está com login de outra conta' });
  if (fs.existsSync(e.aposentada)) recusas.push({ motivo: 'aposentada_existe', detalhe: 'a pasta .claude-personal.aposentada já existe' });
  if (e.reservaExiste && !e.reservaPessoalPronta) {
    recusas.push({ motivo: 'reserva_ocupada', detalhe: 'reserva-pessoal.json existe sem credencial' });
  }
  // O vigia é reagendado apontando para o clone instalado: sem ele, o agendamento roda uma tarefa morta.
  if (!fs.existsSync(e.scriptInstalado)) {
    recusas.push({ motivo: 'clone_ausente', detalhe: 'o clone instalado (plugins/marketplaces) não existe; o vigia não teria para onde apontar' });
  }

  const copias = [];
  const indices = [];
  for (const dirNome of DIRS_COPIA) {
    for (const rel of listarArquivos(path.join(e.pessoal, dirNome), e.pessoal)) {
      const origem = path.join(e.pessoal, rel);
      const destino = path.join(e.trabalho, rel);
      if (path.basename(rel) === 'MEMORY.md' && path.basename(path.dirname(rel)) === 'memory') {
        indices.push({ rel, origem, destino, acao: fs.existsSync(destino) ? 'mesclar' : 'copiar' });
        continue;
      }
      const d = decidirArquivo(origem, destino);
      if (d.acao === 'conflito' && fs.existsSync(d.destino)) {
        recusas.push({ motivo: 'conflito_ocupado', detalhe: path.relative(e.trabalho, d.destino) });
      }
      copias.push({ classe: classeDe(rel), rel, origem, destino: d.destino, acao: d.acao });
    }
  }

  // Índice: o snapshot dos nomes do destino vem daqui, antes de qualquer cópia.
  for (const i of indices) {
    i.linhas = [];
    if (i.acao === 'mesclar') {
      const nomes = new Set(fs.readdirSync(path.dirname(i.destino)));
      i.linhas = linhasDeIndice(fs.readFileSync(i.origem, 'utf8'), nomes);
    }
  }

  // history.jsonl: linhas da pessoal que o destino não tem, sem repetir.
  const historicoOrigem = path.join(e.pessoal, HISTORICO);
  const historicoDestino = path.join(e.trabalho, HISTORICO);
  const jaTem = new Set(fs.existsSync(historicoDestino) ? fs.readFileSync(historicoDestino, 'utf8').split('\n') : []);
  const novasHistorico = [];
  if (fs.existsSync(historicoOrigem)) {
    for (const linha of fs.readFileSync(historicoOrigem, 'utf8').split('\n')) {
      if (!linha || jaTem.has(linha)) continue;
      jaTem.add(linha);
      novasHistorico.push(linha);
    }
  }

  // .claude.json: união de mcpServers e projects por nome/caminho, sem sobrescrever. Nome de MCP
  // igual com definição diferente é recusa (só o nome sai no relatório, nunca a definição).
  const claudePessoal = lerJsonOpcional(path.join(e.pessoal, '.claude.json'), {});
  const claudeDestino = lerJsonOpcional(e.claudeJsonTrabalho, {});
  const mcpP = claudePessoal.mcpServers || {};
  const mcpD = claudeDestino.mcpServers || {};
  const divergentes = mcpDivergentes(mcpP, mcpD);
  if (divergentes.length) recusas.push({ motivo: 'mcp_divergente', detalhe: divergentes.join(', ') });
  const mcpNovos = Object.keys(mcpP).filter((n) => !Object.hasOwn(mcpD, n));
  const projP = claudePessoal.projects || {};
  const projD = claudeDestino.projects || {};
  const projNovos = Object.keys(projP).filter((k) => !Object.hasOwn(projD, k));
  let claudeNovo = null;
  if (mcpNovos.length || projNovos.length) {
    claudeNovo = { ...claudeDestino };
    claudeNovo.mcpServers = { ...mcpD };
    for (const n of mcpNovos) claudeNovo.mcpServers[n] = mcpP[n];
    claudeNovo.projects = { ...projD };
    for (const k of projNovos) claudeNovo.projects[k] = projP[k];
  }

  // Plugins habilitados só na pessoal: instalados pela CLI, nunca copiando o cache (D2).
  const setP = lerJsonOpcional(path.join(e.pessoal, 'settings.json'), {}).enabledPlugins || {};
  const setD = lerJsonOpcional(path.join(e.trabalho, 'settings.json'), {}).enabledPlugins || {};
  const plugins = Object.keys(setP)
    .filter((chave) => setP[chave] === true && setD[chave] !== true)
    .map((chave) => ({ chave }));

  // Reserva: a credencial da pessoal vira reserva-pessoal.json só se ainda não há reserva pronta.
  const credPessoal = lerJsonOpcional(path.join(e.pessoal, '.credentials.json'), null);
  const temCred = Boolean(credPessoal && credPessoal.claudeAiOauth);
  let reserva;
  if (e.reservaPessoalPronta) reserva = { acao: 'mantida' };
  else if (temCred) reserva = { acao: 'gravar', claudeAiOauth: credPessoal.claudeAiOauth };
  else reserva = { acao: 'sem_credencial' };

  // Credencial que fica na pasta aposentada. O refresh token NUNCA pode estar em dois arquivos de uso:
  // se é o mesmo login da reserva (gravado agora ou de antes), a aposentada perde a claudeAiOauth e
  // as outras chaves ficam. Outro login (refresh token diferente) não está na reserva: fica como está.
  let tirarCredPessoal = null;
  let credencial = 'nenhuma';
  if (temCred) {
    const refreshPessoal = credPessoal.claudeAiOauth.refreshToken;
    const refreshReserva = reserva.acao === 'gravar'
      ? refreshPessoal
      : (lerJsonOpcional(e.reservaArq, {}).claudeAiOauth || {}).refreshToken;
    if (refreshPessoal && refreshReserva === refreshPessoal) {
      const restante = { ...credPessoal };
      delete restante.claudeAiOauth;
      tirarCredPessoal = { arq: path.join(e.pessoal, '.credentials.json'), restante };
      credencial = 'sai';
    } else {
      credencial = 'fica';
    }
  }

  return {
    trabalho: e.trabalho,
    pessoal: e.pessoal,
    aposentada: e.aposentada,
    claudeJsonTrabalho: e.claudeJsonTrabalho,
    reservaArq: e.reservaArq,
    recusas,
    copias,
    indices,
    historico: { destino: historicoDestino, novas: novasHistorico },
    claude: { destino: e.claudeJsonTrabalho, novo: claudeNovo, mcpNovos, projNovos },
    plugins,
    reserva,
    credencial,
    tirarCredPessoal,
  };
}

function gravarTexto(arq, texto) {
  fs.mkdirSync(path.dirname(arq), { recursive: true });
  const tmp = `${arq}.${process.pid}.${Date.now()}.tmp`;
  try {
    fs.writeFileSync(tmp, texto, { encoding: 'utf8', flag: 'wx' });
    fs.renameSync(tmp, arq);
  } catch (err) {
    fs.rmSync(tmp, { force: true });
    throw err;
  }
}

function acrescentarLinhas(arq, linhas) {
  const atual = fs.existsSync(arq) ? fs.readFileSync(arq, 'utf8') : '';
  const sep = atual === '' || atual.endsWith('\n') ? '' : '\n';
  gravarTexto(arq, atual + sep + linhas.join('\n') + '\n');
}

function copiarArq(origem, destino) {
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  // COPYFILE_EXCL: se algo surgiu no destino entre o plano e a cópia, falha em vez de sobrescrever.
  fs.copyFileSync(origem, destino, fs.constants.COPYFILE_EXCL);
}

// Ordem de D7: vigia desagendado primeiro; cópias; índices; histórico; .claude.json; plugins; reserva;
// rename da pessoal; vigia reagendado por último (apontando para o clone instalado).
// Cada etapa registra o próprio nome em `feito` quando termina. Se uma falha, o erro sai com `falhou`
// (a etapa que parou) e `feito` (o que já foi gravado): quem chama diz ao usuário onde a migração parou.
function aplicar(plano, ops) {
  if (plano.recusas.length) throw new Error('aplicar com recusas pendentes');
  const feito = [];
  const etapa = (nome, fn) => {
    try {
      const r = fn();
      feito.push(nome);
      return r;
    } catch (err) {
      err.falhou = nome;
      err.feito = [...feito];
      throw err;
    }
  };
  // Sem o vigia desagendado não se copia nada: o status do /Delete é conferido, não ignorado.
  etapa('desagendar o vigia', () => {
    const st = ops.desagendar();
    if (st) throw new Error(`schtasks não removeu o vigia (status ${st})`);
  });
  etapa('copiar arquivos', () => {
    for (const c of plano.copias) {
      if (c.acao === 'igual') continue;
      copiarArq(c.origem, c.destino);
    }
  });
  etapa('índices de memória', () => {
    for (const i of plano.indices) {
      if (i.acao === 'copiar') copiarArq(i.origem, i.destino);
      else if (i.linhas.length) acrescentarLinhas(i.destino, i.linhas.map((l) => l.linha));
    }
  });
  etapa('histórico', () => {
    if (plano.historico.novas.length) acrescentarLinhas(plano.historico.destino, plano.historico.novas);
  });
  etapa('.claude.json', () => {
    if (plano.claude.novo) gravarTexto(plano.claude.destino, JSON.stringify(plano.claude.novo, null, 2) + '\n');
  });
  // A instalação usa a chave completa <plugin>@<marketplace>: nome nu é ambíguo entre marketplaces.
  const plugins = etapa('plugins', () => plano.plugins.map((p) => ({ chave: p.chave, status: ops.instalarPlugin(p.chave) })));
  etapa('reserva', () => {
    if (plano.reserva.acao === 'gravar') {
      gravarCred(plano.reservaArq, JSON.stringify({ claudeAiOauth: plano.reserva.claudeAiOauth }, null, 2) + '\n');
    }
  });
  // Depois da reserva gravada (o login não some), e antes do rename: a aposentada não guarda o mesmo refresh token.
  etapa('credencial da pasta pessoal', () => {
    if (plano.tirarCredPessoal) gravarCred(plano.tirarCredPessoal.arq, JSON.stringify(plano.tirarCredPessoal.restante, null, 2) + '\n');
  });
  etapa('rename da pasta pessoal', () => ops.renomearPasta(plano.pessoal, plano.aposentada));
  const reagendado = etapa('vigia reagendado', () => ops.reagendar());
  return { plugins, reagendado };
}

function relatorio(plano, aplicado) {
  const linhas = [];
  linhas.push(aplicado ? 'unificar: aplicado' : 'unificar: relatório (sem --aplicar nada foi escrito)');
  const porClasse = {};
  const conflitos = [];
  let iguais = 0;
  for (const c of plano.copias) {
    if (c.acao === 'igual') { iguais += 1; continue; }
    porClasse[c.classe] = (porClasse[c.classe] || 0) + 1;
    if (c.acao === 'conflito') conflitos.push(c);
  }
  for (const i of plano.indices) porClasse.memoria = (porClasse.memoria || 0) + (i.acao === 'copiar' ? 1 : 0);
  for (const cl of Object.keys(porClasse).sort()) {
    if (porClasse[cl]) linhas.push(`copiar ${cl}: ${porClasse[cl]} arquivo(s)`);
  }
  linhas.push(`ja iguais no destino (sem copia): ${iguais}`);
  for (const c of conflitos) {
    linhas.push(`conflito: ${c.rel.split(path.sep).join('/')} -> ${path.relative(plano.trabalho, c.destino).split(path.sep).join('/')}`);
  }
  for (const i of plano.indices) {
    if (i.acao === 'mesclar' && i.linhas.length) {
      linhas.push(`indice ${i.rel.split(path.sep).join('/')}: +${i.linhas.length} linha(s)`);
      for (const l of i.linhas) linhas.push(`  + ${l.alvo}`);
    }
  }
  linhas.push(`historico: +${plano.historico.novas.length} linha(s)`);
  linhas.push(`mcp em .claude.json: +${plano.claude.mcpNovos.length} (${plano.claude.mcpNovos.join(', ') || 'nenhum'})`);
  linhas.push(`projetos em .claude.json: +${plano.claude.projNovos.length}`);
  for (const p of plano.plugins) {
    const st = aplicado && aplicado.plugins ? aplicado.plugins.find((x) => x.chave === p.chave) : null;
    linhas.push(st ? `plugin ${p.chave}: ${st.status === 0 ? 'instalado' : `falhou (status ${st.status})`}` : `plugin a instalar: ${p.chave}`);
  }
  const reservaTxt = {
    gravar: 'gravar reserva-pessoal (credencial da pasta pessoal)',
    mantida: 'mantida (já existe reserva pronta)',
    sem_credencial: 'sem credencial na pasta pessoal',
  }[plano.reserva.acao];
  linhas.push(`reserva pessoal: ${reservaTxt}`);
  const credTxt = {
    sai: 'sai da pasta aposentada (o mesmo login ficou na reserva)',
    fica: 'fica na pasta aposentada (outro login, que não está na reserva)',
    nenhuma: 'nenhuma na pasta pessoal',
  }[plano.credencial];
  linhas.push(`credencial da pasta pessoal: ${credTxt}`);
  linhas.push(aplicado ? `pasta pessoal aposentada: ${plano.aposentada}` : `pasta pessoal seria aposentada: ${plano.aposentada}`);
  return linhas;
}

// ---------------------------------------------------------------------------------------------
// Perfil do PowerShell (tarefa 3; design D5). Função pura: recebe o texto do perfil e devolve o
// texto novo. Quem lê e grava o arquivo é scripts/conta.cjs.
//
// As funções claude-pessoal e claude-trabalho saem; entra uma função claude só. Dentro de
// Update-ClaudePlugins, cada `& claude ` vira a aplicação: no PowerShell a função vence a aplicação,
// então sem isso `claude` -> Update-ClaudePlugins -> `& claude plugin ...` -> `claude` recursa.

// Trecho que chama a aplicação (não a função). Usado nas duas trocas abaixo.
const CHAMADA_APP = '& (Get-Command claude -CommandType Application | Select-Object -First 1) ';

// Bloco `function <cabeça> { ... }` por contagem de chaves. As funções do perfil não têm chave em string.
function acharBloco(texto, cabeca) {
  const ini = texto.indexOf(cabeca);
  if (ini < 0) return null;
  let prof = 0;
  for (let i = texto.indexOf('{', ini); i < texto.length; i += 1) {
    if (texto[i] === '{') prof += 1;
    else if (texto[i] === '}') {
      prof -= 1;
      if (prof === 0) return { ini, fim: i + 1 };
    }
  }
  return null;
}

function perfilUnico(texto) {
  const eol = texto.includes('\r\n') ? '\r\n' : '\n';
  const pessoal = acharBloco(texto, 'function claude-pessoal');
  const trabalho = acharBloco(texto, 'function claude-trabalho');
  const atualiza = acharBloco(texto, 'function Update-ClaudePlugins');
  if (!pessoal || !trabalho) {
    return { ok: false, motivo: 'o perfil não tem as funções claude-pessoal e claude-trabalho: nada foi alterado' };
  }
  if (!atualiza) return { ok: false, motivo: 'o perfil não tem Update-ClaudePlugins: nada foi alterado' };

  const claudeUnico = [
    'function claude {',
    '    Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue',
    '    Update-ClaudePlugins',
    `    ${CHAMADA_APP}--dangerously-skip-permissions @args`,
    '}',
  ].join(eol);
  const atualizaNovo = texto.slice(atualiza.ini, atualiza.fim).split('& claude ').join(CHAMADA_APP);
  let fimTrabalho = trabalho.fim;
  if (texto.startsWith(eol, fimTrabalho)) fimTrabalho += eol.length;

  // Trocas em ordem decrescente de posição, para os índices anteriores continuarem válidos.
  const trocas = [
    { ini: atualiza.ini, fim: atualiza.fim, novo: atualizaNovo },
    { ini: pessoal.ini, fim: pessoal.fim, novo: claudeUnico },
    { ini: trabalho.ini, fim: fimTrabalho, novo: '' },
  ].sort((a, b) => b.ini - a.ini);
  let saida = texto;
  for (const t of trocas) saida = saida.slice(0, t.ini) + t.novo + saida.slice(t.fim);
  return { ok: true, texto: saida };
}

// Diff por conjunto de linhas (não é unificado): o que sai (`- `) e o que entra (`+ `).
function diffLinhas(antes, depois) {
  const a = antes.split(/\r?\n/);
  const b = depois.split(/\r?\n/);
  const emA = new Set(a);
  const emB = new Set(b);
  return [
    ...a.filter((l) => !emB.has(l)).map((l) => `- ${l}`),
    ...b.filter((l) => !emA.has(l)).map((l) => `+ ${l}`),
  ];
}

module.exports = {
  planejar, aplicar, relatorio, decidirArquivo, mesmoConteudo, DIRS_COPIA, perfilUnico, diffLinhas, gravarTexto,
};
