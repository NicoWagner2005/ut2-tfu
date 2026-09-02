#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
API_KEY="${API_KEY:-tfu-demo-key}"
URL="${URL:-http://localhost:8080}"
PAUSA="${PAUSA:-1}"
Q_LARGA="$(python3 -c 'print("a" * 101)')"

separador() {
    printf '\n%s\n' '================================================================'
}

esperar() {
    if [ "$PAUSA" = "1" ] && [ -t 0 ]; then
        printf '\nPresione Enter para continuar...'
        read -r _
    fi
}

mostrar_respuesta() {
    codigo="$1"
    archivo="$2"

    printf '\nRESPUESTA\n'
    printf 'HTTP %s\n' "$codigo"
    python3 - "$archivo" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as archivo:
    cuerpo = json.load(archivo)

# En los casos exitosos se resume el catalogo para que la evidencia importante
# entre en pantalla. Los errores se muestran completos.
if "recetas" in cuerpo:
    cuerpo["recetas"] = [receta["nombre"] for receta in cuerpo["recetas"]]

print(json.dumps(cuerpo, ensure_ascii=False, indent=2))
print()
if "huella_computo" in cuerpo:
    print("EVIDENCIA: hay huella_computo -> el cómputo protegido SÍ se ejecutó.")
else:
    print("EVIDENCIA: no hay huella_computo -> el cómputo protegido NO se ejecutó.")
PY
}

probar() {
    titulo="$1"
    peticion_visible="$2"
    resultado_esperado="$3"
    shift 3

    separador
    printf '%s\n\n' "$titulo"
    printf 'PETICIÓN ENVIADA\n'
    printf '%s\n' "$peticion_visible"
    printf '\nCONTROL ESPERADO\n%s\n' "$resultado_esperado"

    archivo="$(mktemp)"
    codigo="$(curl --silent --output "$archivo" --write-out '%{http_code}' "$@")"
    mostrar_respuesta "$codigo" "$archivo"
    rm -f "$archivo"
    esperar
}

printf 'DEMO DE TÁCTICAS DE SEGURIDAD\n'
printf 'Recurso protegido: GET /recetas\n'
printf 'La huella_computo solamente existe si el pedido supera los controles.\n'

separador
printf 'TÁCTICA 1 — AUTORIZAR ACTORES\n'
printf 'Se mantiene igual el recurso solicitado y se cambia la credencial.\n'

probar \
    'Caso 1.1 — Sin credencial' \
    "curl '$URL/recetas?limite=1'" \
    'La API debe impedir el acceso con HTTP 401.' \
    "$URL/recetas?limite=1"

probar \
    'Caso 1.2 — Credencial incorrecta' \
    "curl -H 'X-API-Key: incorrecta' '$URL/recetas?limite=1'" \
    'La API debe impedir el acceso con HTTP 401.' \
    -H 'X-API-Key: incorrecta' \
    "$URL/recetas?limite=1"

probar \
    'Caso 1.3 — Credencial válida' \
    "curl -H 'X-API-Key: $API_KEY' '$URL/recetas?limite=1'" \
    'La API debe permitir el acceso y ejecutar el cómputo.' \
    -H "X-API-Key: $API_KEY" \
    "$URL/recetas?limite=1"

separador
printf 'TÁCTICA 2 — VALIDAR LA ENTRADA\n'
printf 'Todos los pedidos tienen una credencial válida; ahora cambia la entrada.\n'

probar \
    'Caso 2.1 — Entrada de 101 caracteres' \
    "curl -H 'X-API-Key: $API_KEY' '$URL/recetas?q=$Q_LARGA'" \
    'q admite hasta 100 caracteres: debe responder HTTP 400.' \
    -H "X-API-Key: $API_KEY" \
    "$URL/recetas?q=$Q_LARGA"

probar \
    'Caso 2.2 — Número fuera del rango permitido' \
    "curl -H 'X-API-Key: $API_KEY' '$URL/recetas?limite=999'" \
    'limite admite solamente enteros entre 1 y 20: debe responder HTTP 400.' \
    -H "X-API-Key: $API_KEY" \
    "$URL/recetas?limite=999"

probar \
    'Caso 2.3 — Parámetro que no pertenece al contrato' \
    "curl -H 'X-API-Key: $API_KEY' '$URL/recetas?admin=true'" \
    'admin no está en la lista permitida: debe responder HTTP 400.' \
    -H "X-API-Key: $API_KEY" \
    "$URL/recetas?admin=true"

probar \
    'Caso 2.4 — Entrada válida' \
    "curl -H 'X-API-Key: $API_KEY' '$URL/recetas?q=vegetariano&limite=2'" \
    'q y limite cumplen el contrato: debe responder HTTP 200.' \
    -H "X-API-Key: $API_KEY" \
    "$URL/recetas?q=vegetariano&limite=2"

separador
printf 'CONCLUSIÓN\n'
printf '• Autorizar actores detuvo los pedidos sin una credencial válida.\n'
printf '• Validar entrada detuvo valores y parámetros fuera del contrato.\n'
printf '• Solo los pedidos autorizados y válidos generaron huella_computo.\n'
