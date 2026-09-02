# Parte 1 — Requerimientos no funcionales

## 1. Rendimiento

**Requerimiento no funcional:** El sistema debe ser capaz de soportar 100.000
peticiones concurrentes.

**Táctica seleccionada:** Mantener múltiples copias del cómputo.

**Explicación:** Mantener múltiples copias del servicio permite distribuir las
peticiones concurrentes entre distintas unidades de cómputo mediante un
balanceador de carga. De esta forma, las solicitudes pueden procesarse en
paralelo, se reduce la espera en cola de cada petición y aumenta la capacidad
total del sistema. Como el servicio es sin estado, se pueden agregar nuevas
copias horizontalmente hasta alcanzar la capacidad requerida.

La demo permite observar el efecto de esta táctica comparando una copia con
tres copias bajo la misma carga. La cifra de 100.000 peticiones concurrentes es
un criterio cuantitativo de aceptación: en un entorno productivo sería
necesario dimensionar la cantidad de réplicas, la capacidad del balanceador y
la infraestructura, y luego verificar el resultado mediante una prueba de
carga de esa magnitud. La demo demuestra el mecanismo de escalado, pero tres
contenedores locales no certifican por sí solos que se alcance esa cifra.

## 2. Seguridad — Validar la entrada

**Requerimiento no funcional:** El sistema debe asegurarse que las entradas
del usuario no sobrepasen una longitud de 100 caracteres.

**Táctica seleccionada:** Validar la entrada.

**Explicación:** La aplicación valida los datos en el límite de confianza,
antes de realizar el cómputo solicitado. El parámetro de búsqueda `q` admite
como máximo 100 caracteres; cuando la entrada supera esa longitud, la API la
rechaza con HTTP 400. También se verifican el tipo, el rango, la codificación,
los parámetros permitidos y que no existan parámetros repetidos. Esto evita
que datos fuera del contrato ingresen al procesamiento del sistema y reduce el
consumo abusivo de recursos.

## 3. Seguridad — Limitar el acceso

**Requerimiento no funcional:** El sistema debe autenticar al usuario antes de
permitirle hacer solicitudes.

**Táctica seleccionada:** Limitar el acceso.

**Explicación:** La restricción del acceso mediante la utilización de una
API-KEY fortalece la seguridad del sistema, protegiendo la integridad del
estado y previniendo el acceso no autorizado de recursos.

En la implementación, todas las solicitudes requieren el encabezado
`X-API-Key`. La aplicación verifica la credencial antes de resolver la ruta,
validar sus parámetros o ejecutar el cómputo. Si la clave falta o es
incorrecta, responde HTTP 401 y detiene el procesamiento.
