#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
API_KEY="${API_KEY:-tfu-demo-key}"
URL="${URL:-http://localhost:8080}"
export API_KEY URL

printf 'DEMO — MANTENER MÚLTIPLES COPIAS DEL CÓMPUTO\n'
printf '%s\n' '================================================================'
printf 'ETAPA 1: MOSTRAR EL REPARTO DE PEDIDOS\n\n'
printf 'Se enviarán 12 pedidos al único punto de entrada:\n'
printf "curl -H 'X-API-Key: %s' '%s/recetas?limite=1'\n\n" "$API_KEY" "$URL"

intento=1
while [ "$intento" -le 12 ]; do
    curl --fail --silent \
        -H "X-API-Key: $API_KEY" \
        "$URL/recetas?limite=1" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["atendido_por"])'
    intento=$((intento + 1))
done | sort | uniq -c

printf '\nEVIDENCIA: nginx distribuyó los pedidos entre api1, api2 y api3.\n'
printf '\n%s\n' '================================================================'
printf 'ETAPA 2: COMPARAR EL EFECTO SOBRE EL RENDIMIENTO\n\n'
printf 'Se ejecutará exactamente la misma carga en dos escenarios:\n'
printf '  A. Todos los pedidos dirigidos solamente a api1.\n'
printf '  B. Pedidos repartidos entre api1, api2 y api3.\n\n'

python3 scripts/medir-rendimiento.py

printf '\n%s\n' '================================================================'
printf 'CONCLUSIÓN\n'
printf 'El reparto demuestra cómo funciona la táctica.\n'
printf 'La comparación 1 vs. 3 demuestra su impacto sobre el rendimiento.\n'
