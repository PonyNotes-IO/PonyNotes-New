.PHONY: freeze_build watch validate_release_env release_env_build

freeze_build:
	dart run build_runner build -d

validate_release_env:
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate_release_env.ps1 -ProjectRoot .

release_env_build: freeze_build validate_release_env

watch:
	dart run build_runner watch
