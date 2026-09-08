#!/usr/bin/env node
/**
 * Stop — review gate opt-in via Codex na resposta do Claude.
 *
 * Tarefa 7 do plano 2026-09-08-agentes-em-codex (D9): quando o `Stop` é
 * acionado (encerramento manual ou timeout), este hook lê a última mensagem
 * do turno e pede ao `revisor` em Codex que a valide. Bloqueio é opt-in:
 * `gate-review-codex` desligado → libera; ligado → consulta Codex.
 *
 * Fluxo:
 * 1. Lê payload do stdin (evento do harness com session_id, transcript_path, etc)
 * 2. Qualquer exceção de parse → exit 0 com aviso no stderr
 * 3. Checa se o gate está ligado (`ligado('gate-review-codex')`)
 * 4. Checa se é anti-loop (`stop_hook_active === true`)
 * 5. Lê transcript_path, extrai o texto da ÚLTIMA entrada assistant
 * 6. Monta briefing em arquivo temporário
 * 7. Chama `node scripts/despachar-codex.cjs --agente revisor ...`
 * 8. Interpreta primeira linha da saída:
 *    - `/^ALLOW\b/i` → libera (exit 0, sem decisão)
 *    - `/^BLOCK\b/i` → bloqueia com motivo
 *    - Qualquer outra coisa → falha fechada (bloqueia com motivo genérico)
 * 9. Apaga arquivo temporário
 *
 * Falha fechada (D9): erros no despacho, timeout, ou saída irreconhecível
 * resultam em bloqueio, não em liberação. A premissa é que o revisão é mais
 * segura que a ausência dela.
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');

function lerEvento() {
  try {
    const input = fs.readFileSync(0, 'utf8');
    return JSON.parse(input);
  } catch (e) {
    // Parse error — exit 0 com aviso no stderr
    process.stderr.write(`[gate-review-codex] AVISO: payload ilegível, liberando: ${e.message}\n`);
    process.exit(0);
  }
}

/** Lê a última entrada de tipo "assistant" do transcript JSONL. */
function lerUltimaResposta(caminhoTranscrito) {
  try {
    if (!fs.existsSync(caminhoTranscrito)) {
      return null;
    }
    const conteudo = fs.readFileSync(caminhoTranscrito, 'utf8').trim();
    if (!conteudo) {
      return null;
    }
    const linhas = conteudo.split('\n');
    // Itera de trás pra frente procurando por entrada assistant
    for (let i = linhas.length - 1; i >= 0; i--) {
      try {
        const entrada = JSON.parse(linhas[i]);
        if (entrada.type === 'assistant' && entrada.message && entrada.message.content) {
          // Concatena todos os textos de type === "text"
          const textos = entrada.message.content
            .filter(c => c && c.type === 'text' && c.text)
            .map(c => c.text)
            .join('\n');
          if (textos) {
            return textos;
          }
        }
      } catch {
        // Linha ilegível, continua
      }
    }
  } catch (e) {
    process.stderr.write(`[gate-review-codex] AVISO: erro ao ler transcript: ${e.message}\n`);
  }
  return null;
}

/** Monta o briefing em arquivo temporário. */
function montarBriefing(textoResposta) {
  const briefing = `# Review Gate do rainforest-mind

## Contexto
Este é o gate de review automatizado do rainforest-mind. Uma sessão do Claude está
sendo encerrada, e a última resposta do assistente será validada pelo \`revisor\` em Codex.

## Resposta do Claude

===== INÍCIO =====
${textoResposta}
===== FIM =====

## Instrução de Contrato

Responda na PRIMEIRA linha exatamente:
- \`ALLOW: <motivo curto>\` para liberar o encerramento
- \`BLOCK: <motivo curto>\` para bloquear

Bloqueie APENAS para:
- Erro factual verificável (afirmação incorreta, cálculo errado)
- Promessa não cumprida no próprio texto (prometeu fazer X mas não fez)
- Ação irreversível sem confirmação explícita do usuário

Sem certeza, responda \`ALLOW\`.
`;
  const tmp = path.join(os.tmpdir(), `rfm-review-${Date.now()}-${Math.random().toString(36).slice(2)}.md`);
  fs.writeFileSync(tmp, briefing, 'utf8');
  return tmp;
}

/** Bloqueia o turno com motivo JSON. */
function bloqueia(motivo) {
  const decision = { decision: 'block', reason: motivo };
  process.stdout.write(JSON.stringify(decision) + '\n');
  process.exit(0);
}

function main() {
  const ev = lerEvento();

  // Checa se o gate está ligado
  try {
    if (!require('./lib/config.cjs').ligado('gate-review-codex', { projeto: ev.cwd || process.cwd() })) {
      // Desligado → libera silenciosamente
      process.exit(0);
    }
  } catch (e) {
    // Erro ao ler config → assume ligado (falha fechada)
    process.stderr.write(`[gate-review-codex] AVISO: erro ao ler config: ${e.message}, assumindo ligado\n`);
  }

  // Anti-loop: se já bloqueamos uma vez neste turno, deixa passar
  if (ev.stop_hook_active === true) {
    process.exit(0);
  }

  // Lê o transcript e extrai o texto
  const caminhoTranscrito = ev.transcript_path;
  if (!caminhoTranscrito) {
    process.stderr.write(`[gate-review-codex] AVISO: transcript_path ausente, liberando\n`);
    process.exit(0);
  }

  const textoResposta = lerUltimaResposta(caminhoTranscrito);
  if (!textoResposta) {
    process.stderr.write(`[gate-review-codex] AVISO: não conseguiu ler a última resposta do transcript, liberando\n`);
    process.exit(0);
  }

  // Monta briefing temporário
  const briefingFile = montarBriefing(textoResposta);

  try {
    // Resolve o CWD do despacho
    const cwd = ev.cwd || process.cwd();

    // Modo teste: se RFM_TEST=1 e CODEX_CMD está definido, usa o comando customizado
    // Senão, usa o comando padrão de despacho
    let cmd, args, resultado;

    if (process.env.RFM_TEST === '1' && process.env.RFM_DUBLE_SCRIPT) {
      // Modo teste: usa o dublê via variável de ambiente
      cmd = process.execPath;
      args = [process.env.RFM_DUBLE_SCRIPT];
      resultado = spawnSync(cmd, args, {
        input: `# Briefing para revisor\n\n${fs.readFileSync(briefingFile, 'utf8')}\n`,
        encoding: 'utf8',
        env: process.env,
        timeout: 600000 + 5000,
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } else {
      // Modo produção: chama despachar-codex.cjs
      cmd = process.execPath;
      args = [
        path.join(__dirname, '..', 'scripts', 'despachar-codex.cjs'),
        '--agente', 'revisor',
        '--worktree', cwd,
        '--escreve', 'false',
        '--briefing-file', briefingFile,
        '--timeout-ms', '600000',
      ];

      resultado = spawnSync(cmd, args, {
        encoding: 'utf8',
        env: process.env,
        timeout: 600000 + 5000, // 5s de margem
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    }

    // Interpreta a saída
    let parecer = '';
    if (resultado.status === 0 && resultado.stdout) {
      parecer = resultado.stdout.trim().split('\n')[0];
    }

    // Checa se é ALLOW
    if (/^ALLOW\b/i.test(parecer)) {
      // Libera silenciosamente
      process.exit(0);
    }

    // Checa se é BLOCK
    if (/^BLOCK\b/i.test(parecer)) {
      const motivo = parecer.replace(/^BLOCK:\s*/i, '').trim() || 'bloqueado pelo revisor';
      bloqueia(`revisor em Codex: ${motivo}`);
    }

    // Qualquer outra coisa = falha fechada
    const motivo = resultado.status !== 0
      ? `exit ${resultado.status}`
      : resultado.error
        ? resultado.error.message
        : parecer
          ? `saída não reconhecida: "${parecer}"`
          : 'sem saída do revisor';

    bloqueia(`gate-review-codex: falha fechada — ${motivo}; desligue com node scripts/setup.cjs --desligar gate-review-codex`);
  } finally {
    // Apaga o arquivo temporário
    try {
      fs.unlinkSync(briefingFile);
    } catch {
      // Ignorar erro de deleção
    }
  }
}

if (require.main === module) {
  main();
}

module.exports = { lerUltimaResposta, montarBriefing };
