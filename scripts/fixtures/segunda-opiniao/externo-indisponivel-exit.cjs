#!/usr/bin/env node
/**
 * Fixture para segunda-opiniao: modelo externo indisponível — exit ≠ 0
 * Simula CLI externo ligado mas indisponível (ex.: modelo sobrecarregado, quota esgotada)
 * Sai com exit 1 e stderr não vazio
 * Caso de teste: externo-indisponivel-exit
 */

process.stderr.write('Error: API rate limit exceeded\n');
process.exit(1);
