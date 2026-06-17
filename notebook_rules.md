# Notebook Rules for Databricks Transformations

<notebook_development_mandate>
[CRITICAL] When creating or editing `.py` or `.ipynb` files in the `transformations/` directory, you MUST follow these execution constraints:
1. **Execution Context:** The Databricks orchestrator executes Python/Notebook files using `dbutils.notebook.run(..., arguments={"catalog": catalog})`.
2. **Parameter Retrieval:** You MUST retrieve the catalog parameter using Databricks widgets. Do not rely on Python's string formatting for the `{catalog}` value.

**Example usage in Python/Notebooks:**
```python
# Databricks notebook source
catalog = dbutils.widgets.get("catalog")

# Example query using the retrieved parameter
query = f"SELECT * FROM {catalog}.bronze.some_table"
df = spark.sql(query)
```
</notebook_development_mandate>
