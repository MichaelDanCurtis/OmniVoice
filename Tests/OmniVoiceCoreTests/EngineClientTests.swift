import XCTest
@testable import OmniVoiceCore

final class EngineClientTests: XCTestCase {
    func testCleanupRequestEncodesSnakeCasePayload() throws {
        let request = CleanupRequest(
            rawTranscript: "Schedule it for Monday, actually Tuesday.",
            style: .neutral,
            dictionaryTerms: ["OmniVoice"]
        )
        let data = try EngineCoding.encoder.encode(request)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("raw_transcript"))
        XCTAssertTrue(json.contains("dictionary_terms"))
        XCTAssertTrue(json.contains("OmniVoice"))
        XCTAssertTrue(json.contains("neutral"))
    }

    func testCleanupResponseDecodesSnakeCasePayload() throws {
        let data = #"{"text":"Schedule it for Tuesday.","cleanup_applied":true}"#.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(CleanupResult.self, from: data)

        XCTAssertEqual(response, CleanupResult(text: "Schedule it for Tuesday.", cleanupApplied: true))
    }

    func testTranslationRequestEncodesSnakeCasePayload() throws {
        let request = TranslationRequest(
            text: "Hola",
            provider: .fake,
            sourceLanguage: "auto",
            targetLanguage: "en",
            context: ["greeting"],
            isFinal: false
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["text"] as? String, "Hola")
        XCTAssertEqual(object["provider"] as? String, "fake")
        XCTAssertEqual(object["source_language"] as? String, "auto")
        XCTAssertEqual(object["target_language"] as? String, "en")
        XCTAssertEqual(object["context"] as? [String], ["greeting"])
        XCTAssertEqual(object["is_final"] as? Bool, false)
    }

    func testTranslationResponseDecodesEnginePayload() throws {
        let data = #"{"text":"[en] Hola","provider":"fake","source_language":"auto","detected_language":"es","target_language":"en","confidence":0.74,"is_final":true}"#.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(TranslationResult.self, from: data)

        XCTAssertEqual(response.text, "[en] Hola")
        XCTAssertEqual(response.provider, .fake)
        XCTAssertEqual(response.sourceLanguage, "auto")
        XCTAssertEqual(response.detectedLanguage, "es")
        XCTAssertEqual(response.targetLanguage, "en")
        XCTAssertEqual(response.confidence, 0.74)
        XCTAssertTrue(response.isFinal)
    }

    func testTranslationValidationRequestEncodesSnakeCasePayload() throws {
        let request = TranslationValidationRequest(
            text: "Hello",
            provider: .translateGemmaMLX,
            sourceLanguage: "en",
            modelPath: "/models/translate",
            targetLanguages: ["zh", "fr"],
            maxLanguages: 2
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["source_language"] as? String, "en")
        XCTAssertEqual(object["model_path"] as? String, "/models/translate")
        XCTAssertEqual(object["target_languages"] as? [String], ["zh", "fr"])
        XCTAssertEqual(object["max_languages"] as? Int, 2)
    }

    func testTranslationValidationResponseDecodesEnginePayload() throws {
        let data = """
        {
          "provider": "translategemma-mlx",
          "source_language": "en",
          "text": "Hello",
          "capability_source": "model-template",
          "tested": 1,
          "passed": 1,
          "review": 0,
          "failed": 0,
          "items": [
            {
              "code": "zh",
              "name": "Chinese",
              "text": "你好",
              "status": "pass",
              "expected_scripts": ["Han"],
              "dominant_script": "Han",
              "scripts": {"Han": 2},
              "letter_count": 2,
              "expected_script_characters": 2,
              "expected_script_ratio": 1.0,
              "replacement_characters": 0,
              "output_preview": "你好",
              "failure_category": null,
              "notes": []
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(TranslationValidationResponse.self, from: data)

        XCTAssertEqual(response.provider, .translateGemmaMLX)
        XCTAssertEqual(response.tested, 1)
        XCTAssertEqual(response.items[0].expectedScripts, ["Han"])
        XCTAssertEqual(response.items[0].dominantScript, "Han")
        XCTAssertEqual(response.items[0].letterCount, 2)
        XCTAssertEqual(response.items[0].expectedScriptCharacters, 2)
        XCTAssertEqual(response.items[0].expectedScriptRatio, 1.0)
        XCTAssertEqual(response.items[0].outputPreview, "你好")
        XCTAssertNil(response.items[0].failureCategory)
    }

    func testTranslationProviderInfoDecodesEnginePayload() throws {
        let data = #"{"id":"translategemma-mlx","label":"TranslateGemma MLX","available":false,"reason":"model path not configured"}"#.data(using: .utf8)!

        let provider = try EngineCoding.decoder.decode(TranslationProviderInfo.self, from: data)

        XCTAssertEqual(provider.id, "translategemma-mlx")
        XCTAssertEqual(provider.kind, .translateGemmaMLX)
        XCTAssertEqual(provider.label, "TranslateGemma MLX")
        XCTAssertFalse(provider.available)
        XCTAssertEqual(provider.reason, "model path not configured")
    }

    func testTranscribeResponseDecodesProviderPayload() throws {
        let data = #"{"text":"hello","provider":"fake"}"#.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(TranscribeResult.self, from: data)

        XCTAssertEqual(response.text, "hello")
        XCTAssertEqual(response.provider, .fake)
    }

    func testProviderInfoDecodesEnginePayload() throws {
        let data = #"{"id":"parakeet-tdt","label":"Parakeet TDT","available":false,"reason":"model files not found"}"#.data(using: .utf8)!

        let provider = try EngineCoding.decoder.decode(EngineProviderInfo.self, from: data)

        XCTAssertEqual(provider.id, "parakeet-tdt")
        XCTAssertEqual(provider.label, "Parakeet TDT")
        XCTAssertFalse(provider.available)
        XCTAssertEqual(provider.reason, "model files not found")
    }

    func testModelStatusDecodesHuggingFacePayload() throws {
        let data = #"{"provider_id":"translategemma-mlx","label":"TranslateGemma 4B 4-bit","repo_id":"mlx-community/translategemma-4b-it-4bit","local_path":"/models/translategemma-mlx","installed":false,"installed_revision":null,"remote_revision":null,"update_available":null,"missing_files":["model.safetensors"],"download_state":"idle","download_message":null,"category":"translation","recommendation":"Fast / Recommended","detail":"Default low-latency local translation model.","size":"2.18 GB","precision":"4-bit","requires_hf_auth":true,"agreement_url":"https://huggingface.co/google/translategemma-4b-it","license":"gemma"}"#.data(using: .utf8)!

        let status = try EngineCoding.decoder.decode(EngineModelStatus.self, from: data)

        XCTAssertEqual(status.providerID, "translategemma-mlx")
        XCTAssertEqual(status.repoID, "mlx-community/translategemma-4b-it-4bit")
        XCTAssertFalse(status.installed)
        XCTAssertEqual(status.missingFiles, ["model.safetensors"])
        XCTAssertEqual(status.downloadState, "idle")
        XCTAssertEqual(status.category, "translation")
        XCTAssertEqual(status.recommendation, "Fast / Recommended")
        XCTAssertEqual(status.size, "2.18 GB")
        XCTAssertEqual(status.precision, "4-bit")
        XCTAssertTrue(status.requiresHFAuth)
        XCTAssertEqual(status.agreementURL, "https://huggingface.co/google/translategemma-4b-it")
        XCTAssertEqual(status.license, "gemma")
    }

    func testHuggingFaceAuthStatusDecodesEnginePayload() throws {
        let data = #"{"connected":true,"source":"app-keychain","username":"test-user","provider_id":"translategemma-mlx","repo_id":"mlx-community/translategemma-4b-it-4bit","access_granted":true,"message":"Access granted"}"#.data(using: .utf8)!

        let status = try EngineCoding.decoder.decode(HuggingFaceAuthStatus.self, from: data)

        XCTAssertTrue(status.connected)
        XCTAssertEqual(status.source, "app-keychain")
        XCTAssertEqual(status.username, "test-user")
        XCTAssertEqual(status.providerID, "translategemma-mlx")
        XCTAssertEqual(status.accessGranted, true)
    }

    func testHuggingFaceTokenValidationRequestEncodesSnakeCasePayload() throws {
        let request = HuggingFaceTokenValidationRequest(token: "hf_test", providerID: "translategemma-mlx")

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["token"] as? String, "hf_test")
        XCTAssertEqual(object["provider_id"] as? String, "translategemma-mlx")
    }

    func testTranslationCapabilitiesDecodesEnginePayload() throws {
        let data = """
        {
          "provider_id": "translategemma-mlx",
          "model_provider_id": "translategemma-mlx",
          "source_language_locked": true,
          "source_language_reason": "Live speech translation currently uses English ASR input.",
          "source_languages": [{"code": "en", "name": "English", "is_default": true}],
          "target_languages": [
            {"code": "en", "name": "English", "is_default": false},
            {"code": "es", "name": "Spanish", "is_default": false}
          ],
          "capability_source": "model-template",
          "message": null
        }
        """.data(using: .utf8)!

        let capabilities = try EngineCoding.decoder.decode(TranslationCapabilities.self, from: data)

        XCTAssertEqual(capabilities.providerID, "translategemma-mlx")
        XCTAssertEqual(capabilities.modelProviderID, "translategemma-mlx")
        XCTAssertTrue(capabilities.sourceLanguageLocked)
        XCTAssertEqual(capabilities.sourceLanguages, [TranslationLanguageOption(code: "en", name: "English", isDefault: true)])
        XCTAssertEqual(capabilities.targetLanguages.map(\.code), ["en", "es"])
        XCTAssertEqual(capabilities.capabilitySource, "model-template")
    }

    func testModelUpdateDecodesRemoteRevisionPayload() throws {
        let data = #"{"provider_id":"parakeet-tdt","repo_id":"repo","installed_revision":"old-sha","remote_revision":"new-sha","update_available":true}"#.data(using: .utf8)!

        let update = try EngineCoding.decoder.decode(EngineModelUpdateInfo.self, from: data)

        XCTAssertEqual(update.installedRevision, "old-sha")
        XCTAssertEqual(update.remoteRevision, "new-sha")
        XCTAssertTrue(update.updateAvailable)
    }

    func testModelDownloadStatusDecodesQueuedPayload() throws {
        let data = #"{"provider_id":"parakeet-tdt","state":"queued","message":"Download queued","local_path":"/models/parakeet-tdt","revision":null}"#.data(using: .utf8)!

        let status = try EngineCoding.decoder.decode(EngineModelDownloadStatus.self, from: data)

        XCTAssertEqual(status.providerID, "parakeet-tdt")
        XCTAssertEqual(status.state, "queued")
        XCTAssertEqual(status.message, "Download queued")
    }

    func testTranscriptRecordDecodesEnginePayload() throws {
        let data = #"{"id":"t1","created_at":"2026-05-16T08:12:30Z","source":"dictation","raw_text":"no wait house","cleaned_text":"I'm going to the house.","provider":"parakeet-tdt","style":"neutral","audio_bytes":128000,"sample_rate":16000,"duration_ms":1500}"#.data(using: .utf8)!

        let record = try EngineCoding.decoder.decode(EngineTranscriptRecord.self, from: data)

        XCTAssertEqual(record.id, "t1")
        XCTAssertEqual(record.createdAt, "2026-05-16T08:12:30Z")
        XCTAssertEqual(record.source, "dictation")
        XCTAssertEqual(record.rawText, "no wait house")
        XCTAssertEqual(record.cleanedText, "I'm going to the house.")
        XCTAssertEqual(record.provider, "parakeet-tdt")
        XCTAssertEqual(record.style, "neutral")
        XCTAssertEqual(record.audioBytes, 128000)
        XCTAssertEqual(record.sampleRate, 16000)
        XCTAssertEqual(record.durationMs, 1500)
        XCTAssertEqual(record.displayText, "I'm going to the house.")
    }

    func testTranscriptUpdateDecodesStreamingPayload() throws {
        let data = #"{"text":"live words","is_final":false}"#.data(using: .utf8)!

        let update = try EngineCoding.decoder.decode(TranscriptUpdate.self, from: data)

        XCTAssertEqual(update, TranscriptUpdate(text: "live words", isFinal: false))
    }

    func testStreamingURLIncludesTranslationConfigurationWhenEnabled() {
        let configuration = TranslationStreamConfiguration(
            provider: .fake,
            sourceLanguage: "auto",
            targetLanguage: "es",
            modelPath: "/models/translate gemma"
        )

        let url = EngineStreamingClient.streamURL(
            baseURL: URL(string: "ws://127.0.0.1:8765")!,
            provider: .parakeetTDTMLX,
            sampleRate: 16000,
            translation: configuration
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items: [URLQueryItem] = components?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.path, "/stream")
        XCTAssertEqual(query["provider"], "parakeet-tdt-mlx")
        XCTAssertEqual(query["sample_rate"], "16000")
        XCTAssertEqual(query["translate"], "true")
        XCTAssertEqual(query["translation_provider"], "fake")
        XCTAssertEqual(query["source_language"], "auto")
        XCTAssertEqual(query["target_language"], "es")
        XCTAssertEqual(query["translation_model_path"], "/models/translate gemma")
    }

    func testStreamingDiagnosticsCanSkipCurrentSnapshot() {
        let client = EngineStreamingClient()
        let diagnostics = expectation(description: "diagnostics should not be delivered immediately")
        diagnostics.isInverted = true

        client.setOnDiagnostics({ _ in diagnostics.fulfill() }, emitCurrent: false)

        wait(for: [diagnostics], timeout: 0.05)
        client.setOnDiagnostics(nil)
    }

    func testAIHandoffRequestEncodesSnakeCasePayload() throws {
        let request = AIHandoffRequest(
            prompt: "write a reply",
            provider: "claude",
            baseURL: "https://openrouter.ai/api/v1",
            model: "anthropic/claude-sonnet",
            apiKey: "secret",
            transport: .openAICompatible,
            oauthAccessToken: "oauth-token",
            headers: ["X-Test": "yes"],
            context: "Jane asked for an update."
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["prompt"] as? String, "write a reply")
        XCTAssertEqual(object["provider"] as? String, "claude")
        XCTAssertEqual(object["base_url"] as? String, "https://openrouter.ai/api/v1")
        XCTAssertEqual(object["model"] as? String, "anthropic/claude-sonnet")
        XCTAssertEqual(object["api_key"] as? String, "secret")
        XCTAssertEqual(object["transport"] as? String, "openai_compatible")
        XCTAssertEqual(object["oauth_access_token"] as? String, "oauth-token")
        XCTAssertEqual((object["headers"] as? [String: String])?["X-Test"], "yes")
        XCTAssertEqual(object["context"] as? String, "Jane asked for an update.")
    }

    func testAIChatRequestEncodesSnakeCasePayload() throws {
        let request = AIChatRequest(
            provider: "custom",
            baseURL: "https://api.example.com/v1",
            model: "vision-model",
            apiKey: "secret",
            transport: .openAICompatible,
            oauthAccessToken: "oauth-token",
            headers: ["X-Kimi": "enabled"],
            messages: [
                AIChatMessage(role: .user, content: "What is in this screenshot?")
            ],
            attachments: [
                AIChatAttachment(
                    kind: .image,
                    title: "dashboard.png",
                    text: "Screenshot from OmniVoice.",
                    mimeType: "image/png",
                    dataURL: "data:image/png;base64,abc123"
                )
            ],
            webSearchEnabled: true,
            webSearchQuery: "OmniVoice release notes"
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let attachments = try XCTUnwrap(object["attachments"] as? [[String: Any]])

        XCTAssertEqual(object["provider"] as? String, "custom")
        XCTAssertEqual(object["base_url"] as? String, "https://api.example.com/v1")
        XCTAssertEqual(object["oauth_access_token"] as? String, "oauth-token")
        XCTAssertEqual((object["headers"] as? [String: String])?["X-Kimi"], "enabled")
        XCTAssertEqual(object["web_search_enabled"] as? Bool, true)
        XCTAssertEqual(object["web_search_query"] as? String, "OmniVoice release notes")
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "What is in this screenshot?")
        XCTAssertEqual(attachments.first?["kind"] as? String, "image")
        XCTAssertEqual(attachments.first?["mime_type"] as? String, "image/png")
        XCTAssertEqual(attachments.first?["data_url"] as? String, "data:image/png;base64,abc123")
    }

    func testAIChatResultDecodesEnginePayload() throws {
        let data = #"{"text":"Here is the answer.","provider":"custom","model":"qwen"}"#.data(using: .utf8)!

        let result = try EngineCoding.decoder.decode(AIChatResult.self, from: data)

        XCTAssertEqual(result, AIChatResult(text: "Here is the answer.", provider: "custom", model: "qwen"))
    }

    func testTextLLMModelListRequestEncodesSnakeCasePayload() throws {
        let request = TextLLMModelListRequest(
            provider: "custom",
            baseURL: "https://api.moonshot.ai/v1",
            apiKey: "secret",
            transport: .openAICompatible,
            oauthAccessToken: "oauth-token",
            headers: ["X-Kimi": "code"]
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["provider"] as? String, "custom")
        XCTAssertEqual(object["base_url"] as? String, "https://api.moonshot.ai/v1")
        XCTAssertEqual(object["api_key"] as? String, "secret")
        XCTAssertEqual(object["transport"] as? String, "openai_compatible")
        XCTAssertEqual(object["oauth_access_token"] as? String, "oauth-token")
        XCTAssertEqual((object["headers"] as? [String: String])?["X-Kimi"], "code")
    }

    func testTextLLMModelListResponseDecodesEnginePayload() throws {
        let data = #"{"provider":"custom","models":["kimi-k2","kimi-latest"]}"#.data(using: .utf8)!

        let result = try EngineCoding.decoder.decode(TextLLMModelListResponse.self, from: data)

        XCTAssertEqual(result.provider, "custom")
        XCTAssertEqual(result.models, ["kimi-k2", "kimi-latest"])
    }

    func testGitHubDeviceOAuthPayloadsDecodeSnakeCase() throws {
        let deviceData = """
        {
          "device_code": "device-123",
          "user_code": "ABCD-EFGH",
          "verification_uri": "https://github.com/login/device",
          "verification_uri_complete": "https://github.com/login/device?user_code=ABCD-EFGH",
          "expires_in": 900,
          "interval": 5
        }
        """.data(using: .utf8)!
        let tokenData = """
        {
          "access_token": "gho_test",
          "refresh_token": "refresh",
          "token_type": "bearer",
          "scope": "read:user"
        }
        """.data(using: .utf8)!

        let device = try EngineCoding.decoder.decode(GitHubDeviceCodeResponse.self, from: deviceData)
        let token = try EngineCoding.decoder.decode(GitHubDeviceTokenResponse.self, from: tokenData)

        XCTAssertEqual(device.deviceCode, "device-123")
        XCTAssertEqual(device.userCode, "ABCD-EFGH")
        XCTAssertEqual(device.verificationUriComplete, "https://github.com/login/device?user_code=ABCD-EFGH")
        XCTAssertEqual(device.interval, 5)
        XCTAssertEqual(token.accessToken, "gho_test")
        XCTAssertEqual(token.refreshToken, "refresh")
    }

    func testCodexCLIAuthFileDecodesUsableTokens() throws {
        let data = """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "codex-access",
            "refresh_token": "codex-refresh",
            "account_id": "acct_123456"
          },
          "last_refresh": "2026-05-18T19:00:00Z"
        }
        """.data(using: .utf8)!

        let auth = try EngineCoding.decoder.decode(CodexCLIAuthFile.self, from: data)

        XCTAssertEqual(auth.authMode, "chatgpt")
        XCTAssertEqual(auth.usableTokens?.trimmedAccessToken, "codex-access")
        XCTAssertEqual(auth.usableTokens?.trimmedRefreshToken, "codex-refresh")
        XCTAssertEqual(auth.usableTokens?.accountId, "acct_123456")
    }

    func testAIHandoffResultDecodesEnginePayload() throws {
        let data = #"{"text":"Hi Jane, here is the update.","provider":"claude","model":"anthropic/claude-sonnet"}"#.data(using: .utf8)!

        let result = try EngineCoding.decoder.decode(AIHandoffResult.self, from: data)

        XCTAssertEqual(
            result,
            AIHandoffResult(
                text: "Hi Jane, here is the update.",
                provider: "claude",
                model: "anthropic/claude-sonnet"
            )
        )
    }

    func testConversationDetailDecodesEnginePayload() throws {
        let data = """
        {
          "session": {
            "id": "s1",
            "title": "Roadmap call",
            "started_at": "2026-05-17T08:00:00Z",
            "ended_at": null,
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": false
          },
          "segments": [
            {
              "id": "seg1",
              "session_id": "s1",
              "speaker_id": "speaker-1",
              "speaker_display_name": "Speaker 1",
              "start_ms": 18130,
              "end_ms": 21900,
              "text": "How many users did we have last year?",
              "state": "settled",
              "confidence": 0.91
            }
          ],
          "assist_cards": [
            {
              "id": "card1",
              "session_id": "s1",
              "kind": "answer",
              "title": "Answer Found",
              "body": "Last year we had 18,420 active users.",
              "source_references": ["Obsidian/adoption-2025.md"],
              "confidence": 0.78,
              "status": "active",
              "created_at": "2026-05-17T08:00:10Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let detail = try EngineCoding.decoder.decode(ConversationDetail.self, from: data)

        XCTAssertEqual(detail.session.id, "s1")
        XCTAssertEqual(detail.segments[0].speakerDisplayName, "Speaker 1")
        XCTAssertEqual(detail.assistCards[0].copyText, "Last year we had 18,420 active users.")
        XCTAssertEqual(detail.assistCards[0].sourceReferences, ["Obsidian/adoption-2025.md"])
    }

    func testConversationImportResultDecodesEnginePayload() throws {
        let data = #"{"status":"created","session_id":"s1","segments":2,"assist_cards":1}"#.data(using: .utf8)!

        let result = try EngineCoding.decoder.decode(ConversationImportResult.self, from: data)

        XCTAssertEqual(result.status, "created")
        XCTAssertEqual(result.sessionID, "s1")
        XCTAssertEqual(result.segments, 2)
        XCTAssertEqual(result.assistCards, 1)
    }

    func testConversationSessionCreateRequestEncodesSnakeCasePayload() throws {
        let request = ConversationSessionCreateRequest(
            title: "Roadmap call",
            captureMode: .microphoneOnly,
            asrProvider: "parakeet-tdt",
            diarizationProvider: "mock",
            externalProcessingEnabled: false
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["title"] as? String, "Roadmap call")
        XCTAssertEqual(object["capture_mode"] as? String, "microphone_only")
        XCTAssertEqual(object["asr_provider"] as? String, "parakeet-tdt")
        XCTAssertEqual(object["diarization_provider"] as? String, "mock")
        XCTAssertEqual(object["external_processing_enabled"] as? Bool, false)
    }

    func testConversationSegmentCreateRequestEncodesSpeakerIDAsSnakeCasePayload() throws {
        let request = ConversationSegmentCreateRequest(
            speakerID: "speaker-1",
            speakerDisplayName: "Speaker 1",
            startMs: 18_130,
            endMs: 21_900,
            text: "How many users did we have last year?",
            state: .settled,
            confidence: 0.91
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["speaker_id"] as? String, "speaker-1")
        XCTAssertEqual(object["speaker_display_name"] as? String, "Speaker 1")
        XCTAssertEqual(object["start_ms"] as? Int, 18_130)
        XCTAssertEqual(object["end_ms"] as? Int, 21_900)
        XCTAssertEqual(object["text"] as? String, "How many users did we have last year?")
        XCTAssertEqual(object["state"] as? String, "settled")
        XCTAssertEqual(object["confidence"] as? Double, 0.91)
        XCTAssertNil(object["speaker_i_d"])
    }

    func testConversationSegmentCreateRequestCanOmitSpeakerForLocalDiarization() throws {
        let request = ConversationSegmentCreateRequest(
            startMs: 18_130,
            endMs: 21_900,
            text: "How many users did we have last year?",
            state: .settled
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["speaker_id"])
        XCTAssertNil(object["speaker_display_name"])
        XCTAssertEqual(object["start_ms"] as? Int, 18_130)
        XCTAssertEqual(object["end_ms"] as? Int, 21_900)
        XCTAssertEqual(object["text"] as? String, "How many users did we have last year?")
        XCTAssertEqual(object["state"] as? String, "settled")
    }

    func testConversationSegmentCreateRequestCanCarryAudioForLocalDiarization() throws {
        let audio = Data("pcm-window".utf8)
        let request = ConversationSegmentCreateRequest(
            audioStartMs: 16_000,
            startMs: 18_130,
            endMs: 21_900,
            text: "How many users did we have last year?",
            state: .settled,
            audioPCMFloat32: audio,
            audioSampleRate: 16_000
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["audio_pcm_float32_base64"] as? String, audio.base64EncodedString())
        XCTAssertEqual(object["audio_sample_rate"] as? Int, 16_000)
        XCTAssertEqual(object["audio_start_ms"] as? Int, 16_000)
        XCTAssertNil(object["audio_p_c_m_float32_base64"])
    }

    func testConversationDetailUpdateRequestEncodesSpeakerNamesAndSegments() throws {
        let request = ConversationDetailUpdateRequest(
            title: "Edited roadmap call",
            speakerNames: ["speaker-1": "Mike"],
            segments: [
                ConversationSegmentUpdateRequest(id: "seg-1", text: "Edited line.")
            ]
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let speakerNames = try XCTUnwrap(object["speaker_names"] as? [String: String])
        let segments = try XCTUnwrap(object["segments"] as? [[String: Any]])

        XCTAssertEqual(object["title"] as? String, "Edited roadmap call")
        XCTAssertEqual(speakerNames["speaker-1"], "Mike")
        XCTAssertEqual(segments.first?["id"] as? String, "seg-1")
        XCTAssertEqual(segments.first?["text"] as? String, "Edited line.")
        XCTAssertNil(object["speakerNames"])
    }

    func testConversationAssistCardCreateRequestEncodesSourceReferencesAsSnakeCasePayload() throws {
        let request = ConversationAssistCardCreateRequest(
            kind: .answer,
            title: "Answer Found",
            body: "Last year we had 18,420 active users.",
            sourceReferences: ["Obsidian/adoption-2025.md"],
            confidence: 0.78
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["kind"] as? String, "answer")
        XCTAssertEqual(object["title"] as? String, "Answer Found")
        XCTAssertEqual(object["body"] as? String, "Last year we had 18,420 active users.")
        XCTAssertEqual(object["source_references"] as? [String], ["Obsidian/adoption-2025.md"])
        XCTAssertEqual(object["confidence"] as? Double, 0.78)
    }
}
