from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_build_script_bundles_embedded_python_runtime():
    script = (ROOT / "script" / "build_and_run.sh").read_text()

    assert 'PYTHON_RUNTIME_DIR="$APP_RESOURCES/Python"' in script
    assert "bundle_python_runtime" in script
    assert "OMNIVOICE_PYTHON_RUNTIME_SOURCE" in script
    assert 'find "$PYTHON_RUNTIME_DIR" -name "__pycache__"' in script
    assert 'chmod -R a-w "$PYTHON_RUNTIME_DIR"' in script


def test_bundled_engine_launcher_prefers_embedded_python_before_system_python():
    script = (ROOT / "scripts" / "run-bundled-engine.sh").read_text()

    bundled_index = script.index('BUNDLED_PYTHON_BIN="$APP_RESOURCES_DIR/Python/bin/python3.12"')
    system_index = script.index("python3.13")

    assert bundled_index < system_index
    assert "Bundled Python runtime is missing" in script
    assert "PYTHONDONTWRITEBYTECODE" in script
    assert "PYTHONPYCACHEPREFIX" in script


def test_dmg_readme_no_longer_requires_user_installed_python():
    script = (ROOT / "script" / "build_and_run.sh").read_text()

    assert "OmniVoice includes its own Python runtime" in script
    assert "Python 3.12 or newer is required." not in script
