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
 *   progressoArq                         unificar-progresso.jsonl na pasta de dados da conta (uma linha por cópia; lido na retomada, apagado ao fim)
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

// Progresso da cópia (rodada 4, achado 1): caminhos copiados com o MESMO nome por uma rodada que não chegou ao
// fim. Só a cópia com o mesmo nome entra; alvo que virou .pessoal.<ext> nunca entra. Sem ele, a retomada não
// distingue "copiado na rodada anterior" de "já existia no destino".
// Formato (rodada 6, achado 3): uma string JSON por linha, acrescentada por appendFileSync antes de cada cópia.
// Gravar a lista inteira a cada cópia custava O(n²) (4000 arquivos: 22 s). Linha truncada (morte no meio da
// escrita) não parseia e é ignorada: o caminho dela não entra, e a retomada copia de novo.
function lerProgresso(arq) {
  if (!arq || !fs.existsSync(arq)) return [];
  const saida = [];
  for (const linha of fs.readFileSync(arq, 'utf8').split('\n')) {
    if (!linha) continue;
    let rel;
    try {
      rel = JSON.parse(linha);
    } catch {
      continue;
    }
    if (typeof rel === 'string') saida.push(path.normalize(rel));
  }
  return saida;
}

function gravarProgresso(plano, rel) {
  if (!plano.progressoArq) return;
  fs.mkdirSync(path.dirname(plano.progressoArq), { recursive: true });
  fs.appendFileSync(plano.progressoArq, JSON.stringify(rel.split(path.sep).join('/')) + '\n');
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

// Índice de memória: a linha da pessoal entra se (a) o texto dela ainda não está no MEMORY.md de destino
// e (b) o alvo .md foi copiado com o mesmo nome — nesta rodada ou numa anterior (copiados: ver planejar).
// Alvo que ficou em conflito, ou que não existe na pessoal, não entra. Como o critério
// lê o destino, uma rodada repetida não duplica a linha, e a linha de uma rodada interrompida não se perde.
function linhasDeIndice(textoPessoal, textoDestino, dirRel, copiados) {
  const semCR = (l) => l.replace(/\r$/, '');
  const jaNoDestino = new Set(textoDestino.split('\n').map(semCR));
  const vistas = new Set();
  const novas = [];
  for (const linha of textoPessoal.split('\n')) {
    const m = linha.match(LINK_MD);
    if (!m || jaNoDestino.has(semCR(linha)) || vistas.has(linha)) continue;
    if (!copiados.has(path.join(dirRel, m[1]))) continue;
    vistas.add(linha);
    novas.push({ linha, alvo: m[1] });
  }
  return novas;
}

function planejar(e) {
  const recusas = [];
  if (e.processosVivos && e.processosVivos.length) {
    recusas.push({ motivo: 'processo_claude', detalhe: `feche o Claude e rode unificar num terminal sem Claude aberto (vivos: ${e.processosVivos.join(', ')})` });
  }
  if (e.sessoesVivas) recusas.push({ motivo: 'sessao_viva', detalhe: 'há sessão viva no sessoes.json' });
  // Qualquer pasta ativa fora de casa recusa (o chamador passa o resultado de todas): a volta do mover
  // encontraria a saída ocupada e a pasta única ficaria presa na conta pessoal.
  if (e.pastaForaDeCasa) recusas.push({ motivo: 'pasta_fora_de_casa', detalhe: 'uma pasta ativa está com login de outra conta: volte a pasta antes de unificar' });
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
      copias.push({ classe: classeDe(rel), rel, origem, destino: d.destino, acao: d.acao, mesmoNome: d.destino === destino });
    }
  }

  // Índice: lê o destino agora, antes de qualquer cópia. Conta como migrado o que esta rodada copiou com o mesmo
  // nome, e o que uma rodada anterior copiou (progresso) e já está igual. Alvo que já era igual sem progresso
  // (a.md idêntico desde o início) não entra: o destino já tinha o alvo. Alvo em conflito nunca entra.
  const progressoAntes = lerProgresso(e.progressoArq);
  const copiadosAntes = new Set(progressoAntes);
  const copiados = new Set(copias
    .filter((c) => c.acao === 'copiar' || (c.acao === 'igual' && c.mesmoNome && copiadosAntes.has(c.rel)))
    .map((c) => c.rel));
  for (const i of indices) {
    i.linhas = [];
    if (i.acao === 'mesclar') {
      i.linhas = linhasDeIndice(fs.readFileSync(i.origem, 'utf8'), fs.readFileSync(i.destino, 'utf8'), path.dirname(i.rel), copiados);
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
  // Mesmo caminho nas duas pastas: o destino fica como está, e o relatório lista o caminho (não mesclado).
  const projRepetidos = Object.keys(projP).filter((k) => Object.hasOwn(projD, k));
  // Só as entradas a acrescentar ficam no plano. O arquivo inteiro NÃO é montado aqui: a etapa .claude.json
  // relê o destino na hora de gravar (rodada 6, achado 2), para não apagar o que uma sessão gravou depois.
  const mcpAdd = Object.fromEntries(mcpNovos.map((n) => [n, mcpP[n]]));
  const projAdd = Object.fromEntries(projNovos.map((k) => [k, projP[k]]));

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
    progressoArq: e.progressoArq || null,
    progressoAntes,
    claudeJsonTrabalho: e.claudeJsonTrabalho,
    reservaArq: e.reservaArq,
    recusas,
    copias,
    indices,
    historico: { destino: historicoDestino, novas: novasHistorico },
    claude: { destino: e.claudeJsonTrabalho, mcpAdd, projAdd, mcpNovos, projNovos, projRepetidos },
    plugins,
    reserva,
    credencial,
    tirarCredPessoal,
  };
}

// Grava texto (UTF-8) ou bytes (Buffer), por arquivo temporário e renomeação.
function gravarTexto(arq, dados) {
  fs.mkdirSync(path.dirname(arq), { recursive: true });
  const tmp = `${arq}.${process.pid}.${Date.now()}.tmp`;
  try {
    fs.writeFileSync(tmp, dados, { flag: 'wx' });
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
  // Vigia que não estava agendado (plano.vigiaAgendado === false, descoberto por /Query antes da escrita):
  // nada a desagendar, e no fim nada a reagendar.
  etapa('desagendar o vigia', () => {
    if (plano.vigiaAgendado === false) return;
    const st = ops.desagendar();
    if (st) throw new Error(`schtasks não removeu o vigia (status ${st})`);
  });
  // Conta pessoal registrada (rodada 6, achado 1): depois do vigia desagendado (se o /Delete falha, nada é escrito)
  // e antes da cópia: a pasta pessoal sai no rename, e o modo uma pasta não tem outra forma de registrá-la.
  etapa('conta pessoal registrada', () => {
    if (plano.registroPessoal) ops.registrarPessoal(plano.registroPessoal);
  });
  // O progresso é gravado ANTES de cada cópia (rodada 5, achado 4): um processo morto no meio do laço, sem finally,
  // deixa no progresso o que já começou a copiar com o mesmo nome. Se o alvo não chegou ao disco, a retomada copia de novo.
  etapa('copiar arquivos', () => {
    for (const c of plano.copias) {
      if (c.acao === 'igual') continue;
      if (c.acao === 'copiar') gravarProgresso(plano, c.rel);
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
  // Relido AGORA (rodada 6, achado 2): uma sessão pode ter gravado o destino depois do planejar (chave nova,
  // numStartups). Só entra o que é da pessoal e ainda não existe no destino; o resto do arquivo atual fica como está.
  etapa('.claude.json', () => {
    const { mcpAdd, projAdd, destino } = plano.claude;
    if (!Object.keys(mcpAdd).length && !Object.keys(projAdd).length) return;
    const atual = lerJsonOpcional(destino, {});
    const mcpServers = { ...(atual.mcpServers || {}) };
    const projects = { ...(atual.projects || {}) };
    for (const [n, def] of Object.entries(mcpAdd)) if (!Object.hasOwn(mcpServers, n)) mcpServers[n] = def;
    for (const [k, def] of Object.entries(projAdd)) if (!Object.hasOwn(projects, k)) projects[k] = def;
    gravarTexto(destino, JSON.stringify({ ...atual, mcpServers, projects }, null, 2) + '\n');
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
  // Cópia concluída e pasta aposentada: a retomada não precisa mais do progresso. Apagado só aqui.
  if (plano.progressoArq) fs.rmSync(plano.progressoArq, { force: true });
  // plano.reagendar: o vigia estava agendado, ou a marca de uma rodada anterior diz que o reagendamento falta.
  const reagendado = etapa('vigia reagendado', () => (plano.reagendar ? ops.reagendar() : null));
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
  const repetidos = plano.claude.projRepetidos;
  linhas.push(`projetos em .claude.json: +${plano.claude.projNovos.length} (já existiam nas duas pastas, não mesclados: ${repetidos.join(', ') || 'nenhum'})`);
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
  if (aplicado && plano.vigiaAgendado === false && !plano.reagendar) linhas.push('vigia não estava agendado: nada a desagendar nem reagendar');
  if (aplicado && plano.vigiaAgendado === false && plano.reagendar) linhas.push('vigia desagendado por uma rodada anterior: reagendado agora');
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

// Flags da linha `& claude ...` do claude-trabalho que sai (sem o @args). O claude novo recebe ESSAS flags,
// copiadas do perfil de origem; nada é escrito aqui. Sem linha de chamada ou sem flags, devolve ''.
function flagsDoTrabalho(blocoTrabalho) {
  const linha = blocoTrabalho.split(/\r?\n/).find((l) => /&\s+claude(\s|$)/.test(l));
  if (!linha) return '';
  const depois = linha.slice(linha.search(/&\s+claude/)).replace(/^&\s+claude/, '');
  return depois.replace(/@args/, '').trim();
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

  const flags = flagsDoTrabalho(texto.slice(trabalho.ini, trabalho.fim));
  const chamada = flags ? `${CHAMADA_APP}${flags} @args` : `${CHAMADA_APP}@args`;
  const claudeUnico = [
    'function claude {',
    '    Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue',
    '    Update-ClaudePlugins',
    `    ${chamada}`,
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

// Codificação do perfil do PowerShell: BOM UTF-8, UTF-16 LE com BOM, ou sem BOM = CP-1252 (o PowerShell 5.1
// lê assim). O texto volta aos mesmos bytes, exceto no que a troca mexe: CP-1252 é decodificado byte a byte.
const CP1252 = new TextDecoder('windows-1252');
const BYTE_DE_CP1252 = new Map();
for (let b = 0; b < 256; b += 1) BYTE_DE_CP1252.set(CP1252.decode(Uint8Array.of(b)), b);

function lerPerfil(arq) {
  const b = fs.readFileSync(arq);
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) return { texto: b.subarray(3).toString('utf8'), codificacao: 'utf8bom' };
  if (b[0] === 0xff && b[1] === 0xfe) return { texto: b.subarray(2).toString('utf16le'), codificacao: 'utf16' };
  return { texto: CP1252.decode(b), codificacao: 'cp1252' };
}

// Recusa, antes de gravar, o caractere que o CP-1252 não tem (não troca em silêncio por "?").
function codificarPerfil(texto, codificacao) {
  if (codificacao === 'utf8bom') return Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(texto, 'utf8')]);
  if (codificacao === 'utf16') return Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(texto, 'utf16le')]);
  const bytes = [];
  for (const ch of texto) {
    const byte = BYTE_DE_CP1252.get(ch);
    if (byte === undefined) throw new Error(`caractere fora do CP-1252 (U+${ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0')}): perfil não gravado`);
    bytes.push(byte);
  }
  return Buffer.from(bytes);
}

function gravarPerfil(arq, texto, codificacao) {
  gravarTexto(arq, codificarPerfil(texto, codificacao));
}

module.exports = {
  planejar, aplicar, relatorio, decidirArquivo, mesmoConteudo, DIRS_COPIA, perfilUnico, diffLinhas, gravarTexto,
  lerPerfil, gravarPerfil, codificarPerfil, flagsDoTrabalho,
};
