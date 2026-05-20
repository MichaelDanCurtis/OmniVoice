from omnivoice_engine.translation_cli import main


def test_translation_cli_outputs_local_translation(capsys):
    exit_code = main(["--text", "Hola", "--target-language", "en", "--provider", "fake"])

    assert exit_code == 0
    assert capsys.readouterr().out.strip() == "[en] Hola"


def test_translation_cli_can_emit_json(capsys):
    exit_code = main(["--text", "Hola", "--target-language", "en", "--provider", "fake", "--json"])

    assert exit_code == 0
    output = capsys.readouterr().out
    assert '"text": "[en] Hola"' in output
    assert '"detected_language": "es"' in output


def test_translation_cli_can_validate_target_languages(capsys):
    exit_code = main(
        [
            "--text",
            "Hello",
            "--provider",
            "fake",
            "--validate-targets",
            "--max-languages",
            "2",
            "--json",
        ]
    )

    assert exit_code == 0
    output = capsys.readouterr().out
    assert '"tested": 2' in output
    assert '"items": [' in output
