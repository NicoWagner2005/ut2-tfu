# UT2 - Tacticas de arquitectura

API REST de recetas para demostrar una combinacion de tacticas de arquitectura:

1. **Mantener multiples copias del computo**, para rendimiento.
2. **Autorizar actores**, para seguridad (resistir ataques).
3. **Validar la entrada**, para seguridad (resistir ataques).

Los requerimientos no funcionales y la explicacion de como cada tactica los
satisface se encuentran en [`PARTE_1.md`](PARTE_1.md).

## Arquitectura

El servicio, deliberadamente sin estado, se ejecuta en tres copias identicas.
nginx expone un unico punto de entrada y reparte los pedidos en round-robin.

```text
                                      red interna de Docker
                                  +---------------------------+
                                  |  api1  [sin puerto host]  |
cliente --API key--> nginx :8080 -+  api2  [sin puerto host]  |
                                  |  api3  [sin puerto host]  |
                                  +---------------------------+
```

Las copias se definen una sola vez mediante un ancla YAML y solo cambia
`INSTANCE_ID`, utilizado para mostrar que instancia atendio cada pedido. El
catalogo es fijo y de solo lectura, por lo que no hay estado que sincronizar.

## Inicio rapido

Requisito general: Docker Desktop o Docker Engine con Compose. Los scripts de
macOS/Linux usan ademas `curl` y Python 3; los scripts de Windows usan
PowerShell y las bibliotecas .NET incluidas en el sistema.

macOS o Linux:

```bash
./scripts/iniciar.sh
```

Windows PowerShell:

```powershell
.\scripts\iniciar.ps1
```

Si la politica de ejecucion de Windows bloquea scripts locales, se puede usar
sin cambiar la configuracion global:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\iniciar.ps1
```

El script usa la clave didactica `tfu-demo-key`. Se puede elegir otra antes de
iniciar:

```bash
API_KEY='una-clave-distinta' ./scripts/iniciar.sh
```

En PowerShell:

```powershell
$env:API_KEY = "una-clave-distinta"
.\scripts\iniciar.ps1
```

Los scripts de demo deben ejecutarse con el mismo valor de `API_KEY`.

## API REST

### `GET /salud`

Endpoint liviano para verificar que la aplicacion esta disponible. Al igual
que el resto de la API, requiere autenticacion.

```bash
curl -s \
  -H 'X-API-Key: tfu-demo-key' \
  http://localhost:8080/salud \
  | python3 -m json.tool
```

### `GET /recetas`

Recurso protegido. Requiere `X-API-Key` y admite solamente estos parametros:

| Parametro | Regla |
|---|---|
| `q` | Busqueda opcional, no vacia, maximo 100 caracteres |
| `limite` | Entero opcional entre 1 y 20 |

```bash
curl -s \
  -H 'X-API-Key: tfu-demo-key' \
  'http://localhost:8080/recetas?q=italia&limite=2' \
  | python3 -m json.tool
```

## Demo completa

Con el entorno levantado, ejecutar en macOS o Linux:

```bash
./scripts/demo-multiples-copias.sh
./scripts/demo-seguridad.sh
```

El primer script muestra el reparto entre instancias y luego compara la misma
carga concurrente usando una copia y las tres copias. No requiere
ApacheBench: la medicion usa solamente Python. El segundo muestra cada peticion
antes de enviarla, el control que se espera aplicar, la respuesta y si llego a
ejecutarse el computo protegido.
La demo de seguridad se pausa entre casos de forma predeterminada. Para
ejecutarla completa sin pausas:

```bash
PAUSA=0 ./scripts/demo-seguridad.sh
```

En Windows PowerShell:

```powershell
.\scripts\demo-multiples-copias.ps1
.\scripts\demo-seguridad.ps1
```

La demo de seguridad tambien se pausa de forma predeterminada en Windows. Para
ejecutarla de corrido:

```powershell
.\scripts\demo-seguridad.ps1 -NoPause
```

## Tactica de rendimiento: multiples copias del computo

Cada pedido valido a `/recetas` realiza unas 450.000 iteraciones SHA-256. El
costo artificial hace visible el cuello de botella: una copia procesa un
pedido ligado a CPU por vez, mientras tres copias pueden atender pedidos en
paralelo. El balanceador evita que el cliente conozca la topologia.

Para observar el reparto:

```bash
docker compose logs nginx --tail 20
```

El script compara automaticamente dos rutas de demostracion:

```bash
# Misma carga y concurrencia contra 1 y 3 copias
./scripts/demo-multiples-copias.sh
```

`/demo/una-copia/recetas` dirige los pedidos solamente a `api1`, mientras
`/recetas` los reparte entre las tres copias. Ambas rutas llegan a la misma API,
mantienen la misma autenticacion, validacion y costo por pedido. La primera
existe exclusivamente para obtener una comparacion repetible sin modificar la
configuracion durante la exposicion.

Ejemplo de resultados obtenidos con 60 pedidos y concurrencia 6 (los valores
exactos dependen del equipo donde se ejecute Docker):

| Copias | Rendimiento | Latencia mediana | Latencia p95 |
|---:|---:|---:|---:|
| 1 | 10,79 req/s | 527 ms | 788 ms |
| 3 | 28,73 req/s | 202 ms | 319 ms |

La mejora proviene de reducir la espera en cola, no de acelerar un pedido
individual. Como efectos secundarios, se consumen mas recursos, los logs se
distribuyen y nginx se convierte en un punto unico de falla.

## Tactica de seguridad: autorizar actores

- Todas las solicitudes exigen una clave en el encabezado `X-API-Key`; si
  falta o es incorrecta responden `401` antes de resolver la ruta o ejecutar
  trabajo de negocio.
- La comparacion de la clave usa una operacion de tiempo constante.
- Las APIs no publican puertos al host y viven en una red interna. nginx es el
  unico servicio conectado tambien a la red de entrada y al puerto 8080.
- Los contenedores de la API usan filesystem de solo lectura, usuario sin
  privilegios, ninguna capability Linux y `no-new-privileges`.
- Solo se implementa lectura; los metodos de escritura responden `405`.

La clave incluida es exclusivamente para una demo local. En produccion se
inyectaria desde un gestor de secretos, se usaria TLS y se reemplazaria por un
mecanismo de identidad y autorizacion acorde al sistema.

## Tactica de seguridad: validar la entrada

La API procesa la entrada con una lista permitida. Rechaza con `400`:

- parametros desconocidos o repetidos;
- valores vacios, tipos incorrectos y limites fuera de rango;
- busquedas de mas de 100 caracteres o con caracteres de control;
- URLs demasiado largas o con codificacion porcentual mal formada.

La autorizacion y la validacion suceden antes del computo costoso. Esto reduce
la superficie de ataque y evita gastar CPU en pedidos que no cumplen el
contrato.

## Pruebas automatizadas

```bash
python3 -m unittest discover -s tests -v
docker compose config --quiet
```

## Archivos entregados

| Archivo | Rol |
|---|---|
| `PARTE_1.md` | Requerimientos no funcionales y justificacion de las tacticas |
| `app/server.py` | API, autenticacion, validacion y computo artificial |
| `app/recipes.json` | Catalogo fijo de recetas |
| `docker-compose.yml` | Tres copias, red interna y balanceador |
| `nginx.conf` | Punto de entrada y round-robin |
| `scripts/iniciar.sh` | Inicia y espera que la aplicacion este lista |
| `scripts/demo-multiples-copias.sh` | Demuestra la tactica de rendimiento |
| `scripts/medir-rendimiento.py` | Compara throughput y latencia con 1 y 3 copias |
| `scripts/demo-seguridad.sh` | Demuestra ambas tacticas de seguridad |
| `scripts/iniciar.ps1` | Inicio compatible con Windows PowerShell |
| `scripts/demo-multiples-copias.ps1` | Demo de rendimiento para Windows |
| `scripts/demo-seguridad.ps1` | Demo de seguridad para Windows |
| `tests/test_server.py` | Verifica acceso, validacion y contrato HTTP |

## Detener el entorno

```bash
docker compose down
```
