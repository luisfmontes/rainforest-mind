#!/bin/bash
R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test what the shell sees
cmd_pattern="git commit -m \$'Fix\\'d bug' \$'--no-verify'"
echo "cmd_pattern in shell: $cmd_pattern"

# Show hex dump
echo "$cmd_pattern" | od -c

# Now pass to Node
node -e "
console.log('Received from bash:', process.argv[1]);
const bs = String.fromCharCode(92);
console.log('Backslash char (92):', bs);
console.log('Has backslash 92?', process.argv[1].includes(bs));
" "$cmd_pattern"
