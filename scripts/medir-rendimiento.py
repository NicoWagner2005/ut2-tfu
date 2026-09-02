#!/usr/bin/env python3
"""Ejecuta la misma carga contra una y tres copias y compara resultados."""

import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

URL = os.environ.get("URL", "http://localhost:8080")
API_KEY = os.environ.get("API_KEY", "tfu-demo-key")
PEDIDOS = int(os.environ.get("PEDIDOS", "60"))
CONCURRENCIA = int(os.environ.get("CONCURRENCIA", "6"))


def pedir(url):
    inicio = time.perf_counter()
    pedido = urllib.request.Request(url, headers={"X-API-Key": API_KEY})
    try:
        with urllib.request.urlopen(pedido, timeout=30) as respuesta:
            cuerpo = json.load(respuesta)
            correcto = respuesta.status == 200 and "huella_computo" in cuerpo
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        correcto = False
    return time.perf_counter() - inicio, correcto


def percentil_95(valores):
    ordenados = sorted(valores)
    indice = max(0, int(0.95 * len(ordenados) + 0.999999) - 1)
    return ordenados[indice]


def medir(nombre, ruta):
    url = f"{URL}{ruta}"
    print(f"Midiendo {nombre}: {PEDIDOS} pedidos, concurrencia {CONCURRENCIA}...")
    inicio = time.perf_counter()
    with ThreadPoolExecutor(max_workers=CONCURRENCIA) as ejecutor:
        futuros = [ejecutor.submit(pedir, url) for _ in range(PEDIDOS)]
        resultados = [futuro.result() for futuro in as_completed(futuros)]
    duracion_total = time.perf_counter() - inicio

    latencias = [duracion for duracion, _ in resultados]
    correctos = sum(correcto for _, correcto in resultados)
    return {
        "nombre": nombre,
        "correctos": correctos,
        "req_s": PEDIDOS / duracion_total,
        "mediana_ms": statistics.median(latencias) * 1000,
        "p95_ms": percentil_95(latencias) * 1000,
    }


def main():
    if PEDIDOS < 1 or CONCURRENCIA < 1:
        raise SystemExit("PEDIDOS y CONCURRENCIA deben ser mayores que cero")

    resultados = [
        medir("1 copia", "/demo/una-copia/recetas?limite=1"),
        medir("3 copias", "/recetas?limite=1"),
    ]

    print()
    print("RESULTADOS — MISMA CARGA Y MISMO CÓMPUTO POR PEDIDO")
    print(f"{'Escenario':<12} {'Correctos':>10} {'req/s':>10} {'Mediana':>12} {'p95':>12}")
    print("-" * 60)
    for resultado in resultados:
        print(
            f"{resultado['nombre']:<12} "
            f"{resultado['correctos']:>3}/{PEDIDOS:<6} "
            f"{resultado['req_s']:>10.2f} "
            f"{resultado['mediana_ms']:>9.0f} ms "
            f"{resultado['p95_ms']:>9.0f} ms"
        )

    una, tres = resultados
    if una["correctos"] != PEDIDOS or tres["correctos"] != PEDIDOS:
        print("\nERROR: hubo pedidos fallidos; la comparación no es válida.", file=sys.stderr)
        return 1

    mejora = tres["req_s"] / una["req_s"]
    reduccion_p95 = una["p95_ms"] / tres["p95_ms"]
    print()
    print(f"Con 3 copias, el rendimiento fue {mejora:.2f} veces mayor.")
    print(f"La latencia p95 fue {reduccion_p95:.2f} veces menor.")
    print("La mejora viene del procesamiento paralelo y la menor espera en cola.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
