# Python Formatting and Testing Rules

<tdd_mandate>
[MANDATORY] TEST-DRIVEN DEVELOPMENT (TDD) IS REQUIRED for any configuration validation or generation scripts you create.
1. You MUST write robust, comprehensive `pytest` tests FIRST for any new feature or modification.
2. NEVER write the implementation code before the tests are fully defined and act as the specification.
</tdd_mandate>

<python_project_rules>
[CRITICAL] Follow these rules EXACTLY:
1. **Modern Python:** ALWAYS use Python 3.10+ features (pattern matching, context managers).
2. **Strict Typing:** You MUST enforce explicit type hinting for ALL Python function signatures, class methods, and complex variables.
3. **F-Strings:** ALWAYS use f-strings for variables. DO NOT convert simple strings to f-strings unnecessarily.
4. **Formatting:** Python code MUST strictly conform to `black` (88-chars, double quotes) and PEP 8.
5. **Documentation:** Include PEP 257 Google-style docstrings for any Python validation code.
</python_project_rules>

<testing_guidelines>
[MANDATORY] Pytest Rules for Validation Scripts:
1. **Tests First:** ALWAYS output `test_*.py` files first.
2. **Simplicity:** Cyclomatic complexity MUST be 1. DO NOT use `if`, `while`, or complex `try/except` inside tests.
3. **AAA Pattern:** Structure tests with exactly 3 blocks (Arrange, Act, Assert) separated by newlines.
4. **Exceptions:** ALWAYS use `with pytest.raises(ExpectedException, match="regex"):`.
5. **Black Box:** Test behavior, not internal implementation.
6. **Iteration:** ALWAYS use `@pytest.mark.parametrize` instead of writing loops.
</testing_guidelines>

<output_format>
[MANDATORY] Output Requirements:
1. **Dependencies:** Keep `requirements.txt` up to date if you add config validation libraries (e.g., Pydantic). Always pin to a specific version.
</output_format>
