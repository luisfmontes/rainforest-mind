// Logica pura do plugins-em-dia: quais plugins da lista estao instalados no escopo user,
// a versao de cada um, a ordem dos comandos de atualizacao, a comparacao de versoes e a
// janela de intervalo. ES module sem Node e sem relogio: o instante entra por argumento
// (`agoraMs`, em ms), nunca por leitura. Quem le o installed_plugins.json e quem roda o
// claude fica fora daqui.

export const LISTA_PADRAO = ['rainforest-mind@rainforest-mind'];
// Periodo entre uma checagem automatica e a seguinte (3 h).
export const PERIODO_MS = 10800000;
// Varias janelas abrem juntas; so uma roda o update dentro desta janela (30 min).
export const INTERVALO_MINIMO_MS = 1800000;

// Alvos: os ids da lista com uma INSTALACAO no escopo user. Filtro pelo installed_plugins.json,
// nunca pelo enabledPlugins, que nao enxerga o escopo local.
export function alvos(registro, lista) {
  return lista.filter(id => (registro.plugins?.[id] || []).some(i => i.scope === 'user'));
}

// Versao de cada alvo, lida da entrada user (a local pode estar em outra versao).
export function versoes(registro, ids) {
  const out = {};
  for (const id of ids) {
    const user = (registro.plugins?.[id] || []).find(i => i.scope === 'user');
    if (user) out[id] = user.version;
  }
  return out;
}

// Cada marketplace (parte depois do @) uma vez, na ordem em que aparece nos alvos.
export function marketplaces(lista) {
  const out = [];
  for (const id of lista) {
    const mkt = id.split('@')[1];
    if (!out.includes(mkt)) out.push(mkt);
  }
  return out;
}

// Lista de "nome antes -> depois" so do que mudou. O nome e a parte antes do @.
export function subiram(antes, depois) {
  const out = [];
  for (const id of Object.keys(antes)) {
    if (depois[id] && depois[id] !== antes[id]) {
      out.push(id.split('@')[0] + ' ' + antes[id] + ' -> ' + depois[id]);
    }
  }
  return out;
}

export function podeRodar(ultimaMs, agoraMs, forcado) {
  return forcado || agoraMs - ultimaMs >= INTERVALO_MINIMO_MS;
}

// Sem subida, nada. Com subida, recarrega sozinho so se o recarregamento for seguro.
export function acaoAposSubir(lista, recarregaSeguro) {
  if (lista.length === 0) return 'nada';
  return recarregaSeguro ? 'recarregar' : 'avisar';
}

// Argv na ordem de execucao: primeiro marketplace update (o update do plugin so enxerga
// versao que ja esta no clone local), depois plugin update por alvo.
export function comandos(lista) {
  const out = [];
  for (const mkt of marketplaces(lista)) out.push(['plugin', 'marketplace', 'update', mkt]);
  for (const id of lista) out.push(['plugin', 'update', id, '--scope', 'user']);
  return out;
}
