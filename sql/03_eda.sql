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

WITH paises_referencia AS (
	-- Lista de todos los países que aparecen en el dataset
	SELECT DISTINCT country FROM fact_sales
)
SELECT
	pr.country,
	COUNT(fsa.sale_id) AS num_ventas,
	COALESCE(SUM(fsa.total_price), 0) AS ingresos_totales,
	COALESCE(ROUND(AVG(fsa.total_price), 2), 0) AS ticket_medio
FROM paises_referencia pr
LEFT JOIN fact_sales fsa ON pr.country = fsa.country 
GROUP BY pr.country 
ORDER BY ingresos_totales DESC;

-- -------------------------------------------------------------
-- C3. Ranking de marcas por ingresos con funciones ventana
-- Insight: posición relativa de cada marca en el mercado.
-- RANK() permite ver empates; DENSE_RANK() no deja huecos.
-- -------------------------------------------------------------

SELECT
	marca,
	ingresos_totales,
	num_ventas,
	RANK() OVER (ORDER BY ingresos_totales DESC) AS ranking_ingresos,
	DENSE_RANK() OVER (ORDER BY num_ventas DESC) AS ranking_ventas
FROM v_ventas_por_marca
LIMIT 15;

-- -------------------------------------------------------------
-- C4. Cuota de mercado por tipo de combustible en ventas
-- Insight: qué tecnología de propulsión domina las ventas reales (no solo el catálogo). 
-- Combina fact_sales con dim_coche y dim_combustible.
-- -------------------------------------------------------------

SELECT
	cb.tipo AS combustible,
	COUNT(fsa.sale_id) AS num_ventas,
	ROUND(SUM(fsa.total_price), 2) AS ingresos,
	ROUND(SUM(fsa.total_price) * 100.0 / SUM(SUM(fsa.total_price)) OVER (), 2) AS pct_ingresos
FROM fact_sales fsa
INNER JOIN dim_coche dc ON fsa.coche_id = dc.coche_id
INNER JOIN dim_combustible cb ON dc.combustible_id = cb.combustible_id
GROUP BY cb.tipo
ORDER BY ingresos DESC;

-- -------------------------------------------------------------
-- C5. Clasificación de coches por segmento de precio con CASE
-- Insight: distribución del catálogo por segmento (económico
-- medio, premium, lujo) y rendimiento medio de cada segmento.
-- -------------------------------------------------------------

SELECT 
CASE
	WHEN precio_usd < 20000 THEN 'Económico (<20k)'
	WHEN precio_usd BETWEEN 20000 AND 60000 THEN 'Medio (20k-60k)'
	WHEN precio_usd BETWEEN 60001 AND 150000 THEN 'Premium (60k-150k)'
	WHEN precio_usd > 150000 THEN 'Lujo (>150k)'
	ELSE 'Sin precio'
END AS segmento,
COUNT(*) AS num_modelos,
ROUND(AVG(velocidad_max_kmh), 1) AS velocidad_media,
ROUND(AVG(aceleracion_0_100), 2) AS aceleracion_media 
FROM dim_coche
WHERE precio_usd > 0
GROUP BY segmento
ORDER BY MIN(precio_usd);

-- -------------------------------------------------------------
-- C6. Ventas por trimestre usando funciones de fecha
-- Insight: detectar estacionalidad en las ventas.
-- (¿Hay trimestre con más actividad comercial?).
-- CAST convierte el número de trimestre a texto para el label.
-- -------------------------------------------------------------

SELECT
	EXTRACT(YEAR FROM sale_date)::INT AS anio,
	EXTRACT(QUARTER FROM sale_date)::INT AS trimestre,
	'Q' || CAST(EXTRACT(QUARTER FROM sale_date) AS TEXT) AS label_trimestre,
	COUNT(sale_id) AS num_ventas,
	ROUND(SUM(total_price), 2) AS ingresos
FROM fact_sales
GROUP BY EXTRACT(YEAR FROM sale_date), EXTRACT(QUARTER FROM sale_date)
ORDER BY anio, trimestre;

-- -------------------------------------------------------------
-- C7. Ticket medio por dealer y ranking dentro de su país
-- Insight: qué dealers venden coches más caros en cada mercado.
-- Usa función ventana para ranking por grupos (país).
-- -------------------------------------------------------------

SELECT
	fsa.country,
	fsa.dealer_id,
	COUNT(fsa.sale_id) AS num_ventas,
	ROUND(AVG(fsa.total_price), 2) AS ticket_medio,
	RANK() OVER (
		PARTITION BY fsa.country
		ORDER BY AVG(fsa.total_price) DESC
	) AS ranking_en_pais
FROM fact_sales fsa
GROUP BY fsa.country, fsa.dealer_id
ORDER BY fsa.country, ranking_en_pais;

-- -------------------------------------------------------------
-- C8. CTE encadenada: ventas del top 5 marcas más vendidas
-- Insight: análisis en profundidad de los líderes de mercado.
-- Usamos dos CTEs encadenadas: primera obetenemos el top 5,
-- luego cruzamos con las ventas detalladas de esas marcas.
-- -------------------------------------------------------------

WITH top5_marcas AS (
	-- CTE1: Identificar las 5 marcas con más unidades vendidas
	SELECT
		m.marca_id,
		m.nombre,
		SUM(fsa.quantity) AS total_unidades
	FROM fact_sales fsa
	JOIN dim_coche dc ON fsa.coche_id = dc.coche_id
	JOIN dim_marca m ON dc.marca_id = m.marca_id
	GROUP BY m.marca_id, m.nombre
	ORDER BY total_unidades DESC
	LIMIT 5
),
ventas_top5 AS (
	-- CTE 2: ventas anuales de esas 5 marcas
	SELECT
		t.nombre AS marca,
		EXTRACT(YEAR FROM fsa.sale_date)::INT AS anio,
		COUNT(fsa.sale_id) AS num_ventas,
		ROUND(SUM(fsa.total_price), 2) AS ingresos
	FROM fact_sales fsa
	JOIN dim_coche dc ON fsa.coche_id = dc.coche_id
	JOIN top5_marcas t ON dc.marca_id = t.marca_id 
	GROUP BY t.nombre, EXTRACT(YEAR FROM fsa.sale_date)
)
SELECT * FROM ventas_top5
ORDER BY marca, anio;

-- -------------------------------------------------------------
-- C9. Ventas acumuladas por marca con ventana acumulativa
-- Insight: progresión de ingresos a lo largo del tiempo para
-- ver que marcas crecen más rápido (running total).
-- -------------------------------------------------------------

WITH ventas_mesuales AS (
	SELECT
	m.nombre AS marca,
	DATE_TRUNC('month', fsa.sale_date)::DATE AS mes,
	ROUND(SUM(fsa.total_price), 2) AS ingresos_mes
	FROM fact_sales fsa
	JOIN dim_coche dc ON fsa.coche_id = dc.coche_id
	JOIN dim_marca m ON dc.marca_id = m.marca_id
	-- Solo las 3 marcas con más ventas para no saturar el resultado
	WHERE m.nombre IN (
		SELECT m2.nombre
		FROM fact_sales fsa2
		JOIN dim_coche dc2 ON fsa2.coche_id = dc2.coche_id
		JOIN dim_marca m2 ON dc2.marca_id = m2.marca_id
		GROUP BY m2.nombre
		ORDER BY SUM(fsa2.quantity) DESC 
		LIMIT 3
	)
	GROUP BY m.nombre, DATE_TRUNC('month', fsa.sale_date)
)
SELECT
	marca,
	mes,
	ingresos_mes,
	ROUND(SUM(ingresos_mes) OVER (
		PARTITION BY marca
		ORDER BY mes
		ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
	), 2) AS ingresos_acumulados
FROM ventas_mesuales 
ORDER BY marca, mes;

-- -------------------------------------------------------------
-- C10. Subquery: coches del catálogo que NUNCA se han vendido
-- Insight: modelos del catálogo sin ninguna venta registrada.
-- Útil para decisiones de inventario o descatalogación.
-- LEFT JOIN + IS NULL como alternativa a NOT IN con subquery.
-- -------------------------------------------------------------

SELECT
	m.nombre AS marca,
	dc.modelo,
	dc.precio_usd,
	cb.tipo AS combustible
FROM dim_coche dc
JOIN dim_marca m ON dc.marca_id = m.marca_id 
LEFT JOIN dim_combustible cb ON dc.combustible_id = cb.combustible_id
WHERE dc.coche_id NOT IN (
	SELECT DISTINCT coche_id FROM fact_sales
)
ORDER BY m.nombre, dc.modelo
LIMIT 30;

-- -------------------------------------------------------------
-- C11. Transacción: insertar una venta nueva y hacer rollback
-- Demostración de BEGIN / COMMIT / ROLLBACK.
-- Insertaremos una venta de prueba y la revertimos para no
-- contaminar los datos reales.
-- -------------------------------------------------------------

BEGIN;

	INSERT INTO fact_sales (
		sale_date, customer_id, dealer_id, salesperson_id,
		coche_id, quantity, unit_price, total_price, payment_method, country
	) VALUES (
		'2025-01-15', 'CL0001', 'DL001', 'SP001',
		1, 1, 1100000.00, 1100000.00, 'Cash', 'Spain'
	);
	
	-- Verificamos que se insertó
	SELECT sale_id, sale_date, total_price FROM fact_sales ORDER BY sale_id DESC LIMIT 1;
	
ROLLBACK;
-- La venta de prueba queda descartada, los datos siguen intactos.

-- -------------------------------------------------------------
-- C12. Uso de la función creada en 01_schema.sql
-- Insight: comparar ingresos totales entre dos marcas concretas.
-- -------------------------------------------------------------

SELECT 
	'FERRARI' AS marca,
	fn_total_ventas_marca('FERRARI') AS ingresos_totales
UNION ALL
SELECT 
	'BMW',
	fn_total_ventas_marca('BMW');

-- -------------------------------------------------------------
-- C13. Ventas por vendedor con % sobre el total de su dealer
-- Insight: qué vendedor aporta más dentro de cada concesionario.
-- Usa función ventana para calcular el total del dealer en paralelo.
-- -------------------------------------------------------------

SELECT
	dealer_id,
	salesperson_id,
	COUNT(sale_id) AS num_ventas,
	ROUND(SUM(total_price), 2) AS ingresos,
	ROUND(
		SUM(total_price) * 100.0 /
		SUM(SUM(total_price)) OVER (PARTITION BY dealer_id), 2
	) AS pct_sobre_dealer
FROM fact_sales
GROUP BY dealer_id, salesperson_id
ORDER BY dealer_id, ingresos DESC;