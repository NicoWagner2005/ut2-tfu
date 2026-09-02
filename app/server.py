"""API REST de recetas usada para demostrar tacticas de arquitectura.

Rendimiento: el servicio sin estado se ejecuta en multiples copias.
Seguridad: /recetas exige una clave de API y valida toda entrada antes de
realizar el computo costoso.
"""

import hashlib
import hmac
import json
import os
import re
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

PORT = int(os.environ.get("PORT", "3000"))
INSTANCE_ID = os.environ.get("INSTANCE_ID", "desconocida")
API_KEY = os.environ.get("API_KEY", "")

# Costo artificial de CPU por pedido (~100 ms). Sin este costo una sola copia
# alcanza para todo el trafico y la tactica no seria medible.
ITERACIONES = int(os.environ.get("WORK_ITERATIONS", "450000"))

MAX_REQUEST_TARGET = 512
MAX_BUSQUEDA = 100
MAX_RESULTADOS = 20
PARAMETROS_PERMITIDOS = {"q", "limite"}
PORCENTAJE_INVALIDO = re.compile(r"%(?![0-9a-fA-F]{2})")
CARACTER_DE_CONTROL = re.compile(r"[\x00-\x1f\x7f]")

with Path(__file__).with_name("recipes.json").open(encoding="utf-8") as f:
    RECETAS = json.load(f)["recetas"]


class EntradaInvalida(ValueError):
    """Entrada del cliente que no cumple el contrato de la API."""


def computo_costoso():
    """Trabajo ligado a CPU que permite medir el efecto de las copias."""
    dato = INSTANCE_ID.encode()
    for _ in range(ITERACIONES):
        dato = hashlib.sha256(dato).digest()
    return dato.hex()[:8]


def validar_consulta(request_target):
    """Acepta solamente q y limite, con tipo, cantidad y longitud acotados."""
    if len(request_target) > MAX_REQUEST_TARGET:
        raise EntradaInvalida("la URL supera el largo maximo permitido")
    if PORCENTAJE_INVALIDO.search(request_target):
        raise EntradaInvalida("la URL contiene una codificacion invalida")

    partes = urlsplit(request_target)
    if partes.scheme or partes.netloc or partes.fragment:
        raise EntradaInvalida("el formato de la URL no esta permitido")
    if partes.path != "/recetas":
        raise EntradaInvalida("ruta invalida")

    try:
        parametros = parse_qs(
            partes.query,
            keep_blank_values=True,
            strict_parsing=True,
            errors="strict",
            max_num_fields=len(PARAMETROS_PERMITIDOS),
        )
    except (ValueError, UnicodeError) as error:
        raise EntradaInvalida("consulta mal formada") from error

    desconocidos = set(parametros) - PARAMETROS_PERMITIDOS
    if desconocidos:
        raise EntradaInvalida(
            "parametros no permitidos: " + ", ".join(sorted(desconocidos))
        )
    if any(len(valores) != 1 for valores in parametros.values()):
        raise EntradaInvalida("cada parametro puede aparecer una sola vez")

    busqueda = None
    if "q" in parametros:
        busqueda = unicodedata.normalize("NFKC", parametros["q"][0]).strip()
        if not busqueda:
            raise EntradaInvalida("q no puede estar vacio")
        if len(busqueda) > MAX_BUSQUEDA:
            raise EntradaInvalida(f"q admite hasta {MAX_BUSQUEDA} caracteres")
        if CARACTER_DE_CONTROL.search(busqueda):
            raise EntradaInvalida("q contiene caracteres no permitidos")

    limite = MAX_RESULTADOS
    if "limite" in parametros:
        texto_limite = parametros["limite"][0]
        if not texto_limite.isascii() or not texto_limite.isdecimal():
            raise EntradaInvalida("limite debe ser un numero entero")
        limite = int(texto_limite)
        if not 1 <= limite <= MAX_RESULTADOS:
            raise EntradaInvalida(f"limite debe estar entre 1 y {MAX_RESULTADOS}")

    return busqueda, limite


def filtrar_recetas(busqueda, limite):
    if busqueda is None:
        return RECETAS[:limite]

    termino = busqueda.casefold()
    resultado = []
    for receta in RECETAS:
        campos = (
            receta["nombre"],
            receta["categoria"],
            receta["cocina"],
            *receta.get("tags", []),
        )
        if any(termino in str(campo).casefold() for campo in campos):
            resultado.append(receta)
            if len(resultado) == limite:
                break
    return resultado


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _responder(self, codigo, cuerpo, encabezados=None):
        datos = json.dumps(cuerpo, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(datos)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for nombre, valor in (encabezados or {}).items():
            self.send_header(nombre, valor)
        self.end_headers()
        self.wfile.write(datos)

    def _tiene_acceso(self):
        clave_recibida = self.headers.get("X-API-Key", "")
        if not API_KEY:
            return False
        # Se comparan hashes de igual largo, incluso si el atacante envia una
        # clave de longitud diferente.
        recibida = hashlib.sha256(clave_recibida.encode("utf-8")).digest()
        esperada = hashlib.sha256(API_KEY.encode("utf-8")).digest()
        return hmac.compare_digest(recibida, esperada)

    def do_GET(self):
        partes = urlsplit(self.path)

        # La autenticacion se aplica antes de permitir cualquier solicitud,
        # incluso antes de resolver la ruta pedida.
        if not self._tiene_acceso():
            self._responder(
                401,
                {"error": "acceso no autorizado"},
                {"WWW-Authenticate": 'ApiKey realm="recetas"'},
            )
            return

        if partes.path == "/salud" and not partes.query:
            self._responder(200, {"estado": "ok", "instancia": INSTANCE_ID})
            return

        if partes.path != "/recetas":
            self._responder(
                404,
                {"error": "no encontrado", "rutas": ["/recetas", "/salud"]},
            )
            return

        try:
            busqueda, limite = validar_consulta(self.path)
        except EntradaInvalida as error:
            self._responder(400, {"error": "entrada invalida", "detalle": str(error)})
            return

        recetas = filtrar_recetas(busqueda, limite)
        huella = computo_costoso()
        self._responder(
            200,
            {
                "atendido_por": INSTANCE_ID,
                "huella_computo": huella,
                "cantidad": len(recetas),
                "recetas": recetas,
            },
        )

    def _metodo_no_permitido(self):
        self._responder(
            405,
            {"error": "metodo no permitido"},
            {"Allow": "GET"},
        )

    do_POST = _metodo_no_permitido
    do_PUT = _metodo_no_permitido
    do_PATCH = _metodo_no_permitido
    do_DELETE = _metodo_no_permitido

    def log_message(self, *args):
        pass  # El log de reparto lo lleva nginx.


if __name__ == "__main__":
    if not API_KEY:
        raise SystemExit("API_KEY es obligatoria")
    print(
        f"[{INSTANCE_ID}] escuchando en :{PORT} "
        f"({ITERACIONES} iteraciones por pedido)",
        flush=True,
    )
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
