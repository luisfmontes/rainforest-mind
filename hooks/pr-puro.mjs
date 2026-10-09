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
  return MOTIVOS[m] ?? m.toLowerCase();
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
  return origem === 'sessao' || /^fluxo\//.test(branch || '');
}

// Texto para o modelo: numero, titulo e a acao que cabe a cada virada.
export function nota(virada, r) {
  const pr = 'PR #' + r.numero + ' (' + r.titulo + ')';
  if (virada === 'checks-ok') {
    if (r.mergavel) {
      return pr + ': checks ok e mergeável (mergeStateStatus CLEAN). Mande mergear: gh pr merge ' + r.numero + ' --squash --delete-branch';
    }
    return pr + ': checks ok, mas NÃO mande mergear: ' + r.motivo + '.';
  }
  if (virada === 'checks-falha') return pr + ': checks falharam. Investigue e conserte na branch ' + r.branch + '.';
  if (virada === 'mudanca-pedida') return pr + ': mudança pedida na review. Resuma e traga ao usuário, sem alterar nada.';
  if (virada === 'conflito') return pr + ': conflito com ' + r.base + '. Resuma e traga ao usuário, sem alterar nada.';
  if (virada === 'merged') return pr + ' foi mergeado. Informe o usuário e diga para limpar o worktree e a branch.';
  return '';
}

export function deveAcordar({ origem, branch, virada, ultimaMudancaMs, agoraMs }) {
  return ehDaSessao({ origem, branch }) && virada !== null && quieto(ultimaMudancaMs, agoraMs);
}
