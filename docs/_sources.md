{% docs src_raw_crm %}
Landing zone del sistema CRM en SQL Server (`dbt_cibao_raw.raw_crm`).

Contiene datos de clientes y sus direcciones tal como fueron extraídos del sistema fuente.
Cada ingesta hace **TRUNCATE + full reload** — la tabla raw refleja siempre el estado
actual del sistema fuente, sin historia. Los registros eliminados en la fuente se marcan
con `_is_deleted = 1` antes del truncate (lógica del pipeline).

**Freshness esperada:** datos nuevos cada día. Alerta warn a las 24h, error a las 72h.
{% enddocs %}

{% docs src_raw_crm_customers %}
Tabla raw de clientes del CRM. Contiene información de identificación, contacto y
referencia al sistema (account_number). Incluye clientes individuales (con person_id)
y clientes corporativos (con store_id).

**Granularidad:** un registro por cliente (`customer_id` único).
**PII presente:** name, email_address, phone.
**Relaciones:** addresses (1:N por customer_id).
{% enddocs %}

{% docs src_raw_crm_addresses %}
Tabla raw de direcciones de clientes del CRM. Un cliente puede tener múltiples
direcciones (facturación, envío, etc.).

**Granularidad:** un registro por dirección (`address_id` único).
**PII presente:** address_line1, address_line2.
**Relaciones:** customers (N:1 por customer_id).
{% enddocs %}

{% docs src_raw_erp %}
Landing zone del sistema ERP en SQL Server (`dbt_cibao_raw.raw_erp`).

Contiene el ciclo completo de ventas: órdenes de venta (cabecera + detalle) y
catálogo de productos. Las órdenes tienen alta frecuencia de carga (diaria).
Los productos se consideran un catálogo semi-estático (alerta a los 7 días, error a los 30).
{% enddocs %}

{% docs src_raw_erp_order_headers %}
Tabla raw de cabeceras de órdenes de venta. Cada fila representa una orden completa
con su cliente, fechas, estado y montos totales.

**Granularidad:** un registro por orden (`sales_order_id` único).
**Sin PII:** customer_id es una clave entera de sistema, no un dato personal.
**Estados:** 1=In Process, 2=Approved, 3=Backordered, 4=Rejected, 5=Shipped, 6=Cancelled.
{% enddocs %}

{% docs src_raw_erp_order_details %}
Tabla raw de líneas de detalle de órdenes. Cada fila es un producto dentro de una orden.

**Granularidad:** un registro por línea de producto dentro de una orden
(clave compuesta: `sales_order_id` + `sales_order_detail_id`).
**Sin PII.**
**Relaciones:** order_headers (N:1), products (N:1).
{% enddocs %}

{% docs src_raw_erp_products %}
Catálogo raw de productos del ERP. Incluye códigos, nombres, precios de lista,
costos de producción y atributos físicos (color, talla, peso).

**Granularidad:** un registro por producto (`product_id` único).
**Sin PII.**
**Freshness relajada:** los productos cambian con menor frecuencia que las órdenes.
{% enddocs %}

{% docs src_raw_hr %}
Landing zone del sistema de RRHH en SQL Server (`dbt_cibao_raw.raw_hr`).

Contiene información de empleados y el catálogo de departamentos. Los empleados
incluyen datos personales sensibles (PII) que nunca deben salir del servidor local
en texto claro.

**Datos PII presentes:** national_id_number, login_id, birth_date.
{% enddocs %}

{% docs src_raw_hr_employees %}
Tabla raw de empleados. Incluye datos personales (cédula, login, fecha de nacimiento),
datos laborales (cargo, fecha de contratación) y datos de compensación (salaried_flag,
vacation_hours, sick_leave_hours).

**Granularidad:** un registro por empleado (`business_entity_id` único).
**PII presente:** national_id_number, login_id, birth_date.
**Relación con az_:** az_employees expone solo hashes de los campos PII.
**Recuperación PII:** usar `int_pii_vault_employees` en SQL Server local.
{% enddocs %}

{% docs src_raw_hr_departments %}
Catálogo raw de departamentos de la empresa. Tabla de referencia organizacional
semi-estática. Cada departamento pertenece a un grupo funcional.

**Granularidad:** un registro por departamento (`department_id` único).
**Sin PII.**
**Freshness relajada:** cambios esperados mensualmente.
{% enddocs %}
