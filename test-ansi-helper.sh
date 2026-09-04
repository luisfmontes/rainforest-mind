#!/bin/bash
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$SRC"  # Use current dir as test repo

# Função auxiliar para construir JSON com contrabarra em $'...'
# Recebe um comando e constrói um JSON com o comando EXATAMENTE como recebido
# Passa a string via stdin em heredoc para evitar interpretação dupla de shell
b_ansi() {
  local cmd_pattern="$1"
  node -e "
const bs = String.fromCharCode(92);
process.stdin.on('data', (cmdPattern) => {
  // Interpreta sequências de escape manualmente: backslash-quote vira barra+aspa
  const cmdStr = cmdPattern.toString().trim();
  let c = '';
  let i = 0;
  while (i < cmdStr.length) {
    if (cmdStr[i] === '\\\\' && i + 1 < cmdStr.length && cmdStr[i+1] === \"'\") {
      c += bs + \"'\";
      i += 2;
    } else {
      c += cmdStr[i];
      i += 1;
    }
  }
  console.log(JSON.stringify({
    session_id: 's1',
    cwd: '$R'.replace(/\\\\/g, '/'),
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: { command: c }
  }));
});
" <<< "$cmd_pattern"
}

echo "=== Test 1: git commit -m \$'Fix\\'d bug' \$'--no-verify' ==="
result=$(b_ansi "git commit -m \$'Fix\\'d bug' \$'--no-verify'")
echo "Full JSON:"
echo "$result" | node -e "const d = require('fs').readFileSync(0, 'utf8'); console.log(JSON.stringify(JSON.parse(d), null, 2));"
echo ""
echo "Extracted command:"
echo "$result" | node -e "const d = JSON.parse(require('fs').readFileSync(0, 'utf8')); console.log(JSON.stringify(d.tool_input.command));"
echo ""
echo "Command with escapes visible:"
echo "$result" | node -e "const d = JSON.parse(require('fs').readFileSync(0, 'utf8')); const cmd = d.tool_input.command; console.log('Has backslash?', cmd.includes('\\\\') ? 'YES' : 'NO'); console.log('Has dollar-quote?', cmd.includes(\"\\\$'\") ? 'YES' : 'NO');"
