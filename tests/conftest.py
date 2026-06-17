import pytest

def pytest_collection_modifyitems(items):
    """Automatically adds 'unit' or 'integration' markers based on directory.

    This allows running ``pytest -m unit`` or ``pytest -m integration`` without
    manually decorating every test function.
    """
    for item in items:
        # Normalise to forward-slashes so the check works on Windows too.
        path_str = str(item.fspath).replace("\\", "/")
        if "/tests/unit/" in path_str:
            item.add_marker(pytest.mark.unit)
        elif "/tests/integration/" in path_str:
            item.add_marker(pytest.mark.integration)
