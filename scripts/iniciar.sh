#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

export API_KEY="${API_KEY:-tfu-demo-key}"
docker compose up -d

printf 'Esperando que la API quede disponible'
intento=0
while ! curl --fail --silent \
    -H "X-API-Key: $API_KEY" \
    http://localhost:8080/salud >/dev/null; do
    intento=$((intento + 1))
    if [ "$intento" -ge 30 ]; then
        printf '\nLa API no respondio a tiempo. Revise: docker compose logs\n' >&2
        exit 1
    fi
    printf '.'
    sleep 1
done

printf '\nAPI lista en http://localhost:8080\n'
printf 'Clave de demostracion: %s\n' "$API_KEY"
