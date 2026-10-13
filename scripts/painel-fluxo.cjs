#!/usr/bin/env node
/**
 * Painel do fluxo (D6, D7 do design 2026-10-13-executar-dag-painel): um HTML
 * auto-contido por fluxo, em `<dados>/fluxos/<slug>/painel.html`. Quem abre vê, sem
 * rolar, qual tarefa está em voo, qual falta e se o fluxo parou. Os três estados vêm
 * como texto (`integrada`, `em voo`, `pendente`), não só como cor.
 *
 * Por que é arquivo e não Artifact: publicar a cada mudança de status custaria uma
 * publicação por evento, e o painel é leitura local do estado (D6).
 *
 * O `marcar` de executar, revisar e verificar o regenera (`estado.cjs`, `regenerarPainel`).
 * A raiz de dados é a mesma cadeia do gate de teto (`hooks/lib/raiz.cjs`), com o
 * mesmo fallback para `<projeto>/.rainforest`.
 *
 * Uso:
 *   node scripts/painel-fluxo.cjs gerar --slug <slug>   imprime o caminho do arquivo
 */
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require(path.join(__dirname, '..', 'hooks', 'lib', 'raiz.cjs'));

// Todo texto que vem do plano ou do estado passa por aqui. A ordem importa: a
// contrabarra do `&` sai antes dos outros, senão o `&amp;` seria escapado de novo.
function escapar(valor) {
  const texto = valor === undefined || valor === null ? '' : String(valor);
  return texto.replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

const ROTULO_ESTADO = { integrada: 'integrada', em_voo: 'em voo', pendente: 'pendente' };

const CSS = `
:root { color-scheme: light dark; --bg: #fbfbfd; --fg: #1d1d1f; --suave: #5f6368;
  --cartao: #ffffff; --borda: #d2d2d7; --ok: #17703a; --voo: #8a5300; --parado: #b3261e; }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --bg: #161618; --fg: #f5f5f7; --suave: #a1a1a6;
    --cartao: #222225; --borda: #3a3a3f; --ok: #5ed38a; --voo: #f5b94d; --parado: #ff8a80; }
}
:root[data-theme="dark"] { --bg: #161618; --fg: #f5f5f7; --suave: #a1a1a6;
  --cartao: #222225; --borda: #3a3a3f; --ok: #5ed38a; --voo: #f5b94d; --parado: #ff8a80; }
body { margin: 0; background: var(--bg); color: var(--fg);
  font: 15px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 60rem; margin: 0 auto; padding: 16px; }
h1 { font-size: 1.35rem; margin: 0 0 4px; }
.slug { color: var(--suave); font-size: .85rem; margin: 0 0 16px; word-break: break-all; }
dl.resumo { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px;
  background: var(--cartao); border: 1px solid var(--borda); border-radius: 10px;
  padding: 12px 16px; margin: 0 0 20px; }
dl.resumo dt { color: var(--suave); }
dl.resumo dd { margin: 0; font-weight: 600; }
.parado { color: var(--parado); }
.grade { display: grid; grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr)); gap: 12px; }
.cartao { background: var(--cartao); border: 1px solid var(--borda); border-radius: 10px; padding: 12px 14px; }
.cartao h2 { font-size: 1rem; margin: 0 0 4px; }
.cartao .camada { color: var(--suave); font-weight: 400; font-size: .85rem; }
.cartao .titulo { margin: 0 0 8px; }
.chip { display: inline-block; border: 1px solid currentColor; border-radius: 999px;
  padding: 1px 10px; font-size: .85rem; font-weight: 600; }
.chip.integrada { color: var(--ok); }
.chip.em_voo { color: var(--voo); }
.chip.pendente { color: var(--suave); }
.agente { color: var(--suave); font-size: .85rem; margin-left: 6px; }
`;

function cartao(t) {
  const estado = ROTULO_ESTADO[t.estado] ? t.estado : 'pendente';
  const agente = t.estado === 'em_voo' && t.agente
    ? `<span class="agente">agente ${escapar(t.agente)}</span>` : '';
  const iteracao = t.iteracao ? ` · iteração ${escapar(t.iteracao)}` : '';
  return `<article class="cartao">
  <h2>Tarefa ${escapar(t.numero)} <span class="camada">camada ${escapar(t.camada)}${iteracao}</span></h2>
  <p class="titulo">${escapar(t.titulo)}</p>
  <p><span class="chip ${estado}">${escapar(ROTULO_ESTADO[estado])}</span>${agente}</p>
</article>`;
}

function listaNumeros(tarefas) {
  return tarefas.length ? tarefas.map((t) => escapar(t.numero)).join(', ') : 'nenhuma';
}

/** Monta o HTML inteiro a partir do modelo de `estado.cjs` `modeloDoPainel`. */
function montarHtml(m) {
  const emVoo = m.tarefas.filter((t) => t.estado === 'em_voo');
  const faltam = m.tarefas.filter((t) => t.estado !== 'integrada');
  const parado = m.parado.length
    ? `<span class="parado">parado em ${escapar(m.parado[0].estagio)}: ${escapar(m.parado[0].status)}</span>`
    : (m.estagio_atual === null ? 'concluído' : 'em andamento');
  const estagio = m.estagio_atual === null ? 'fluxo completo' : escapar(m.estagio_atual);
  const emVooTexto = emVoo.length
    ? emVoo.map((t) => `tarefa ${escapar(t.numero)} ${escapar(t.titulo)}${t.agente ? ` (agente ${escapar(t.agente)})` : ''}`).join('; ')
    : 'nenhuma';
  const faltaTexto = faltam.length
    ? `${faltam.length} (${listaNumeros(faltam)})`
    : 'nenhuma';
  const reMarcar = m.re_marcar.length
    ? `<dt>Integrada no git, não marcada</dt><dd>${listaNumeros(m.re_marcar.map((n) => ({ numero: n })))}</dd>`
    : '';
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Painel ${escapar(m.slug)}</title>
<style>${CSS}</style>
</head>
<body>
<main>
<h1>${escapar(m.titulo)}</h1>
<p class="slug">${escapar(m.slug)}</p>
<dl class="resumo">
<dt>Em voo</dt><dd>${emVooTexto}</dd>
<dt>Falta</dt><dd>${faltaTexto}</dd>
<dt>Fluxo</dt><dd>${parado}</dd>
<dt>Estágio atual</dt><dd>${estagio}</dd>
<dt>Último marcar</dt><dd>${m.ultimo_marcar ? escapar(m.ultimo_marcar) : 'nenhum'}</dd>
<dt>Veredito de revisar</dt><dd>${m.veredito_revisar ? escapar(m.veredito_revisar) : 'ainda não'}</dd>
${reMarcar}
</dl>
<section class="grade">
${m.tarefas.map(cartao).join('\n')}
</section>
</main>
</body>
</html>
`;
}

function raizDeDados(projeto) {
  const r = resolverRaiz({ cwd: projeto });
  return (r && r.raiz) || path.join(projeto, '.rainforest');
}

/** Grava `<raiz>/fluxos/<slug>/painel.html` de forma atômica e devolve o caminho. */
function gravarPainel(m) {
  const dir = path.join(raizDeDados(m.projeto), 'fluxos', m.slug);
  fs.mkdirSync(dir, { recursive: true });
  const arquivo = path.join(dir, 'painel.html');
  const tmp = `${arquivo}.tmp`;
  fs.writeFileSync(tmp, montarHtml(m), 'utf8');
  fs.renameSync(tmp, arquivo);
  return arquivo;
}

function main() {
  const [cmd] = process.argv.slice(2);
  const i = process.argv.indexOf('--slug');
  const slug = i > 0 ? process.argv[i + 1] : undefined;
  if (cmd !== 'gerar' || !slug) {
    console.error('uso: node scripts/painel-fluxo.cjs gerar --slug <slug>');
    process.exit(1);
  }
  let arquivo;
  try {
    const { modeloDoPainel } = require(path.join(__dirname, 'estado.cjs'));
    arquivo = gravarPainel(modeloDoPainel(slug));
  } catch (e) {
    console.error(`erro: painel: ${e && e.message ? e.message : e}`);
    process.exit(1);
  }
  console.log(arquivo);
}

if (require.main === module) main();
module.exports = { escapar, montarHtml, gravarPainel };
