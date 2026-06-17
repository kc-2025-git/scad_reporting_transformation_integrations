# SQL Rules for Databricks Transformations

<sql_development_mandate>
[CRITICAL] When creating or editing `.sql` files in the `transformations/` directory, you MUST follow these execution constraints:
1. **Parameter Injection:** The Databricks orchestrator executes SQL files using Python's string formatting: `spark.sql(sql_query.format(catalog=catalog))`.
2. **Literal Parameter:** You MUST inject the catalog name by using the exact literal placeholder `{catalog}` in the SQL syntax wherever the catalog name is required.
3. **No Databricks Widgets:** Do not attempt to use Databricks widgets or SQL variables (like `${catalog}`) for parameterization. Only use `{catalog}`.

**Example usage in SQL:**
```sql
SELECT *
FROM {catalog}.bronze.some_table
```
</sql_development_mandate>
