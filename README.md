# 🚗 Proyecto SQL: Análisis de Ventas de Coches (Cars Dataset 2025)

Proyecto de análisis de datos en **PostgreSQL** sobre el catálogo y las ventas del mercado del automóvil. El objetivo es transformar un dataset "en bruto" en un **modelo de datos dimensional** limpio y, a partir de él, responder preguntas de negocio mediante consultas SQL: qué marcas y modelos venden más, qué mercados generan más ingresos, cómo evolucionan las ventas en el tiempo, qué tecnologías de propulsión dominan, etc.

---

## 📊 Origen de los datos

Este proyecto combina dos fuentes de datos:

1. **Catálogo de coches** ([`csv/cars_dataset_2025.csv`](csv/cars_dataset_2025.csv))
   Dataset original descargado de Kaggle: [Cars Datasets 2025](https://www.kaggle.com/datasets/abdulmalik1518/cars-datasets-2025?resource=download). Contiene ~1.200 modelos de coches con sus características técnicas (marca, motor, potencia, velocidad máxima, aceleración, precio, tipo de combustible, asientos, par motor...).

2. **Registros de ventas** ([`csv/fact_sales.csv`](csv/fact_sales.csv))
   Dataset **generado a partir del anterior con la ayuda de Claude (Anthropic)**, simulando ~2.500 transacciones de venta reales (clientes, concesionarios, vendedores, fechas, precios, métodos de pago y países). Estos registros son los que alimentan la tabla de hechos **`fact_sales`**, el corazón del análisis.

---

## 🗂️ Modelo de datos

El proyecto sigue un **esquema en estrella (star schema)**: una tabla de hechos central rodeada de tablas de dimensión que describen el "quién, qué y cómo" de cada venta.

```
                ┌────────────────┐
                │   dim_marca     │
                └───────┬─────────┘
                        │
┌────────────────┐  ┌──┴───────────┐   ┌──────────────────┐
│ dim_combustible├──┤  dim_coche   │   │   dim_customer    │
└────────────────┘  └──────┬───────┘   └─────────┬─────────┘
                            │                     │
                     ┌──────┴─────────────────────┴───────┐
                     │            fact_sales               │
                     └──────┬─────────────────┬────────────┘
                            │                  │
                   ┌────────┴───────┐  ┌───────┴────────────┐
                   │   dim_dealer    │  │  dim_salesperson    │
                   └─────────────────┘  └─────────────────────┘
```

### Tabla de hechos

- **`fact_sales`**: una fila = una transacción de venta (fecha, cliente, concesionario, vendedor, coche, cantidad, precio unitario, precio total, método de pago y país).

### Tablas de dimensión

| Tabla | Descripción |
|---|---|
| `dim_marca` | Fabricantes de coches (Ferrari, Toyota, BMW...) |
| `dim_combustible` | Tipos de combustible normalizados (Petrol, Diesel, Electric, Hybrid...) |
| `dim_coche` | Catálogo de modelos con sus características técnicas y precio |
| `dim_customer` | Clientes que realizan las compras |
| `dim_dealer` | Concesionarios donde se realizan las ventas |
| `dim_salesperson` | Vendedores que gestionan cada transacción |

Además del modelo de tablas, el esquema incluye **vistas, una vista materializada, índices y una función** para facilitar el análisis recurrente:

- `v_ventas_por_marca` / `v_top_modelos`: agregados de ventas listos para consultar.
- `mv_resumen_anual`: resumen de ventas por año, precalculado para consultas rápidas.
- `fn_total_ventas_marca(marca)`: función que devuelve los ingresos totales de una marca.

---

## 🎯 Objetivo de las operaciones y métricas

El análisis (en [`sql/03_eda.sql`](sql/03_eda.sql)) se organiza en tres bloques:

### A. Validación y calidad de datos
Comprobación de que la carga es correcta, detección de nulos, duplicados y outliers de precio en el catálogo, y revisión de la distribución de tipos de combustible.

### B. EDA descriptivo
Estadísticas de precio, velocidad y aceleración por marca y combustible, evolución anual de las ventas y distribución por método de pago, para entender el catálogo y la base de ventas antes de sacar conclusiones.

### C. Consultas analíticas de negocio
Preguntas de negocio resueltas con SQL avanzado (JOINs, CTEs, subconsultas, funciones de ventana y transacciones):

- Modelos más vendidos e ingresos por marca/país.
- Ranking de marcas y dealers (`RANK()`, `DENSE_RANK()`).
- Cuota de mercado por tipo de combustible.
- Segmentación de coches por precio.
- Estacionalidad de las ventas por trimestre.
- Ingresos acumulados por marca a lo largo del tiempo.
- Modelos del catálogo sin ventas (oportunidades/descatalogación).
- Rendimiento de cada vendedor dentro de su concesionario.

---

## ⚙️ Stack y puesta en marcha

- **Motor**: PostgreSQL 16 (vía Docker).
- **Orquestación**: `docker-compose.yml` levanta un contenedor `postgres-cars` en el puerto `5433`.

```bash
# 1. Levantar la base de datos
docker compose up -d

# 2. Crear el modelo (tablas, vistas, índices, función)
psql -h localhost -p 5433 -U postgres -d cars_db -f sql/01_schema.sql

# 3. Cargar los datos
psql -h localhost -p 5433 -U postgres -d cars_db -f sql/02_data.sql

# 4. Ejecutar el análisis exploratorio
psql -h localhost -p 5433 -U postgres -d cars_db -f sql/03_eda.sql
```

---

## 📁 Estructura del repositorio

```
proyecto_sql/
├── csv/
│   ├── cars_dataset_2025.csv   # Catálogo original (Kaggle)
│   └── fact_sales.csv          # Ventas generadas con Claude
├── sql/
│   ├── 01_schema.sql           # Creación del modelo dimensional
│   ├── 02_data.sql             # Carga y limpieza de datos
│   └── 03_eda.sql              # Análisis exploratorio y consultas de negocio
└── docker-compose.yml          # PostgreSQL en Docker
```
