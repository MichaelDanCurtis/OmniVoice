from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_build_script_bundles_embedded_python_runtime():
    script = (ROOT / "script" / "build_and_run.sh").read_text()

    assert 'PYTHON_RUNTIME_DIR="$APP_RESOURCES/Python"' in script
    assert 'ENGINE_WHEELHOUSE_DIR="$ENGINE_BUNDLE_DIR/wheelhouse"' in script
    assert "bundle_python_runtime" in script
    assert "bundle_engine_wheelhouse" in script
    assert '"$bundled_python" - "$ROOT_DIR/engine/pyproject.toml" "$requirements_file"' in script
    assert "-m pip download" in script
    assert "OMNIVOICE_PYTHON_RUNTIME_SOURCE" in script
    assert 'find "$PYTHON_RUNTIME_DIR" -name "__pycache__"' in script
    assert 'chmod -R a-w "$PYTHON_RUNTIME_DIR"' in script
    assert "protect_python_runtime\nsign_app_bundle\n/usr/bin/codesign --verify" in script


def test_bundled_engine_launcher_uses_embedded_python_and_wheels_by_default():
    script = (ROOT / "scripts" / "run-bundled-engine.sh").read_text()

    bundled_index = script.index('BUNDLED_PYTHON_BIN="$APP_RESOURCES_DIR/Python/bin/python3.12"')
    system_index = script.index("python3.13")

    assert bundled_index < system_index
    assert 'ALLOW_SYSTEM_PYTHON_FALLBACK="${OMNIVOICE_ALLOW_SYSTEM_PYTHON_FALLBACK:-0}"' in script
    assert 'BUNDLED_WHEELHOUSE_DIR="$BUNDLED_ENGINE_ROOT/wheelhouse"' in script
    assert 'OMNIVOICE_USE_BUNDLED_WHEELHOUSE:-1' in script
    assert "--no-index" in script
    assert "--find-links" in script
    assert "Bundled Python runtime is missing" in script
    assert "Bundled OmniVoice Python wheelhouse is missing" in script
    assert "Canary-Qwen runtime is not part of the bundled wheelhouse" in script
    assert "PYTHONDONTWRITEBYTECODE" in script
    assert "PYTHONPYCACHEPREFIX" in script


def test_dmg_readme_no_longer_requires_user_installed_python():
    script = (ROOT / "script" / "build_and_run.sh").read_text()

    assert "OmniVoice includes its own Python runtime" in script
    assert "Python 3.12 or newer is required." not in script
    assert 'make_bundle_writable_for_rebuild "$DMG_STAGING/$APP_DISPLAY_NAME.app"' in script


def test_distribution_docs_describe_integrated_runtime_and_external_models():
    readme = (ROOT / "README.md").read_text()
    distribution = (ROOT / "docs" / "LOCAL_DISTRIBUTION.md").read_text()

    assert "Python 3.12 or newer" not in readme
    assert "Python 3.12 or newer" not in distribution
    assert "bundled Python runtime" in readme
    assert "bundled Python runtime" in distribution
    assert "bundled Python wheelhouse" in distribution
    assert "Models are not bundled" in distribution
