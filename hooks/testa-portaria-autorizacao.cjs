#!/usr/bin/env node
"use strict";
/* Bateria da autorização do usuário (Tarefa 7 do fluxo, D4, D5, D6, D8).
 *
 * Duas partes:
 *
 * PARTE 1 — o LEITOR (hooks/lib/autorizacao-usuario.cjs), chamado direto,
 * sobre as fixtures de test/fixtures/autorizacao/. Cobre concessão digitada e
 * de meio de turno, marcador subordinado, negação (com/sem acento,
 * maiúsculas), precedência entre concessão e negação, negação sobre outro
 * assunto, as duas injeções (tool_result e task-notification) e transcript
 * vazio/inexistente/com linha partida.
 *
 * PARTE 2 — a PORTARIA (hooks/portaria.cjs) como PROCESSO REAL via spawnSync,
 * sobre payload sintético montado em JS (nunca string de shell). Cada sandbox
 * é um repositório git TEMPORÁRIO e ISOLADO, sem `docs/rainforest/estado/`
 * — ou seja, sem fluxo aberto casando com a branch — para que o ramo "sem
 * estágio ativo" da portaria seja, de fato, exercitado. Rodar isto de dentro
 * de um worktree com fluxo aberto NÃO prova nada: o despacho passaria pelo
 * caminho normal, sem nunca consultar a autorização (foi o que aconteceu na
 * sessão que motivou este fluxo, e por isso os testes NUNCA reaproveitam o
 * `raiz` deste repositório — sempre `caixa()`).
 *
 * O coração da bateria são os casos 13 a 16: eles provam que a autorização
 * dispensa SÓ o portão de ESTÁGIO, e nada mais — manifesto ausente, agente não
 * declarado, e as duas travas de `escreve: true` (isolation + ausência de
 * name) continuam negando com autorização válida.
 *
 * Mesmo formato das baterias irmãs: `caso(nome, cond, detalhe)` imprime
 * `ok`/`FALHA`, contagem final `== resultado: N ok, M falha(s) ==`, exit 0
 * só com zero falhas.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");
const LEITOR = path.join(__dirname, "lib", "autorizacao-usuario.cjs");
const FIXTURES = path.join(__dirname, "..", "test", "fixtures", "autorizacao");
const TRANSCRIPT_COMPLETO = path.join(__dirname, "..", "test", "fixtures", "transcript-autorizacao.jsonl");

const { autorizado } = require(LEITOR);

let ok = 0;
let falhou = 0;

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe !== undefined ? ` — ${detalhe}` : ""}`);
  }
}

function fx(nome) {
  return path.join(FIXTURES, nome);
}

// ============================================================================
// PARTE 1 — LEITOR (hooks/lib/autorizacao-usuario.cjs)
// ============================================================================

console.log("== 1. concessao digitada (origin.kind: human) autoriza ==");
{
  const r = autorizado(fx("autorizado-digitado.jsonl"));
  caso("autorizado() = true", r === true, r);
}

console.log("== 2. concessao mandada no meio do turno (queue-operation) autoriza ==");
{
  const r = autorizado(fx("autorizado.jsonl"));
  caso("autorizado() = true", r === true, r);
}

console.log("== 3. mencao sob marcador subordinado NAO autoriza ==");
{
  // Turno isolado: só a frase '...explicitamente falo que autorizo subagentes...'
  const r = autorizado(fx("turno-reclamacao.jsonl"));
  caso("autorizado() = false (subordinada nao conta)", r === false, r);

  // O mesmo turno, precedido de uma concessão de verdade no transcript real:
  // a concessão anterior é que decide, não a menção subordinada posterior.
  const rCompleto = autorizado(TRANSCRIPT_COMPLETO);
  caso("com a concessao anterior no mesmo transcript, autorizado() = true", rCompleto === true, rCompleto);
}

console.log("== 3b. considerar autorizar NAO e autorizar (achados da revisao de 2026-09-12) ==");
{
  // Tres frases de um humano de verdade (`origin.kind: human`, sem injecao
  // nenhuma) que abriam o portao. Nenhuma delas e consentimento: duas sao hedge
  // e uma e pergunta. A trava so cobria fala relatada ("falo que autorizo"), e
  // a lista exigia "se EU autorizo" — "decidi se autorizo" passava batido.
  const rHedge1 = autorizado(fx("hedge-nao-decidi.jsonl"));
  caso("'ainda nao decidi se autorizo subagentes' NAO autoriza", rHedge1 === false, rHedge1);

  const rHedge2 = autorizado(fx("hedge-vou-pensar.jsonl"));
  caso("'vou pensar se autorizo subagentes amanha' NAO autoriza", rHedge2 === false, rHedge2);

  const rPergunta = autorizado(fx("pergunta-posso-autorizar.jsonl"));
  caso("'posso autorizar subagentes ou fica arriscado?' NAO autoriza", rPergunta === false, rPergunta);

  // O envelope de sistema era casado com regex sem a flag `i`: bastava a tag vir
  // com outra caixa para um relato de agente voltar a contar como voz do usuario.
  const rEnvelope = autorizado(fx("envelope-caixa-trocada.jsonl"));
  caso("envelope <Task-Notification> com caixa trocada NAO autoriza", rEnvelope === false, rEnvelope);
}

console.log("== 3c. hedge numa frase NAO mata concessao em outra (falso negativo de 2026-09-12) ==");
{
  // O conserto dos hedges acima varria do marcador ate o FIM do texto. Com isso
  // as tres frases abaixo — concessoes firmes, precedidas de duvida sobre OUTRA
  // coisa — passaram a ser RECUSADAS. Falso negativo e pior que o defeito
  // original: o usuario autoriza, nada acontece, e a negacao fala de estagio.
  const rTalvez = autorizado(fx("concessao-apos-talvez.jsonl"));
  caso("'talvez a gente mude o plano depois. autorizo subagentes' AUTORIZA", rTalvez === true, rTalvez);

  const rPergAntes = autorizado(fx("concessao-apos-pergunta.jsonl"));
  caso("'sera que o CI aguenta? autorizo subagentes agora' AUTORIZA", rPergAntes === true, rPergAntes);

  const rPensar = autorizado(fx("concessao-apos-vou-pensar.jsonl"));
  caso("'vou pensar no design amanha. autorizo subagentes ja' AUTORIZA", rPensar === true, rPensar);

  // E a ponta que sobrou do lado contrario: pergunta digitada com pressa, sem o
  // ponto de interrogacao, continua sendo pedido de opiniao.
  const rSemInterrog = autorizado(fx("pergunta-sem-interrogacao.jsonl"));
  caso("'posso autorizar subagentes' (sem '?') NAO autoriza", rSemInterrog === false, rSemInterrog);

  // Pergunta que NENHUM marcador pega: quem segura esta e so o '?'. Sem este
  // caso, apagar a regra da pergunta deixava a bateria verde — medido.
  const rPergSemMarcador = autorizado(fx("pergunta-sem-marcador.jsonl"));
  caso("'te autorizar subagentes ajuda em alguma coisa?' NAO autoriza", rPergSemMarcador === false, rPergSemMarcador);
}

console.log("== 3d. pontuacao grudada e oracao por virgula (achados da 2a rodada de revisao) ==");
{
  // A regra da pergunta era `endsWith('?')`, estreita demais: qualquer coisa
  // colada depois do sinal escapava — e escapava para o lado PERIGOSO, abrindo
  // o portao numa pergunta de verdade.
  const rInterrogColada = autorizado(fx("pergunta-interrogacao-colada.jsonl"));
  caso("'autorizo subagentes?!' NAO autoriza", rInterrogColada === false, rInterrogColada);

  const rInterrogAspas = autorizado(fx("pergunta-interrogacao-com-aspas.jsonl"));
  caso("pergunta entre aspas ('...subagentes?\"') NAO autoriza", rInterrogAspas === false, rInterrogAspas);

  // O outro lado do mesmo sinal: confirmacao casual no fim nao transforma
  // concessao em pergunta.
  const rRabicho = autorizado(fx("concessao-com-rabicho.jsonl"));
  caso("'autorizo subagentes, beleza?' AUTORIZA", rRabicho === true, rRabicho);

  // O marcador subordina por ORACAO, nao pela frase inteira: virgula separa.
  const rVirgula = autorizado(fx("concessao-apos-hedge-virgula.jsonl"));
  caso("'talvez seja arriscado, autorizo subagentes mesmo assim' AUTORIZA", rVirgula === true, rVirgula);

  // ...e o contrario tem de continuar valendo: marcador COLADO no verbo, na
  // mesma oracao, subordina mesmo com adversativa depois. Guarda de regressao —
  // ja passava antes da quebra por oracao, e o valor dela e nao deixar de
  // passar depois.
  const rColado = autorizado(fx("hedge-colado-no-verbo-virgula.jsonl"));
  caso("'nao sei se autorizo subagentes, mas talvez amanha' NAO autoriza", rColado === false, rColado);

  // Virgula de aposto nao e fronteira de oracao: o subordinador pendurado
  // carrega a duvida para a frente.
  const rPendurado = autorizado(fx("subordinador-pendurado.jsonl"));
  caso("'nao sei se, no fim, autorizo subagentes' NAO autoriza", rPendurado === false, rPendurado);

  // Guarda de regressao, nao teste de mecanismo: quem barra esta e o marcador
  // `se autoriz`, que ja subordinava antes da quebra por oracao existir.
  // Registrado assim porque a revisao de 2026-09-12 mostrou que o comentario
  // anterior afirmava testar a ordem "pergunta antes da quebra", e nao testava.
  const rCondicional = autorizado(fx("condicional-com-pergunta.jsonl"));
  caso("'se autorizo subagentes, voce faz?' NAO autoriza", rCondicional === false, rCondicional);

  // Esta sim exercita a ordem: nenhum marcador pega a frase, entao so a regra
  // da pergunta — aplicada na FRASE, antes de quebrar em oracoes — a segura.
  // Com a quebra vindo primeiro, "vale a pena te autorizar subagentes" viraria
  // oracao sem '?' e concederia.
  const rMultiOracao = autorizado(fx("pergunta-multioracao.jsonl"));
  caso("'vale a pena te autorizar subagentes, ou faco eu mesmo?' NAO autoriza", rMultiOracao === false, rMultiOracao);

  // Guarda de regressao: quem barra e o marcador `posso autoriz`, nao o rabicho.
  const rPergRabicho = autorizado(fx("pergunta-com-rabicho.jsonl"));
  caso("'posso autorizar subagentes, ta?' NAO autoriza", rPergRabicho === false, rPergRabicho);
}

console.log("== 3e. rabicho ambiguo, '?' colado e palavra comum (achados da 3a rodada) ==");
{
  // `sim` e `ne` estavam na lista de rabichos e fechavam QUALQUER oracao
  // anterior, inclusive hesitante — o portao abria numa duvida declarada.
  const rSim = autorizado(fx("pergunta-hesitante-com-sim.jsonl"));
  caso("'nao tenho certeza, autorizo subagentes, sim?' NAO autoriza", rSim === false, rSim);

  const rNe = autorizado(fx("pergunta-hesitante-com-ne.jsonl"));
  caso("'fico em duvida, autorizo subagentes, ne?' NAO autoriza", rNe === false, rNe);

  // '?' colado na proxima palavra nao esta na cauda de pontuacao; a regra passou
  // a ser '?' em qualquer lugar da frase.
  const rColadoPalavra = autorizado(fx("pergunta-interrogacao-colada-em-palavra.jsonl"));
  caso("'autorizo subagentes?ou nao' NAO autoriza", rColadoPalavra === false, rColadoPalavra);

  // `quando` e `caso` saíram dos subordinadores pendurados: fora do papel de
  // conjuncao sao palavra comum, e recusar concessao e o lado ruim do erro.
  const rQuando = autorizado(fx("concessao-apos-quando.jsonl"));
  caso("'nao sei quando, autorizo subagentes agora mesmo' AUTORIZA", rQuando === true, rQuando);

  const rCaso = autorizado(fx("concessao-apos-caso.jsonl"));
  caso("'vai depender do caso, autorizo subagentes' AUTORIZA", rCaso === true, rCaso);
}

console.log("== 4. negacao sem acento ('nao autorizo subagentes') NAO autoriza ==");
{
  const r = autorizado(fx("negado-sem-acento.jsonl"));
  caso("autorizado() = false", r === false, r);
}

console.log("== 5. negacao com acento, em maiusculas, NAO autoriza ==");
{
  const comAcento = autorizado(fx("negado-com-acento.jsonl"));
  caso("com acento ('não autorizo subagentes') = false", comAcento === false, comAcento);

  const maiuscula = autorizado(fx("negado-maiuscula.jsonl"));
  caso("maiuscula sem acento ('NAO AUTORIZO SUBAGENTES') = false", maiuscula === false, maiuscula);

  const ambos = autorizado(fx("negado-acento-maiuscula.jsonl"));
  caso("acento E maiuscula juntos ('NÃO AUTORIZO SUBAGENTES') = false", ambos === false, ambos);
}

console.log("== 6. precedencia: a ULTIMA palavra e que vale ==");
{
  const concessaoDepoisNegacao = autorizado(fx("negado-sem-acento.jsonl"));
  caso("concessao e DEPOIS negacao = false", concessaoDepoisNegacao === false, concessaoDepoisNegacao);

  const negacaoDepoisConcessao = autorizado(fx("negacao-depois-concessao.jsonl"));
  caso("negacao e DEPOIS concessao = true", negacaoDepoisConcessao === true, negacaoDepoisConcessao);
}

console.log("== 7. negacao sobre OUTRO assunto depois de conceder continua autorizado ==");
{
  const r = autorizado(fx("outro-assunto.jsonl"));
  caso("'nao autorizo mexer no meu ambiente' nao revoga 'autorizo subagentes' = true", r === true, r);
}

console.log("== 8. injecao por tool_result NAO autoriza ==");
{
  const r = autorizado(fx("injecao-por-tool-result.jsonl"));
  caso("um arquivo lido contendo a frase nao abre o portao = false", r === false, r);
}

console.log("== 9. injecao por <task-notification> NAO autoriza ==");
{
  const r = autorizado(fx("injecao-por-notificacao.jsonl"));
  caso("relato de subagente citando a frase nao abre o portao = false", r === false, r);
}

console.log("== 10. transcript vazio, inexistente, e com linha JSON partida no fim NAO estouram ==");
{
  let vazio, erroVazio = null;
  try {
    vazio = autorizado(fx("vazio.jsonl"));
  } catch (e) {
    erroVazio = e;
  }
  caso("transcript vazio nao estoura", erroVazio === null, erroVazio && erroVazio.message);
  caso("transcript vazio = false", vazio === false, vazio);

  let inexistente, erroInexistente = null;
  try {
    inexistente = autorizado(fx("nao-existe-de-verdade.jsonl"));
  } catch (e) {
    erroInexistente = e;
  }
  caso("transcript inexistente nao estoura", erroInexistente === null, erroInexistente && erroInexistente.message);
  caso("transcript inexistente = false", inexistente === false, inexistente);

  let partida, erroPartida = null;
  try {
    partida = autorizado(fx("linha-partida.jsonl"));
  } catch (e) {
    erroPartida = e;
  }
  caso("transcript com linha JSON partida no fim nao estoura", erroPartida === null, erroPartida && erroPartida.message);
  // A linha partida é descartada (JSON.parse falha, entra no catch e continua);
  // a concessão válida da linha anterior é que decide.
  caso("e a concessao da linha anterior, intacta, ainda vale = true", partida === true, partida);
}

// ============================================================================
// PARTE 2 — PORTARIA (hooks/portaria.cjs), processo real
// ============================================================================

function caixa(prefixo) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `portaria-autorizacao-${prefixo}-`));
}

function iniciarGit(raiz) {
  // Branch qualquer, sem prefixo 'fluxo/': o que importa aqui é que
  // docs/rainforest/estado/ NUNCA é criado nestes sandboxes, então o
  // resolvedor de estágio ativo devolve null incondicionalmente — é assim
  // que o ramo "sem estágio ativo" da portaria é alcançado de propósito, e
  // não por acidente de branch.
  spawnSync("git", ["init", "-q"], { cwd: raiz });
  spawnSync("git", ["config", "user.email", "<email>"], { cwd: raiz });
  spawnSync("git", ["config", "user.name", "Test"], { cwd: raiz });
  fs.writeFileSync(path.join(raiz, "README"), "test", "utf8");
  spawnSync("git", ["add", "."], { cwd: raiz });
  spawnSync("git", ["commit", "-q", "-m", "initial"], { cwd: raiz });
}

function criarManifesto(raiz, manifesto) {
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), JSON.stringify(manifesto, null, 2) + "\n", "utf8");
}

function manifestoD2(agentes) {
  return { versao: 1, agentes };
}

function rodaHook(raiz, payload) {
  // Payload SEMPRE montado como objeto JS e serializado aqui — nunca como
  // string de shell com aspas aninhadas.
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload),
    env: { ...process.env, CLAUDE_PROJECT_DIR: raiz },
    encoding: "utf8",
  });
}

function ultimaLinhaDoLog(raiz) {
  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  if (!fs.existsSync(logPath)) return null;
  const linhas = fs.readFileSync(logPath, "utf8").trim().split("\n").filter(Boolean);
  if (linhas.length === 0) return null;
  try {
    return JSON.parse(linhas[linhas.length - 1]);
  } catch {
    return null;
  }
}

console.log("== 11. sem fluxo + autorizacao valida -> exit 0, log com estagio/decisao/via ==");
{
  const raiz = caixa("11");
  iniciarGit(raiz);
  criarManifesto(raiz, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));

  const r = rodaHook(raiz, {
    session_id: "s11",
    cwd: raiz,
    transcript_path: fx("autorizado.jsonl"),
    tool_input: { subagent_type: "revisor" },
  });

  caso("exit 0", r.status === 0, `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);

  const entrada = ultimaLinhaDoLog(raiz);
  caso("log tem uma linha JSON valida", entrada !== null, entrada);
  if (entrada) {
    caso("estagio = 'fora-de-fluxo'", entrada.estagio === "fora-de-fluxo", entrada.estagio);
    caso("decisao = 'allow'", entrada.decisao === "allow", entrada.decisao);
    caso("via = 'autorizacao-do-usuario'", entrada.via === "autorizacao-do-usuario", entrada.via);
  }

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log("== 12. sem fluxo + sem autorizacao -> exit 2, motivo 'sem estagio ativo' ==");
{
  const raiz = caixa("12");
  iniciarGit(raiz);
  criarManifesto(raiz, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));

  // A ARMADILHA: usar o transcript INTEIRO (test/fixtures/transcript-autorizacao.jsonl)
  // aqui daria exit 0 por engano — ele tem uma concessão válida ANTES do turno
  // de reclamação. O caso certo é o turno isolado, sem a concessão.
  const r = rodaHook(raiz, {
    session_id: "s12",
    cwd: raiz,
    transcript_path: fx("turno-reclamacao.jsonl"),
    tool_input: { subagent_type: "revisor" },
  });

  caso("exit 2", r.status === 2, `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  caso("motivo cita 'sem estágio ativo'", (r.stderr || "").includes("sem estágio ativo"), r.stderr);

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log("== 13. manifesto AUSENTE + autorizacao valida -> continua exit 2 ==");
{
  const raiz = caixa("13");
  iniciarGit(raiz);
  // Sem manifesto de propósito: a autorização não pode criar o que falta.

  const r = rodaHook(raiz, {
    session_id: "s13",
    cwd: raiz,
    transcript_path: fx("autorizado.jsonl"),
    tool_input: { subagent_type: "revisor" },
  });

  caso("exit 2 (autorizacao NAO cria manifesto)", r.status === 2, `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  caso("motivo cita manifesto ausente", /manifesto n[aã]o encontrado/i.test(r.stderr || ""), r.stderr);

  const entrada = ultimaLinhaDoLog(raiz);
  caso("a linha de deny nao carrega 'via' (autorizacao nunca foi consultada)",
    entrada === null || entrada.via === undefined, JSON.stringify(entrada));

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log("== 14. agente NAO declarado + autorizacao valida -> continua exit 2 ==");
{
  const raiz = caixa("14");
  iniciarGit(raiz);
  // Manifesto existe, mas não declara 'revisor'.
  criarManifesto(raiz, manifestoD2({ outro: { estagios: ["revisar"], escreve: false } }));

  const r = rodaHook(raiz, {
    session_id: "s14",
    cwd: raiz,
    transcript_path: fx("autorizado.jsonl"),
    tool_input: { subagent_type: "revisor" },
  });

  caso("exit 2 (autorizacao NAO declara agente)", r.status === 2, `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  caso("motivo cita o agente e 'nao consta no manifesto'",
    (r.stderr || "").includes("revisor") && (r.stderr || "").includes("não consta no manifesto"), r.stderr);

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log("== 15. escreve:true + autorizacao + SEM isolation:'worktree' -> continua exit 2 ==");
{
  const raiz = caixa("15");
  iniciarGit(raiz);
  criarManifesto(raiz, manifestoD2({ escritor: { estagios: ["executar"], escreve: true } }));

  const r = rodaHook(raiz, {
    session_id: "s15",
    cwd: raiz,
    transcript_path: fx("autorizado.jsonl"),
    tool_input: { subagent_type: "escritor" }, // sem isolation
  });

  caso("exit 2 (autorizacao NAO dispensa a regra 11)", r.status === 2, `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  caso("motivo nomeia isolation: \"worktree\"", (r.stderr || "").includes('isolation: "worktree"'), r.stderr);

  // Controle positivo, no MESMO sandbox: o mesmo agente, a mesma autorização,
  // mas com isolation:"worktree" e sem name, aprova. Prova que a negação
  // acima é sobre o isolamento — não uma recusa cega a 'escreve:true' com
  // autorização.
  const rControle = rodaHook(raiz, {
    session_id: "s15b",
    cwd: raiz,
    transcript_path: fx("autorizado.jsonl"),
    tool_input: { subagent_type: "escritor", isolation: "worktree" },
  });
  caso("controle: com isolation:'worktree' e sem name, aprova (exit 0)",
    rControle.status === 0, `exit=${rControle.status} stderr=${JSON.stringify(rControle.stderr)}`);
  const entradaControle = ultimaLinhaDoLog(raiz);
  caso("e o log do controle registra via + isolation",
    entradaControle && entradaControle.via === "autorizacao-do-usuario" && entradaControle.isolation === "worktree",
    JSON.stringify(entradaControle));

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log("== 16. escreve:true + autorizacao + com 'name' preenchido -> continua exit 2 ==");
{
  const raiz = caixa("16");
  iniciarGit(raiz);
  criarManifesto(raiz, manifestoD2({ escritor: { estagios: ["executar"], escreve: true } }));

  const r = rodaHook(raiz, {
    session_id: "s16",
    cwd: raiz,
    transcript_path: fx("autorizado.jsonl"),
    tool_input: { subagent_type: "escritor", isolation: "worktree", name: "sonda-um" },
  });

  caso("exit 2 (autorizacao NAO dispensa a regra 10)", r.status === 2, `exit=${r.status} stderr=${JSON.stringify(r.stderr)}`);
  caso("motivo cita o name recebido", (r.stderr || "").includes("sonda-um"), r.stderr);

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log("== 17. as mensagens de negacao sao distintas, cada uma com o seu texto ==");
{
  const raizAusente = caixa("17-ausente");
  iniciarGit(raizAusente);
  criarManifesto(raizAusente, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));
  const rAusente = rodaHook(raizAusente, {
    session_id: "s17a",
    cwd: raizAusente,
    // transcript_path AUSENTE do payload (chave nem existe)
    tool_input: { subagent_type: "revisor" },
  });
  caso("transcript_path ausente: exit 2", rAusente.status === 2, `exit=${rAusente.status}`);
  caso("transcript_path ausente: motivo 'sem estágio ativo'",
    (rAusente.stderr || "").includes("sem estágio ativo — abra um fluxo"), rAusente.stderr);
  fs.rmSync(raizAusente, { recursive: true, force: true });

  const raizVazio = caixa("17-vazio");
  iniciarGit(raizVazio);
  criarManifesto(raizVazio, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));
  const rVazio = rodaHook(raizVazio, {
    session_id: "s17b",
    cwd: raizVazio,
    transcript_path: "",
    tool_input: { subagent_type: "revisor" },
  });
  caso("transcript_path vazio: exit 2", rVazio.status === 2, `exit=${rVazio.status}`);
  caso("transcript_path vazio: motivo proprio, distinto do 'ausente'",
    (rVazio.stderr || "").includes("autorização não pôde ser conferida — transcript_path não foi fornecido"),
    rVazio.stderr);
  fs.rmSync(raizVazio, { recursive: true, force: true });

  const raizInexistente = caixa("17-inexistente");
  iniciarGit(raizInexistente);
  criarManifesto(raizInexistente, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));
  const caminhoFalso = fx("nao-existe-de-verdade.jsonl");
  const rInexistente = rodaHook(raizInexistente, {
    session_id: "s17c",
    cwd: raizInexistente,
    transcript_path: caminhoFalso,
    tool_input: { subagent_type: "revisor" },
  });
  caso("arquivo inexistente: exit 2", rInexistente.status === 2, `exit=${rInexistente.status}`);
  caso("arquivo inexistente: motivo cita o caminho e 'não existe'",
    (rInexistente.stderr || "").includes(caminhoFalso) && (rInexistente.stderr || "").includes("não existe"),
    rInexistente.stderr);
  fs.rmSync(raizInexistente, { recursive: true, force: true });

  const raizNegacao = caixa("17-negacao");
  iniciarGit(raizNegacao);
  criarManifesto(raizNegacao, manifestoD2({ revisor: { estagios: ["revisar"], escreve: false } }));
  const rNegacao = rodaHook(raizNegacao, {
    session_id: "s17d",
    cwd: raizNegacao,
    transcript_path: fx("negado-sem-acento.jsonl"),
    tool_input: { subagent_type: "revisor" },
  });
  caso("negacao explicita: exit 2", rNegacao.status === 2, `exit=${rNegacao.status}`);
  caso("negacao explicita: motivo proprio, sobre revogacao",
    (rNegacao.stderr || "").includes("autorização foi revogada"), rNegacao.stderr);
  fs.rmSync(raizNegacao, { recursive: true, force: true });

  // As quatro mensagens sao, de fato, DIFERENTES entre si — nao a mesma
  // string reaproveitada para os quatro casos.
  //
  // Esta assercao ja foi decorativa: ela montava um Set com as quatro strings
  // ESPERADAS, digitadas aqui, e conferia `size === 4`. Passava sem consultar o
  // hook uma vez sequer — mutar a portaria para emitir a mesma mensagem generica
  // nos quatro ramos deixava esta linha verde. Achado da revisao de 2026-09-12.
  // Agora ela le o stderr REAL dos quatro processos que ja rodaram acima.
  const primeiraLinha = (r) => String((r && r.stderr) || "").trim().split("\n")[0].trim();
  const reais = [rAusente, rVazio, rInexistente, rNegacao].map(primeiraLinha);
  const textos = new Set(reais);
  caso("as quatro mensagens REAIS do hook sao distintas entre si", textos.size === 4, reais);
  caso("nenhuma das quatro mensagens reais e vazia", reais.every((t) => t.length > 0), reais);
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);

if (falhou > 0) {
  process.exit(1);
} else {
  console.log("todos os casos: OK");
  process.exit(0);
}
