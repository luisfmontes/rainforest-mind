// Logica pura do painel de PR (/pr): o resumo do PR, os eventos entre duas leituras, a
// virada que acorda o modelo e a nota que ele recebe. ES module sem Node e sem texto de
// template: o instante entra por argumento (em ms), nunca por leitura de relogio.

export const POLL_MS = 60000;
export const QUIETO_MS = 180000;

const FALHAS = ['FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED'];

// Motivo de merge a partir de mergeStateStatus do gh; o que nao estiver aqui vai em minusculas.
const MOTIVOS = {
  CLEAN: 'mergeável',
  DIRTY: 'conflito',
  BLOCKED: 'bloqueado',
  BEHIND: 'desatualizado',
  UNSTABLE: 'checks não passaram',
  DRAFT: 'draft',
  UNKNOWN: 'sem dado de merge',
};

function motivoDe(pr) {
  const m = String(pr.mergeStateStatus || '');
  // Fora da tabela, so letras e _: o motivo entra na nota que o modelo le.
  return MOTIVOS[m] ?? m.toLowerCase().replace(/[^a-z_]/g, '');
}

function resumirChecks(cs) {
  if (!cs.length) return 'sem checks';
  const fim = (c) => String(c.conclusion || c.state || '').toUpperCase();
  const rodando = cs.filter((c) => (c.status && c.status !== 'COMPLETED') || c.state === 'PENDING').length;
  const falhas = cs.filter((c) => FALHAS.includes(fim(c))).length;
  if (falhas) return 'checks: ' + falhas + ' falharam de ' + cs.length;
  if (rodando) return 'checks: ' + rodando + ' rodando de ' + cs.length;
  return 'checks ok (' + cs.length + ')';
}

function iconeChecks(t) {
  if (t.startsWith('checks ok')) return '✓';
  if (t.includes('falharam')) return '×';
  if (t.includes('rodando')) return '◐';
  return '·';
}

function iconeMotivo(m) {
  if (m === 'conflito' || m === 'bloqueado') return '×';
  if (m === 'mergeável') return '✓';
  return '·';
}

// pr: saida de `gh pr view --json ...`; threads: `reviewThreads` do GraphQL ({ totalCount, nodes }).
export function resumir(pr, threads) {
  const nos = threads && Array.isArray(threads.nodes) ? threads.nodes : [];
  const cs = Array.isArray(pr.statusCheckRollup) ? pr.statusCheckRollup : [];
  return {
    numero: pr.number,
    titulo: pr.title,
    url: pr.url,
    estado: pr.isDraft && pr.state === 'OPEN' ? 'DRAFT' : pr.state,
    branch: pr.headRefName,
    base: pr.baseRefName,
    autor: pr.author && pr.author.login ? pr.author.login : '',
    head: String(pr.headRefOid || '').slice(0, 7),
    checks: resumirChecks(cs),
    mergavel: pr.state === 'OPEN' && pr.mergeStateStatus === 'CLEAN',
    motivo: motivoDe(pr),
    review: String(pr.reviewDecision || '').toLowerCase().split('_').join(' '),
    threadsAbertas: nos.filter((t) => !t.isResolved).length,
    threadsTotal: threads && typeof threads.totalCount === 'number' ? threads.totalCount : nos.length,
    comentarios: Array.isArray(pr.comments) ? pr.comments.length : 0,
  };
}

// Eventos entre duas leituras do resumo. O instante (agoraMs) e recebido por contrato, mas
// os textos nao levam hora: quem pinta a hora na tela e a superficie, nao esta funcao.
export function eventos(velho, novo, agoraMs) {
  void agoraMs;
  const lista = [];
  if (!velho) {
    lista.push({ icone: '·', texto: 'acompanhando a partir de ' + novo.head });
    lista.push({ icone: iconeChecks(novo.checks), texto: novo.checks });
    return lista;
  }
  const pushNovo = velho.head !== novo.head;
  if (pushNovo) lista.push({ icone: '↑', texto: 'push ' + novo.head });
  // Logo depois de um push a CI ainda nao registrou os checks: "sem checks" ali e ruido.
  const ruidoDePush = pushNovo && novo.checks === 'sem checks';
  if (velho.checks !== novo.checks && !ruidoDePush) {
    lista.push({ icone: iconeChecks(novo.checks), texto: velho.checks + ' → ' + novo.checks });
  }
  if (velho.motivo !== novo.motivo) {
    lista.push({ icone: iconeMotivo(novo.motivo), texto: velho.motivo + ' → ' + novo.motivo });
  }
  if (velho.review !== novo.review) {
    const icone = novo.review === 'changes requested' ? '×' : novo.review === 'approved' ? '✓' : '·';
    lista.push({ icone, texto: 'review: ' + (novo.review || 'nenhum') });
  }
  if (novo.threadsTotal > velho.threadsTotal) {
    lista.push({ icone: '+', texto: (novo.threadsTotal - velho.threadsTotal) + ' thread(s) nova(s)' });
  }
  if (velho.threadsAbertas !== novo.threadsAbertas) {
    lista.push({ icone: '·', texto: 'threads abertas: ' + velho.threadsAbertas + ' → ' + novo.threadsAbertas });
  }
  if (novo.comentarios > velho.comentarios) {
    lista.push({ icone: '+', texto: (novo.comentarios - velho.comentarios) + ' comentário(s) novo(s)' });
  }
  if (velho.estado !== novo.estado) {
    const icone = novo.estado === 'MERGED' ? '✓' : novo.estado === 'CLOSED' ? '×' : '·';
    lista.push({ icone, texto: velho.estado.toLowerCase() + ' → ' + novo.estado.toLowerCase() });
  }
  return lista;
}

// O que o pane desenha do resumo: o estado em destaque e os chips com glifo e tom (nome de
// tema do engine; null = apagado). Formato adaptado do painel de MR do wildz-data, de
// Rafael Lopes, copiado com autorizacao dele (2026-10-09).
const TOM_DO_ICONE = { '✓': 'success', '×': 'error', '◐': 'warning' };

export function tomDoIcone(icone) {
  return TOM_DO_ICONE[icone] ?? null;
}

function tomDoMotivo(m) {
  if (m === 'mergeável') return { glyph: '✓', tone: 'success' };
  if (m === 'conflito' || m === 'bloqueado') return { glyph: '×', tone: 'error' };
  if (m === 'desatualizado' || m === 'checks não passaram' || m === 'draft') return { glyph: '◐', tone: 'warning' };
  return { glyph: '○', tone: null };
}

export function bloco(r) {
  const tons = { OPEN: 'success', MERGED: 'merged', CLOSED: 'error' };
  const iconeC = iconeChecks(r.checks);
  const chips = [
    { glyph: iconeC === '·' ? '○' : iconeC, text: r.checks, tone: tomDoIcone(iconeC) },
    { ...tomDoMotivo(r.motivo), text: r.motivo },
  ];
  if (r.review === 'approved') chips.push({ glyph: '✓', text: 'aprovado', tone: 'success' });
  else if (r.review === 'changes requested') chips.push({ glyph: '×', text: 'mudança pedida', tone: 'error' });
  else if (r.review === 'review required') chips.push({ glyph: '◐', text: 'review pendente', tone: 'warning' });
  chips.push({
    glyph: '',
    text: 'threads ' + r.threadsAbertas + '/' + r.threadsTotal + ' · ' + r.comentarios + ' coment.',
    tone: r.threadsAbertas > 0 ? 'warning' : null,
  });
  return {
    label: String(r.estado || '').toLowerCase(),
    labelTone: tons[r.estado] ?? null,
    sub: r.branch + ' → ' + r.base + ' · @' + r.autor,
    url: r.url,
    chips,
  };
}

// A leitura que pede acao: null para mudanca nao decisiva e quando nao ha leitura anterior.
export function virada(velho, novo) {
  if (!velho) return null;
  if (velho.estado !== 'MERGED' && novo.estado === 'MERGED') return 'merged';
  if (velho.motivo !== 'conflito' && novo.motivo === 'conflito') return 'conflito';
  if (!velho.checks.includes('falharam') && novo.checks.includes('falharam')) return 'checks-falha';
  if (velho.review !== 'changes requested' && novo.review === 'changes requested') return 'mudanca-pedida';
  if (!velho.checks.startsWith('checks ok') && novo.checks.startsWith('checks ok')) return 'checks-ok';
  return null;
}

export function quieto(ultimaMudancaMs, agoraMs) {
  return agoraMs - ultimaMudancaMs >= QUIETO_MS;
}

export function ehDaSessao({ origem, branch }) {
  return origem === 'sessao' || (origem === 'retomada' && /^fluxo\//.test(branch || ''));
}

// Texto para o modelo: so o numero e a acao. Titulo, nomes de branch e corpo do PR sao
// escritos por quem abre o PR e nunca entram aqui — chegariam ao modelo como instrucao
// (revisao de seguranca do commit 361caeb9). O titulo fica no pane, que e tela do usuario.
export function nota(virada, r) {
  const n = Number(r.numero);
  const pr = 'PR #' + n;
  if (virada === 'checks-ok') {
    if (r.mergavel) {
      return pr + ': checks ok e mergeável (mergeStateStatus CLEAN). Mande mergear: gh pr merge ' + n + ' --squash --delete-branch';
    }
    return pr + ': checks ok, mas NÃO mande mergear: ' + r.motivo + '.';
  }
  if (virada === 'checks-falha') return pr + ': checks falharam. Investigue e conserte na branch do PR.';
  if (virada === 'mudanca-pedida') return pr + ': mudança pedida na review. Resuma e traga ao usuário, sem alterar nada.';
  if (virada === 'conflito') return pr + ': conflito com a base. Resuma e traga ao usuário, sem alterar nada.';
  if (virada === 'merged') return pr + ' foi mergeado. Informe o usuário e diga para limpar o worktree e a branch.';
  return '';
}

export function deveAcordar({ origem, branch, virada, ultimaMudancaMs, agoraMs }) {
  return ehDaSessao({ origem, branch }) && virada !== null && quieto(ultimaMudancaMs, agoraMs);
}

// Executavel que o mod pode rodar: `saida` e o que `where.exe` (Windows) ou `which -a` (outros)
// imprimiu. Vale a primeira linha que e caminho absoluto e que NAO esta dentro do repositorio
// da sessao (`cwdSessao`): o Windows procura o executavel primeiro na pasta atual, e um
// repositorio clonado com gh.exe/claude.cmd na raiz rodaria codigo dele a cada consulta.
// Sem `cwdSessao` nao ha como provar que o caminho esta fora: nada serve (null).
const barras = (p) => String(p).trim().replace(/\\/g, '/');
const absoluto = (l) => /^([a-z]:\/|\/)/i.test(barras(l));
const dentro = (l, base) => {
  const b = barras(base).replace(/\/+$/, '');
  if (b === '') return true;
  const doWindows = /^[a-z]:\//i.test(b) || /^[a-z]:\//i.test(barras(l));
  const x = doWindows ? barras(l).toLowerCase() : barras(l);
  const y = doWindows ? b.toLowerCase() : b;
  return x === y || x.startsWith(y + '/');
};

// Os proprios localizadores e o cmd vao por caminho absoluto: chamados pelo nome, o Windows
// os procura primeiro na pasta atual, e com o plugin carregado de dentro de um repositorio
// (--plugin-dir, claude plugin test) essa pasta e do repositorio (auditoria de 2026-10-09).
export function raizDoSistema(systemRoot) {
  const r = String(systemRoot || '').replace(/[\\/]+$/, '');
  return /^[A-Za-z]:\\/.test(r + '\\') && absoluto(r) ? r : 'C:\\Windows';
}

export function localizadores(nome, systemRoot) {
  const raiz = raizDoSistema(systemRoot);
  return [
    [raiz + '\\System32\\where.exe', nome + '.exe', nome + '.cmd', nome + '.bat'],
    ['/usr/bin/which', '-a', nome],
  ];
}

export function interpretadorDeLote(systemRoot) {
  return raizDoSistema(systemRoot) + '\\System32\\cmd.exe';
}

// O gh do painel roda sozinho, com a pasta do repositorio como cwd; um core.fsmonitor
// plantado no .git/config do repositorio rodaria no git que o gh chama. Desligado por env.
export const AMBIENTE_GIT_SEGURO = {
  GIT_CONFIG_COUNT: '1',
  GIT_CONFIG_KEY_0: 'core.fsmonitor',
  GIT_CONFIG_VALUE_0: 'false',
};

export function escolherExecutavel(saida, cwdSessao) {
  const linhas = String(saida || '').split(/\r?\n/).map((l) => l.trim()).filter((l) => l !== '');
  const base = cwdSessao;
  return linhas.find((l) => absoluto(l) && !dentro(l, base)) ?? null;
}

// O PR so conta como da sessao (acorda o modelo) se o autor e quem esta logado no gh e o PR
// nao vem de fork: PR de terceiro pode aparecer na saida de um comando ou numa branch fluxo/*.
export function donoConfere({ autor, eu, cruzado }) {
  return Boolean(eu) && autor === eu && cruzado === false;
}
