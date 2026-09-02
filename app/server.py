"""
Servicio de recetas: devuelve un catalogo fijo leido de recipes.json.

Es una unidad de computo deliberadamente simple y SIN ESTADO: no guarda nada
entre pedidos, por lo que puede replicarse N veces sin coordinacion. Esa es la
precondicion de la tactica "mantener multiples copias del computo".

Cada respuesta incluye 'atendido_por' para poder demostrar que el balanceador
reparte el trabajo entre las copias.
"""

import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "3000"))
INSTANCE_ID = os.environ.get("INSTANCE_ID", "desconocida")

# Costo artificial de CPU por pedido (~100 ms). Sin este costo una sola copia
# alcanza para todo el trafico y la tactica no seria medible.
ITERACIONES = int(os.environ.get("WORK_ITERATIONS", "450000"))

with open("recipes.json", encoding="utf-8") as f:
    RECETAS = json.load(f)


def computo_costoso():
    """Trabajo ligado a CPU. hashlib no libera el GIL con entradas chicas, asi
    que cada copia procesa un pedido por vez: el cuello de botella es la
    cantidad de copias, no la cantidad de hilos."""
    dato = INSTANCE_ID.encode()
    for _ in range(ITERACIONES):
        dato = hashlib.sha256(dato).digest()
    return dato.hex()[:8]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _responder(self, codigo, cuerpo):
        datos = json.dumps(cuerpo, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(datos)))
        self.end_headers()
        self.wfile.write(datos)

    def do_GET(self):
        if self.path.startswith("/recetas"):
            huella = computo_costoso()
            self._responder(200, {
                "atendido_por": INSTANCE_ID,
                "huella_computo": huella,
                "recetas": RECETAS,
            })
        elif self.path == "/salud":
            self._responder(200, {"estado": "ok", "instancia": INSTANCE_ID})
        else:
            self._responder(404, {"error": "no encontrado", "rutas": ["/recetas", "/salud"]})

    def log_message(self, *args):
        pass  # el log de reparto lo lleva nginx


if __name__ == "__main__":
    print(f"[{INSTANCE_ID}] escuchando en :{PORT} ({ITERACIONES} iteraciones por pedido)", flush=True)
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
