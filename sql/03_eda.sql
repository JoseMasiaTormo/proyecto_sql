-- =============================================================>

-- Proyecto Análisis de Ventas de Coches (Cars Dataset 2025)
-- Descripción: Análisis Exploratorio de Datos (EDA) completo.
-- Incluye limpieza adicional, estadisticas descriptivas y 
-- consultas analíticas de negocio con insights documentados.
--
-- ESTRUCTURA:
--   A: Validación y calidad de datos.
--   B: EDA descriptivo (entender los datos).
--	 C: Consultas analíticas de negocio (insights).

-- =============================================================>

-- ===================================>
-- A. VALIDACIÓN Y CALIDAD DE DATOS
-- ===================================>

-- -------------------------------------------------------------
-- A1. Conteo general de registros por tabla
-- Comprobamos que la carga fue correcta y no falta nada.
-- -------------------------------------------------------------

SELECT 'dim_marca' AS tabla, COUNT(*) AS registros FROM dim_marca
UNION ALL
SELECT 'dim_combustible', COUNT(*) FROM dim_combustible
UNION ALL
SELECT 'dim_coche', COUNT(*) FROM dim_coche
UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL
SELECT 'dim_dealer', COUNT(*) FROM dim_dealer
UNION ALL
SELECT 'dim_salesperson', COUNT(*) FROM dim_salesperson
UNION ALL
SELECT 'fact_sales', COUNT(*) FROM fact_sales;

-- -------------------------------------------------------------
-- A2. Nulos por columna en dim_coche.
-- Identificamos que columnas técnicas tienen mayor tasa de nulos.
-- -------------------------------------------------------------

SELECT
	COUNT(*) AS total_coches,
	COUNT(*) FILTER (WHERE velocidad_max_kmh IS NULL) AS nulos_velocidad,
	COUNT(*) FILTER (WHERE aceleracion_0_100 IS NULL) AS nulos_aceleración,
	COUNT(*) FILTER (WHERE precio_usd IS NULL OR precio_usd = 0) AS nulos_precio,
	COUNT(*) FILTER (WHERE combustible_id IS NULL) AS nulos_combustible
FROM dim_coche;

-- -------------------------------------------------------------
-- A3. Duplicados en dim_coche (mismo marca + modelo)
-- Insight: si hay modelos repetidos es porque el CSV tenía
-- varias versiones/variantes del mismo nombre.
-- -------------------------------------------------------------

SELECT
	m.nombre AS marca,
	UPPER(TRIM(dc.modelo)) AS modelo,
	COUNT(*) AS veces
FROM dim_coche dc 
JOIN dim_marca m ON dc.marca_id = m.marca_id
GROUP BY m.nombre, UPPER(TRIM(dc.modelo))
HAVING COUNT(*) > 1
ORDER BY veces DESC
LIMIT 20;

-- En el anterior apartado se explica porque no se borran los duplicados.
-- Igualmente, no se borran porque fact_sales podría estar referenciadolos.
-- En un entorno de producción se haría una deduplicación antes de mostrar los datos.

-- -------------------------------------------------------------
-- A4. Outliers en precio: coches con precio > 1.000.000 $
-- Insight: identifica los supercoches y coches de lujo extremo.
-- -------------------------------------------------------------

SELECT 
	m.nombre AS marca,
	dc.modelo,
	dc.precio_usd 
FROM dim_coche dc
JOIN dim_marca m ON dc.marca_id = m.marca_id 
WHERE dc.precio_usd > 1000000
ORDER BY dc.precio_usd DESC;

-- -------------------------------------------------------------
-- A5. Distribución de tipos de combustible en el catálogo.
-- Insight: qué proporción del catálogo es eléctrico vs gasolina.
-- -------------------------------------------------------------

SELECT
	cb.tipo AS combustible,
	COUNT(dc.coche_id) AS num_modelos,
	ROUND(COUNT(dc.coche_id) * 100.0 / SUM(COUNT(dc.coche_id)) OVER (), 1) AS pct
FROM dim_coche dc
JOIN dim_combustible cb ON dc.combustible_id = cb.combustible_id
GROUP BY cb.tipo 
ORDER BY num_modelos DESC;

-- ===================================>
-- B. EDA DESCRIPTIVO
-- ===================================>

-- -------------------------------------------------------------
-- B1. Estadísticas descriptivas de precios por marca.
-- Insight: rangos de precio de cada fabricante (quien es premium
-- y quien es accesible).
-- -------------------------------------------------------------

SELECT 
	m.nombre AS marca,
	COUNT(dc.coche_id) AS num_modelos,
	ROUND(MIN(dc.precio_usd), 0) AS precio_min,
	ROUND(MAX(dc.precio_usd), 0) AS precio_max,
	ROUND(AVG(dc.precio_usd), 0) AS precio_medio
FROM dim_coche dc 
JOIN dim_marca m ON dc.marca_id = m.marca_id 
WHERE dc.precio_usd > 0
GROUP BY m.nombre
ORDER BY precio_medio DESC;

-- -------------------------------------------------------------
-- B2. Estadísticas de velocidad máxima por tipo de combustible
-- Insight: los coches eléctricos vs gasolina en rendimiento puro.
-- -------------------------------------------------------------

SELECT
	cb.tipo AS combustible,
	COUNT(dc.coche_id) AS num_modelos,
	ROUND(AVG(dc.velocidad_max_kmh), 1) AS velocidad_media,
	MAX(dc.velocidad_max_kmh) AS velocidad_max,
	ROUND(AVG(dc.aceleracion_0_100), 2) AS aceleracion_media_seg
FROM dim_coche dc
JOIN dim_combustible cb ON dc.combustible_id = cb.combustible_id
WHERE dc.velocidad_max_kmh IS NOT NULL AND dc.aceleracion_0_100 IS NOT NULL
GROUP BY cb.tipo 
ORDER BY aceleracion_media_seg ASC;

-- -------------------------------------------------------------
-- B3. Evolución de ventas por año (usando la vista materializada)
-- Insight: tendencia general del negocio 2020-2024.
-- -------------------------------------------------------------

REFRESH MATERIALIZED VIEW mv_resumen_anual;
SELECT * FROM mv_resumen_anual;

-- -------------------------------------------------------------
-- B4. Distribución de ventas por método de pago
-- Insight: qué método de pago prefieren los clientes.
-- -------------------------------------------------------------

SELECT
	payment_method,
	COUNT(*) AS num_ventas,
	ROUND(SUM(total_price), 2) AS ingresos,
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_ventas
FROM fact_sales
GROUP BY payment_method
ORDER BY num_ventas DESC;

-- ===================================>
-- C. COUNSULTAS ANALÍTICAS DE NEGOCIO
-- ===================================>

-- -------------------------------------------------------------
-- C1. Top 10 modelos más vendidos (por unidades)
-- Insight: qué modelos tienen mayor rotación en el mercado.
-- Usa JOIN entre fact_sales, dim_coche y dim_marca.
-- -------------------------------------------------------------

SELECT
	m.nombre AS marca,
	dc.modelo,
	SUM(fsa.quantity) AS unidades_vendidas,
	ROUND(SUM(fsa.total_price), 2) AS ingresos_totales
FROM fact_sales fsa
INNER JOIN dim_coche dc ON fsa.coche_id = dc.coche_id
INNER JOIN dim_marca m ON dc.marca_id = m.marca_id
GROUP BY m.nombre, dc.modelo
ORDER BY unidades_vendidas DESC 
LIMIT 10;

-- -------------------------------------------------------------
-- C2. Ingresos por país (usando la vista de negocio)
-- Insight: qué mercados geográficos generan más ingresos.
-- Incluye LEFT JOIN para ver países aunque no tengan ventas.
-- -------------------------------------------------------------

