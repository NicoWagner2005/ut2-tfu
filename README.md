# ut2-tfu

Demostracion de la tactica de rendimiento **"mantener multiples copias del computo"**
(Bass, Clements y Kazman, categoria *gestion de recursos*).

Un servicio de recetas se replica en 3 copias identicas detras de un balanceador
de carga nginx. El cliente ve un unico punto de entrada, `http://localhost:8080`,
y no sabe cuantas copias hay atras.

```
                    ┌─────────────┐
                    │    api1     │
  cliente ───▶ nginx├─────────────┤
  :8080             │    api2     │
                    ├─────────────┤
                    │    api3     │
                    └─────────────┘
```

## Archivos

| Archivo | Rol |
|---|---|
| `docker-compose.yml` | Despliega las 3 copias del computo y el balanceador |
| `nginx.conf` | Balanceador: define el `upstream` con las 3 copias (round-robin) |
| `app/server.py` | El servicio replicado. Sin estado, con un costo de CPU artificial |
| `app/recipes.json` | Catalogo fijo de recetas |

Las tres copias se definen con un **ancla de YAML** (`&copia-del-computo`) que
las tres reusan: son identicas por construccion y solo se diferencian en la
variable `INSTANCE_ID`, que sirve para saber cual atendio cada pedido.

## Como levantarlo

```bash
docker compose up -d
curl -s http://localhost:8080/recetas | python3 -m json.tool | head
```

```bash
docker compose logs nginx | tail   # que copia atendio y cuanto tardo
```

Endpoints: `GET /recetas` (con costo de computo) y `GET /salud` (sin costo).

## Como medir el efecto de la tactica

Cada pedido cuesta ~90 ms de CPU (`app/server.py`, constante `ITERACIONES`).
El costo es deliberado: sin el, una sola copia alcanzaria para todo el trafico
y la tactica no seria medible. Como `hashlib` no libera el GIL con entradas
chicas, **cada copia procesa un pedido por vez**: el cuello de botella es la
cantidad de copias.

**1. Medir con las 3 copias:**

```bash
ab -n 60 -c 6 http://localhost:8080/recetas
```

**2. Dejar una sola copia:** comentar `api2` y `api3` en el `upstream` de
`nginx.conf`, y luego:

```bash
docker compose restart nginx
ab -n 60 -c 6 http://localhost:8080/recetas
```

### Resultados medidos

| Copias del computo | Rendimiento (req/s) | Latencia mediana | Latencia p95 |
|---|---|---|---|
| 1 | 11,06 | 485 ms | 821 ms |
| 3 | 28,89 | 192 ms | 223 ms |

Con la misma carga (60 pedidos, 6 concurrentes), pasar de 1 a 3 copias
**multiplico por 2,6 el rendimiento y redujo la latencia p95 3,7 veces**.
La mejora no viene de que cada pedido se calcule mas rapido: cada pedido sigue
costando ~90 ms. Viene de que **se elimina el tiempo de espera en cola**, que es
exactamente lo que la tactica busca atacar.

## Analisis

**Impacto positivo.** Mayor capacidad de procesamiento en paralelo y menor
tiempo de encolado bajo trafico simultaneo. Como efecto secundario deseable, el
sistema tolera la caida de una copia: nginx deja de enviarle pedidos y las otras
siguen respondiendo. *Ojo:* eso ultimo es la tactica de disponibilidad
**redundancia activa**, que tiene la misma estructura pero otro objetivo. Lo que
se mide aca es rendimiento.

**Riesgos y efectos secundarios.**

- Mayor sobrecarga operativa: hay 3 nodos que desplegar, monitorear y observar
  en lugar de uno, y los logs quedan distribuidos.
- Aumento directo del costo de infraestructura, proporcional a la cantidad de
  copias.
- El balanceador pasa a ser un **punto unico de falla** y un posible cuello de
  botella: la tactica cambia el problema de lugar, no lo elimina.
- **La tactica solo rinde si hay recursos fisicos abajo.** Las 3 copias mejoran
  porque hay nucleos libres para usarlas. Si se limitara el CPU total al mismo
  valor, 3 copias rendirian practicamente igual que 1.
- Exige que el computo sea **sin estado**. Funciona aca porque las recetas son
  fijas y de solo lectura. Si las copias tuvieran que compartir estado mutable
  (por ejemplo un carrito), haria falta almacenamiento compartido, y ahi
  aparecen los problemas de consistencia de la tactica *mantener multiples
  copias de los datos*.

**En produccion** no se escribirian tres servicios a mano: se usaria
`deploy.replicas: N` o un orquestador. Se hizo explicito para que el
`upstream` de nginx muestre las copias y se puedan apagar de a una.

## Bajar el entorno

```bash
docker compose down
```
