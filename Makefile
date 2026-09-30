# EvenPlate developer commands.
# Configuration lives in .env (copy .env.example). See README.md.

ENV_FILE ?= .env
DEFINES = --dart-define-from-file=$(ENV_FILE)

FN_ENV ?= supabase/.env.functions

.PHONY: help setup run run-release analyze format test check \
        build-apk build-appbundle build-ios build-ios-ipa secrets-push deploy-functions verify-db \
        test-webhook test-vision test-functions seed-chips

help:
	@echo "setup             Create .env from the template"
	@echo "run               Run the app in debug with .env configuration"
	@echo "run-release       Run the app in release with .env configuration"
	@echo "analyze           Static analysis"
	@echo "format            Format all Dart sources"
	@echo "test              Run the Flutter test suite"
	@echo "test-webhook      Run backend webhook verification tests"
	@echo "test-vision       Run vision response normalizer tests"
	@echo "test-functions    Run all edge function tests"
	@echo "check             format check + analyze + test"
	@echo "build-apk         Release APK, obfuscated with split debug symbols"
	@echo "build-appbundle   Release App Bundle for Play"
	@echo "build-ios         Release iOS build"
	@echo "build-ios-ipa     Signed iOS archive and IPA for a later submission"
	@echo "secrets-push      Upload edge function secrets from $(FN_ENV)"
	@echo "deploy-functions  Deploy Supabase edge functions"
	@echo "verify-db         Check entitlement hardening on the live project"
	@echo "seed-chips        Re-score pantry chips with live Gemini after a model change"

$(ENV_FILE):
	@cp .env.example $(ENV_FILE)
	@echo "Created $(ENV_FILE). Fill in the values, then re-run."

setup: $(ENV_FILE)

# Xcode 27 replaced Simulator.app with DeviceHub.app. `open -a Simulator`
# fails because that bundle no longer exists. flutter run can still attach
# to a booted runtime with no device window.
DEVICE_HUB = $(shell xcode-select -p)/../Applications/DeviceHub.app
SIMULATOR_APP = $(shell xcode-select -p)/Applications/Simulator.app

run: $(ENV_FILE)
	@if [ -d "$(DEVICE_HUB)" ]; then open "$(DEVICE_HUB)"; \
	elif [ -d "$(SIMULATOR_APP)" ]; then open "$(SIMULATOR_APP)"; fi
	flutter run $(DEFINES)

run-release: $(ENV_FILE)
	flutter run --release $(DEFINES)

analyze:
	flutter analyze

format:
	dart format lib test

test:
	flutter test

# Backend verification logic runs on Deno in production, so it is bundled and
# run under node here rather than through flutter test.
define run_deno_test
	@set -eu; \
	dir=$$(mktemp -d); \
	trap 'rm -rf "$$dir"' EXIT INT TERM; \
	npx -y esbuild@0.23.1 $(1) \
		--bundle --format=esm --platform=node \
		--outfile="$$dir/bundle.mjs" --log-level=warning; \
	node "$$dir/bundle.mjs"
endef

test-webhook:
	$(call run_deno_test,scripts/webhook_verification_test.ts)

test-vision:
	$(call run_deno_test,scripts/vision_schema_test.ts)
	$(call run_deno_test,scripts/gemini_failure_test.ts)
	$(call run_deno_test,scripts/analyze_sentry_test.ts)

test-functions: test-webhook test-vision
	$(call run_deno_test,scripts/nutrient_records_test.ts)
	$(call run_deno_test,scripts/device_check_test.ts)
	node scripts/function_integration_test.mjs
	node scripts/device_access_handler_test.mjs

# Live Gemini. Do not run in CI. Writes assets/pantry/gemini_chip_scores.json.
seed-chips:
	@set -eu; \
	dir=$$(mktemp -d); \
	trap 'rm -rf "$$dir"' EXIT INT TERM; \
	npx -y esbuild@0.23.1 scripts/seed_chip_scores.ts \
		--bundle --format=esm --platform=node \
		--outfile="$$dir/seed.mjs" --log-level=warning; \
	node "$$dir/seed.mjs"

check:
	python3 scripts/sync_legal_pages.py --check
	dart format --output=none --set-exit-if-changed lib test
	flutter analyze
	flutter test
	$(MAKE) test-functions

# Obfuscation and split debug info keep Dart symbols out of the shipped binary.
# Keep the symbols directory: it is required to symbolize crash reports.
build-apk: $(ENV_FILE)
	python3 scripts/validate_release_config.py android
	flutter build apk --release $(DEFINES) \
		--obfuscate --split-debug-info=build/symbols/android

build-appbundle: $(ENV_FILE)
	python3 scripts/validate_release_config.py android
	flutter build appbundle --release $(DEFINES) \
		--obfuscate --split-debug-info=build/symbols/android

build-ios: $(ENV_FILE)
	python3 scripts/validate_release_config.py ios
	ONESIGNAL_DISABLE_LOCATION=true flutter build ios --release $(DEFINES) \
		--obfuscate --split-debug-info=build/symbols/ios
	python3 scripts/verify_ios_location.py build/ios/iphoneos/Runner.app

build-ios-ipa: $(ENV_FILE)
	python3 scripts/validate_release_config.py ios
	ONESIGNAL_DISABLE_LOCATION=true flutter build ipa --release $(DEFINES) \
		--obfuscate --split-debug-info=build/symbols/ios
	python3 scripts/verify_ios_location.py build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app

# Pushes only the keys that actually have values, so a blank line in the file
# cannot clear a secret that is already set on the project. Values are passed in
# a 0600 temp file rather than on the command line, and only key names are shown.
secrets-push:
	@test -f $(FN_ENV) || { cp $(FN_ENV).example $(FN_ENV); \
		echo "Created $(FN_ENV). Fill in the values, then re-run."; exit 1; }
	@set -eu; \
	tmp=$$(mktemp -t evenplate_secrets); \
	trap 'rm -f "$$tmp"' EXIT INT TERM; \
	grep -E '^[A-Z_]+=.+' $(FN_ENV) > "$$tmp" || { \
		echo "No values set in $(FN_ENV)."; exit 1; }; \
	echo "Pushing: $$(cut -d= -f1 "$$tmp" | tr '\n' ' ')"; \
	supabase secrets set --env-file "$$tmp"

deploy-functions:
	python3 scripts/sync_legal_pages.py
	supabase functions deploy analyze-plate
	supabase functions deploy analyze-foods
	supabase functions deploy revenuecat-webhook
	supabase functions deploy delete-account
	supabase functions deploy reconcile-billing
	supabase functions deploy device-access
	supabase functions deploy legal

verify-db: test-db

# Runs all database assertions in a transaction and leaves no fixture data.
test-db:
	@set -eu; tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT INT TERM; \
	{ echo 'begin;'; cat supabase/schema.sql; echo 'update private.device_policy set enabled=false where singleton;'; cat scripts/database_regression.sql scripts/promo_regression.sql scripts/free_usage_regression.sql scripts/device_check_regression.sql; echo 'rollback;'; } > "$$tmp"; \
	supabase db query --linked --file "$$tmp"
