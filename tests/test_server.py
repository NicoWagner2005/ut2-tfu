import http.client
import os
import sys
import threading
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "app"))
os.environ["API_KEY"] = "clave-de-prueba"

import server  # noqa: E402


class PruebasDeLaAPI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        server.ITERACIONES = 1
        cls.httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        cls.puerto = cls.httpd.server_address[1]
        cls.hilo = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.hilo.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.hilo.join()

    def pedir(self, ruta, clave=None, metodo="GET"):
        conexion = http.client.HTTPConnection("127.0.0.1", self.puerto, timeout=2)
        encabezados = {"X-API-Key": clave} if clave is not None else {}
        conexion.request(metodo, ruta, headers=encabezados)
        respuesta = conexion.getresponse()
        cuerpo = respuesta.read().decode("utf-8")
        conexion.close()
        return respuesta.status, cuerpo

    def test_salud_exige_autenticacion(self):
        estado, _ = self.pedir("/salud")
        self.assertEqual(estado, 401)

        estado, cuerpo = self.pedir("/salud", "clave-de-prueba")
        self.assertEqual(estado, 200)
        self.assertIn('"estado": "ok"', cuerpo)

    def test_recetas_rechaza_acceso_sin_clave(self):
        estado, _ = self.pedir("/recetas")
        self.assertEqual(estado, 401)

    def test_recetas_acepta_clave_y_filtro_validos(self):
        estado, cuerpo = self.pedir("/recetas?q=italia&limite=2", "clave-de-prueba")
        self.assertEqual(estado, 200)
        self.assertIn('"cantidad": 2', cuerpo)

    def test_rechaza_parametro_desconocido(self):
        estado, cuerpo = self.pedir("/recetas?admin=true", "clave-de-prueba")
        self.assertEqual(estado, 400)
        self.assertIn("parametros no permitidos", cuerpo)

    def test_rechaza_limite_fuera_de_rango(self):
        estado, _ = self.pedir("/recetas?limite=999", "clave-de-prueba")
        self.assertEqual(estado, 400)

    def test_rechaza_parametro_repetido(self):
        estado, _ = self.pedir("/recetas?q=a&q=b", "clave-de-prueba")
        self.assertEqual(estado, 400)

    def test_rechaza_utf8_mal_formado(self):
        estado, _ = self.pedir("/recetas?q=%FF", "clave-de-prueba")
        self.assertEqual(estado, 400)

    def test_acepta_busqueda_de_100_caracteres(self):
        estado, _ = self.pedir("/recetas?q=" + "a" * 100, "clave-de-prueba")
        self.assertEqual(estado, 200)

    def test_rechaza_busqueda_de_101_caracteres(self):
        estado, cuerpo = self.pedir("/recetas?q=" + "a" * 101, "clave-de-prueba")
        self.assertEqual(estado, 400)
        self.assertIn("hasta 100 caracteres", cuerpo)

    def test_rechaza_metodos_de_escritura(self):
        estado, _ = self.pedir("/recetas", "clave-de-prueba", metodo="POST")
        self.assertEqual(estado, 405)


if __name__ == "__main__":
    unittest.main()
