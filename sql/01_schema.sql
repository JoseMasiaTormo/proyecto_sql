-- ==========================================>

-- Proyecto Analisis de Ventas de Coches (Cars Dataset 2025).
-- Motor: PostgreSQL.
-- Descripción: Creación del modelo dimensional limpio.
--  - 1 tabla de hechos: fact_sales (ventas de coches).
--  - 5 tablas de dimensión: dim_marca, dim_combustible, dim_coche, dim_dealer, dim_salesperson.

-- ==========================================>


-- ----------------------------------------------------------------------
-- LIMPIEZA PREVIA: Eliminar todo si ya existe para ejecutar desde cero.
-- ----------------------------------------------------------------------

DROP TABLE IF EXISTS fact_sales CASCADE;
DROP TABLE IF EXISTS dim_coche CASCADE;
DROP TABLE IF EXISTS dim_marca CASCADE;
DROP TABLE IF EXISTS dim_combustible CASCADE;
DROP TABLE IF EXISTS dim_dealer CASCADE;
DROP TABLE IF EXISTS dim_salesperson CASCADE;
DROP TABLE IF EXISTS dim_customer CASCADE;

DROP VIEW IF EXISTS v_ventas_por_marca;
DROP VIEW IF EXISTS v_top_modelos;
DROP MATERIALIZED VIEW IF EXISTS mv_resumen_anual;
DROP FUNCTION IF EXISTS fn_total_ventas_marca(TEXT);

-- ======================>
-- TABLAS DE DIMENSIÓN
-- ======================>

-- ----------------------------------------------------------------------
-- dim_marca
-- Representa cada fabricante de coches (Ferrari, Toyota, etc.)
-- PK: marca_id (SERIAL, autoincremental - no usamos el nombre como PK 
--     porque puede haber errores tipograficos en los datos)
-- ----------------------------------------------------------------------
CREATE TABLE dim_marca (
    marca_id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE -- UNIQUE: no puede haber dos marcas con el mismo nombre.
);

-- ----------------------------------------------------------------------
-- dim_combustible
-- Tipos de combustibles normalizados (Petrol, Diesel, Electric...)
-- PK: combustible_id (SERIAL)
-- Los valores originales del CSV estaban muy sucios (22 variantes
-- para 6 categorías reales), aquí guardamos ya la versión limpia.
-- ----------------------------------------------------------------------
CREATE TABLE dim_combustible (
    combustible_id SERIAL PRIMARY KEY,
    tipo VARCHAR(50) NOT NULL UNIQUE
);

-- ----------------------------------------------------------------------
-- dim_coche
-- Catálogo de modelos de coches (tabla principal del CSV original)
-- PK: coche_id (SERIAL)
-- FK: marca_id -> dim_marca | combustible_id -> dim_combustible
-- Aquí almacenamos las características técnicas de cada modelo.
-- ----------------------------------------------------------------------
CREATE TABLE dim_coche (
    coche_id SERIAL PRIMARY KEY,
    marca_id INT NOT NULL REFERENCES dim_marca(marca_id),
    modelo VARCHAR(150) NOT NULL,
    motor VARCHAR(150),
    cc_bateria VARCHAR(50), -- Lo dejamos como texto: hay valores tipo "3,990 cc" o "100 kWh"
    caballos_hp VARCHAR(50), -- Texto: hay rangos como "70-85 hp"
    velocidad_max_kmh INT, -- Extraído y limpiado en 02_data.sql
    aceleracion_0_100 NUMERIC(4, 1), -- Segundos (puede tener decimales)
    precio_usd NUMERIC(12, 2) check (precio_usd is null or precio_usd > 0), -- Precio limpio sin "$" ni comas
    combustible_id INT REFERENCES dim_combustible(combustible_id),
    asientos VARCHAR(10), -- Texto: hay valores "2+2" o rangos
    torque_nm VARCHAR(50) -- Texto: hay rangos "100-140 Nm"
);

-- No ponemos UNIQUE en (marca_id, modelo) porque el CSV tiene
-- duplicados reales (mismo modelo con distintas versiones).

-- ----------------------------------------------------------------------
-- dim_customer
-- Clientes. En este dataset son IDs ficticios generados (CL0001...).
-- PK: customer_id (VARCHAR - ya viene formateado como "CL0001")
-- ----------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_id VARCHAR(10) PRIMARY KEY
);

-- ----------------------------------------------------------------------
-- dim_dealer
-- Concesionarios. IDs ficticios generados (DL001...).
-- PK: dealer_id
-- ----------------------------------------------------------------------
CREATE TABLE dim_dealer (
    dealer_id VARCHAR(10) PRIMARY KEY
);

-- ----------------------------------------------------------------------
-- dim_salesperson
-- Vendedores. IDs ficticios (SP001...).
-- PK: salesperson_id
-- ----------------------------------------------------------------------
CREATE TABLE dim_salesperson (
    salesperson_id VARCHAR(10) PRIMARY KEY
);


-- ======================>
-- TABLA DE HECHOS
-- ======================>

-- ----------------------------------------------------------------------
-- fact_sales
-- Cada fila = una transacción de venta de coche.
-- Granularidad: 1 fila por venta (un cliente compra N unidades
--               de un modelo en una fecha concreta).
-- PK: sale_id
-- FK: coche_id, customer_id, dealer_id, salesperson_id
-- ----------------------------------------------------------------------
CREATE TABLE fact_sales (
    sale_id SERIAL PRIMARY KEY, 
    sale_date DATE NOT NULL,
    customer_id VARCHAR(10) NOT NULL REFERENCES dim_customer(customer_id),
    dealer_id VARCHAR(10) NOT NULL REFERENCES dim_dealer(dealer_id),
    salesperson_id VARCHAR(10) NOT NULL REFERENCES dim_salesperson(salesperson_id),
    coche_id INT NOT NULL REFERENCES dim_coche(coche_id),
    quantity SMALLINT NOT NULL DEFAULT 1,
    unit_price NUMERIC(12, 2) NOT NULL,
    total_price NUMERIC(14, 2) NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    country VARCHAR(50) NOT null

    CONSTRAINT chk_quantity_positiva CHECK (quantity > 0),
    CONSTRAINT chk_unit_price_positivo CHECK (unit_price > 0),
    CONSTRAINT chk_total_price_positivo CHECK (total_price > 0),
    CONSTRAINT chk_payment_method CHECK (payment_method IN ('Cash', 'Financing', 'Leasing'))
);

-- ======================>
-- ÍNDICES
-- ======================>

-- Índice en sale_date: la mayoría de consultas de analisis filtran o agrupan
-- por fecha. Sin el índice, cada query haría un full scan de las 2500 filas
-- de fact_sales (y en una tabla más grande podrían ser millones).
CREATE INDEX idx_fact_sales_date ON fact_sales(sale_date);

-- Índice en coche_id: los JOINs entre fact_sales y dim_coche se ejecutarán
-- muy frecuentemente en las queries analíticas.
CREATE INDEX idx_fact_sales_coche ON fact_sales(coche_id);

-- Índice en country: consultas de ventas por país son habituales en el EDA
-- y en las vistas de negocio.
CREATE INDEX idx_fact_sales_country ON fact_sales(country);


-- ======================>
-- VISTAS DE NEGOCIO
-- ======================>

-- ----------------------------------------------------------------------
-- v_ventas_por_marca
-- Vista normal: ventas agregadas por marca.
-- Se recalcula en cada consulta, siempre muestra datos frescos.
-- Útil para dashboards o informes donde los datos cambian.
-- ----------------------------------------------------------------------

CREATE VIEW v_ventas_por_marca AS
SELECT
    m.nombre AS marca,
    COUNT(fs.sale_id) AS num_ventas,
    SUM(fs.quantity) AS unidades_vendidas,
    ROUND(SUM(fs.total_price), 2) AS ingresos_totales,
    ROUND(AVG(fs.unit_price), 2) AS precio_medio
FROM fact_sales fs
JOIN dim_coche dc ON fs.coche_id = dc.coche_id
JOIN dim_marca m ON dc.marca_id = m.marca_id
GROUP BY m.nombre
ORDER BY ingresos_totales DESC;

-- ----------------------------------------------------------------------
-- v_top_modelos
-- Vista normal: top modelos por ingresos totales generados.
-- Permite ver qué modelos específicos mueven más dinero.
-- ----------------------------------------------------------------------

CREATE VIEW v_top_modelos AS
SELECT
    m.nombre AS marca,
    dc.modelo,
    COUNT(fs.sale_id) AS num_ventas,
    SUM(fs.quantity) AS unidades_vendidas,
    ROUND(SUM(fs.total_price), 2) AS ingresos_totales,
    ROUND(AVG(fs.unit_price), 2) AS precio_medio
FROM fact_sales fs
JOIN dim_coche dc ON fs.coche_id = dc.coche_id
JOIN dim_marca m ON dc.marca_id = m.marca_id
GROUP BY m.nombre, dc.modelo
ORDER BY ingresos_totales DESC;

-- ----------------------------------------------------------------------
-- mv_resumen_anual
-- Vista materializada: resumen de ventas por año.
-- Los datos se almacenan físicamente en disco -> consulta rapidísima.
-- Hay que hacer REFRESH MATERIALIZED VIEW mv_resumen_anual; cuando los datos cambien.
-- Útil para informes históricos que no necesitan datos en tiempo real.
-- ----------------------------------------------------------------------

CREATE MATERIALIZED VIEW mv_resumen_anual AS
SELECT
    EXTRACT(YEAR FROM sale_date)::INT AS anio,
    COUNT(sale_id) AS num_ventas,
    SUM(quantity) AS unidades_vendidas,
    ROUND(SUM(total_price), 2) AS ingresos_totales,
    ROUND(AVG(unit_price), 2) AS precio_medio
FROM fact_sales
GROUP BY EXTRACT(YEAR FROM sale_date)
ORDER BY anio;

-- ======================>
-- FUNCIÓN
-- ======================>

-- ----------------------------------------------------------------------
-- fn_total_ventas_marca(nombre_marca)
-- Devuelve el total de ingresos generados por una marca concreta.
-- Ejemplo de uso: SELECT fn_total_ventas_marca('FERRARI');
-- ----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_total_ventas_marca(p_marca TEXT)
RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC;
BEGIN
    SELECT COALESCE(SUM(fs.total_price), 0)
    INTO v_total
    FROM fact_sales fs
    JOIN dim_coche dc ON fs.coche_id = dc.coche_id
    JOIN dim_marca m ON dc.marca_id = m.marca_id
    WHERE UPPER(m.nombre) = UPPER(p_marca);

    RETURN v_total;
END;
$$ LANGUAGE plpgsql;