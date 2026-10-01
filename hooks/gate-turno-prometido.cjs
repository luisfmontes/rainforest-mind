#!/usr/bin/env node
// @categoria: sensor
/**
 * Stop — barra o turno que promete despacho ou espera de máquina sem concretizar.
 * Protege contra: promessa de ação (despacho, vigia) que não foi executada no turno
 * Não protege contra: gate desligado ou stop_hook_active ativo (anti-loop)
 *
 * Tarefa 10 do plano 2026-09-30-semear-travas (D3): quando o turno termina com uma
 * promessa de "vou despachar" ou "aguardando o CI" mas sem a ferramenta correspondente,
 * o hook barra. Duas categorias:
 *
 * (a) Promete despacho futuro/em andamento ("vou despachar", "despachando", "disparo agora")
 *     sem `tool_use` de tipo `Agent` ou `Task` → exit 2
 *
 * (b) Promete espera de máquina ("CI rodando", "aguardando o CI/build") sem:
 *     - `Bash` com `input.run_in_background === true`, OU
 *     - `Monitor`, OU
 *     - `ScheduleWakeup`
 *     → exit 2
 *
 * Saídas silenciosas:
 * - gate desligado (`ligado('gate-turno-prometido')` = false)
 * - `stop_hook_active === true` (anti-loop)
 * - payload com `agent_id` (não é janela principal)
 * - payload ou transcrição ilegível (aviso no stderr, nunca derruba)
 */

const fs = require('node:fs');
const path = require('node:path');

function bloqueia(motivo) {
  process.stderr.write(motivo);
  process.exit(2);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.stderr.write('[gate-turno-prometido] AVISO: payload ilegível, liberando\n');
    process.exit(0);
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  if (!ev.cwd) process.exit(0);

  // Apenas janela principal
  if (ev.agent_id) process.exit(0);

  // Anti-loop: já barrou uma vez neste turno
  if (ev.stop_hook_active === true) process.exit(0);

  // Checa se o gate está ligado
  try {
    if (!require('./lib/config.cjs').ligado('gate-turno-prometido', { projeto: ev.cwd })) {
      process.exit(0);
    }
  } catch {
    // Erro ao ler config: assume ligado (falha fechada)
  }

  // Lê a transcrição
  let transcricao;
  try {
    if (!ev.transcript_path || !fs.existsSync(ev.transcript_path)) {
      process.stderr.write('[gate-turno-prometido] AVISO: transcript_path ausente ou inacessível\n');
      process.exit(0);
    }
    const conteudo = fs.readFileSync(ev.transcript_path, 'utf8').trim();
    transcricao = conteudo ? conteudo.split(/\r?\n/).filter(Boolean) : [];
  } catch (e) {
    process.stderr.write(`[gate-turno-prometido] AVISO: erro ao ler transcrição: ${e.message}\n`);
    process.exit(0);
  }

  if (!Array.isArray(transcricao) || transcricao.length === 0) {
    process.exit(0);
  }

  try {
    // Parseia cada linha
    const linhas = transcricao.map((l, idx) => {
      try {
        return JSON.parse(l);
      } catch {
        return null;
      }
    }).filter(Boolean);

    // Encontra a fronteira do turno: a última linha `user` que não seja `tool_result`
    let indiceInicioTurno = -1;
    for (let i = linhas.length - 1; i >= 0; i--) {
      const linha = linhas[i];
      if (linha.type === 'user' && linha.isSidechain !== true) {
        // É um user que não é sidechain
        let ehToolResult = false;
        if (linha.message && typeof linha.message === 'object') {
          const content = linha.message.content;
          if (typeof content === 'string') {
            // content é string, não é tool_result
            ehToolResult = false;
          } else if (Array.isArray(content)) {
            // Confere se é array sem tool_result
            ehToolResult = content.some(c => c && c.type === 'tool_result');
          }
        }
        if (!ehToolResult) {
          indiceInicioTurno = i;
          break;
        }
      }
    }

    if (indiceInicioTurno === -1) {
      // Nenhuma linha user encontrada ou todas são tool_result
      process.exit(0);
    }

    // Extrai o turno: linhas depois da fronteira, excluindo sidechains
    const turno = linhas.slice(indiceInicioTurno + 1).filter(l => l.isSidechain !== true);

    if (turno.length === 0) {
      process.exit(0);
    }

    // Extrai o último bloco `text` e todos os `tool_use` do turno
    let ultimoText = null;
    const toolUses = [];

    for (const linha of turno) {
      if (linha.type === 'assistant' && linha.message && linha.message.content) {
        const content = linha.message.content;
        if (Array.isArray(content)) {
          for (const bloco of content) {
            if (bloco && bloco.type === 'text' && bloco.text) {
              ultimoText = bloco.text;
            }
            if (bloco && bloco.type === 'tool_use' && bloco.name) {
              toolUses.push(bloco);
            }
          }
        } else if (typeof content === 'string') {
          ultimoText = content;
        }
      }
    }

    if (!ultimoText) {
      process.exit(0);
    }

    // Normaliza o texto: remove blocos de código, código inline, citações e linhas de lista
    function normalizarTexto(texto) {
      // Remove blocos de código (```...```)
      let normalizado = texto.replace(/```[\s\S]*?```/g, '');
      // Remove código inline (`...`)
      // Sem atravessar linha: crase solta num parágrafo não engole o seguinte.
      normalizado = normalizado.replace(/`[^`\n]*`/g, '');
      // Remove trechos entre aspas duplas ("...")
      normalizado = normalizado.replace(/"[^"\n]*"/g, '');
      // Remove linhas de lista (^\s*([-*]|\d+\.)\s)
      normalizado = normalizado.replace(/^\s*[-*]\s+.*$/gm, '');
      normalizado = normalizado.replace(/^\s*\d+\.\s+.*$/gm, '');
      // Negação ("não vou despachar") é recusa, não promessa.
      normalizado = normalizado.replace(/\bn[ãa]o\s+(vou despachar|vou disparar|estou despachando)\b/gi, '');
      return normalizado;
    }

    const textoNormalizado = normalizarTexto(ultimoText);

    // Constantes de regex para despacho (com \b nas bordas)
    const RE_PROMETE_DESPACHO = /\b(vou despachar|despachando|disparo agora|vou disparar)\b/i;
    const RE_PROMETE_ESPERA_MAQUINA = /\b(CI rodando|aguardando (o|a) (CI|build))\b/i;

    // Verifica se o texto normalizado promete despacho
    const matchDespacho = textoNormalizado.match(RE_PROMETE_DESPACHO);
    const prometeDespacho = matchDespacho !== null;

    // Verifica se o texto normalizado promete espera de máquina
    const matchEsperaMaquina = textoNormalizado.match(RE_PROMETE_ESPERA_MAQUINA);
    const prometeEsperaMaquina = matchEsperaMaquina !== null;

    // Caso (a): promete despacho mas não tem Agent/Task/SendMessage/Workflow
    if (prometeDespacho) {
      const temAgent = toolUses.some(t => t.name === 'Agent');
      const temTask = toolUses.some(t => t.name === 'Task');
      const temSendMessage = toolUses.some(t => t.name === 'SendMessage');
      const temWorkflow = toolUses.some(t => t.name === 'Workflow');
      if (!temAgent && !temTask && !temSendMessage && !temWorkflow) {
        bloqueia(
          `BLOQUEADO pelo gate de turno prometido do rainforest-mind.\n\n` +
          `Razão: você prometeu despachar no texto ("${matchDespacho[0]}"),\n` +
          `mas não despachava nada neste turno. Se queria despachar agora, despacha; se não, diz de quem é a bola.\n\n` +
          `O que fazer:\n` +
          `  1. Despacha agora: use a ferramenta Agent, Task, SendMessage ou Workflow.\n` +
          `  2. Não despacha: corrige a resposta para não prometer despacho.\n` +
          `  3. Desliga o gate se souber que é falso positivo: node scripts/setup.cjs --desligar gate-turno-prometido\n`
        );
      }
    }

    // Caso (b): promete espera de máquina mas não tem vigia
    if (prometeEsperaMaquina) {
      const temBashBackground = toolUses.some(t => t.name === 'Bash' && t.input && t.input.run_in_background === true);
      const temPowershellBackground = toolUses.some(t => t.name === 'PowerShell' && t.input && t.input.run_in_background === true);
      const temMonitor = toolUses.some(t => t.name === 'Monitor');
      const temScheduleWakeup = toolUses.some(t => t.name === 'ScheduleWakeup');
      if (!temBashBackground && !temPowershellBackground && !temMonitor && !temScheduleWakeup) {
        bloqueia(
          `BLOQUEADO pelo gate de turno prometido do rainforest-mind.\n\n` +
          `Razão: você disse que está aguardando máquina ("${matchEsperaMaquina[0]}"),\n` +
          `mas não configurou nenhuma vigia. O turno vai encerrar e você não vai ser despertado.\n\n` +
          `O que fazer:\n` +
          `  1. Vigiar agora: use Bash ou PowerShell com run_in_background, Monitor ou ScheduleWakeup.\n` +
          `  2. Não vigiar: diz que não precisa mais esperar (muda a resposta).\n` +
          `  3. Desliga o gate: node scripts/setup.cjs --desligar gate-turno-prometido\n`
        );
      }
    }

    process.exit(0);
  } catch (e) {
    process.stderr.write(`[gate-turno-prometido] AVISO: erro ao analisar transcrição: ${e.message}\n`);
    process.exit(0);
  }
}

if (require.main === module) main();
