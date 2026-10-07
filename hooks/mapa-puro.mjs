// Logica pura do mapa da sessao: o que foi escrito, que skill rodou, que servico MCP
// e que subagente entrou. Sem `$`, sem Node, sem relogio: o mod chama com valores.
// D16: so Edit, Write e NotebookEdit contam como escrita; escrita por Bash fica fora.

export const ESCRITORAS = new Set(['Edit', 'Write', 'NotebookEdit']);
export const TETO = 50;

// Controles C0/C1 e override bidi nunca chegam crus ao terminal (mesma classe de
// faixa-puro.mjs; la a funcao ainda nao e exportada, entao fica local e minima).
const CONTROLES = /[\u0000-\u001f\u007f-\u009f\u061c\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060-\u2069\ufeff]/g;
export function semControle(s) {
  return String(s ?? '').replace(CONTROLES, ' ');
}

/** Caminho escrito pela chamada, ou null (leitura, Bash e o resto nao escrevem). */
export function escritaDe(e) {
  if (!ESCRITORAS.has(e.tool)) return null;
  const c = e.tool === 'NotebookEdit' ? e.notebook_path : e.file_path;
  return typeof c === 'string' && c !== '' ? semControle(c) : null;
}

/** Servidor de `mcp__<servidor>__<ferramenta>`, ou null. */
export function servidorDe(tool) {
  const m = /^mcp__(.+?)__.+$/.exec(String(tool ?? ''));
  return m ? semControle(m[1]) : null;
}

export function mapaVazio() {
  return { arquivos: [], skills: [], servicos: [], subagentes: [] };
}

// Estoura o teto: sai a entrada mais antiga sem desvio; so desvio sobrando, a mais antiga.
function aparar(lista) {
  const l = lista.slice();
  while (l.length > TETO) {
    const i = l.findIndex(x => typeof x === 'object' && !x.desvio);
    l.splice(i < 0 ? 0 : i, 1);
  }
  return l;
}

function incluir(lista, nome) {
  if (nome === '' || lista.includes(nome)) return { lista, novo: false };
  return { lista: aparar([...lista, nome]), novo: true };
}

/**
 * Evento: o `tool.call` cru (`tool` mais argumentos), `{ agente: true, description }`
 * para o `agent.spawn`, ou `{ desvio: true, caminho }` para marcar arquivo fora do plano.
 * Devolve `{ mapa, novo }`; `novo` so e true na 1a vez que a entrada aparece.
 */
export function registrar(mapa, evento) {
  const m = { ...mapaVazio(), ...mapa };
  if (evento && evento.agente === true) {
    const r = incluir(m.subagentes, semControle(evento.description).trim());
    return { mapa: { ...m, subagentes: r.lista }, novo: r.novo };
  }
  if (evento && evento.desvio === true) {
    const caminho = semControle(evento.caminho);
    const existe = m.arquivos.some(a => a.caminho === caminho);
    const arquivos = existe
      ? m.arquivos.map(a => (a.caminho === caminho ? { ...a, desvio: true } : a))
      : aparar([...m.arquivos, { caminho, desvio: true }]);
    return { mapa: { ...m, arquivos }, novo: !existe };
  }
  const caminho = escritaDe(evento);
  if (caminho !== null) {
    if (m.arquivos.some(a => a.caminho === caminho)) return { mapa: m, novo: false };
    return { mapa: { ...m, arquivos: aparar([...m.arquivos, { caminho, desvio: false }]) }, novo: true };
  }
  if (evento.tool === 'Skill' && typeof evento.skill === 'string') {
    const r = incluir(m.skills, semControle(evento.skill).trim());
    return { mapa: { ...m, skills: r.lista }, novo: r.novo };
  }
  const servidor = servidorDe(evento.tool);
  if (servidor !== null) {
    const r = incluir(m.servicos, servidor);
    return { mapa: { ...m, servicos: r.lista }, novo: r.novo };
  }
  return { mapa: m, novo: false };
}
