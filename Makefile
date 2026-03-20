.PHONY: test test-syntax test-structure test-help test-version test-parse-results \
       test-detect-runner test-validate-numeric test-arg-parsing test-score-calc \
       test-url-matching test-shellcheck test-dry-run test-git-checks

SHELL := /bin/bash
SCRIPT := scripts/night-dev.sh
SKILL := SKILL.md
REFS := references

# Required reference files that SKILL.md dispatches to
REQUIRED_REFS := analyze-prompt.md planner-prompt.md implementation-prompt.md \
                 report-prompt.md research-prompt.md

test: test-syntax test-structure test-help test-version test-dry-run \
      test-parse-results test-detect-runner test-validate-numeric \
      test-arg-parsing test-score-calc test-url-matching test-git-checks test-shellcheck
	@echo ""
	@echo "═══ All tests passed ═══"

test-syntax:
	@echo "--- Syntax validation ---"
	@bash -n $(SCRIPT) && echo "PASS: night-dev.sh syntax OK"
	@# Validate all required files exist (only check if they exist in the skill)
	@for f in $(SCRIPT); do \
		if [ ! -s "$$f" ]; then \
			echo "FAIL: $$f is empty or missing"; exit 1; \
		fi; \
		echo "PASS: $$f exists and has content"; \
	done
	@# Check SKILL.md if it exists
	@if [ -f "$(SKILL)" ]; then \
		if [ ! -s "$(SKILL)" ]; then \
			echo "FAIL: $(SKILL) is empty"; exit 1; \
		fi; \
		echo "PASS: $(SKILL) exists and has content"; \
	else \
		echo "SKIP: $(SKILL) not yet created"; \
	fi
	@# Check reference files if they exist
	@for f in $(addprefix $(REFS)/,$(REQUIRED_REFS)); do \
		if [ -f "$$f" ]; then \
			if [ ! -s "$$f" ]; then \
				echo "FAIL: $$f is empty"; exit 1; \
			fi; \
			echo "PASS: $$f exists and has content"; \
		else \
			echo "SKIP: $$f not yet created"; \
		fi; \
	done

test-structure:
	@echo "--- Structure validation ---"
	@# SKILL.md must contain all phases (FASE 0 through FASE 6b) — only if SKILL.md exists
	@if [ -f "$(SKILL)" ]; then \
		for phase in "FASE 0" "FASE 1" "FASE 2" "FASE 3" "FASE 4" "FASE 5" "FASE 6" "FASE 6b"; do \
			if ! grep -q "$$phase" $(SKILL); then \
				echo "FAIL: $(SKILL) missing $$phase"; exit 1; \
			fi; \
			echo "PASS: $(SKILL) contains $$phase"; \
		done; \
	else \
		echo "SKIP: $(SKILL) not yet created, skipping phase checks"; \
	fi
	@# analyze-prompt.md must contain development opportunity categories — only if it exists
	@if [ -f "$(REFS)/analyze-prompt.md" ]; then \
		for cat in "SECURITY" "BUG" "PERFORMANCE" "ARCHITECTURE" "QUALITY"; do \
			if ! grep -qi "$$cat" $(REFS)/analyze-prompt.md; then \
				echo "FAIL: analyze-prompt.md missing category $$cat"; exit 1; \
			fi; \
			echo "PASS: analyze-prompt.md contains $$cat"; \
		done; \
	else \
		echo "SKIP: analyze-prompt.md not yet created"; \
	fi
	@# planner-prompt.md validation
	@if [ -f "$(REFS)/planner-prompt.md" ]; then \
		for cat in "TASK-" "risk" "score"; do \
			if ! grep -qi "$$cat" $(REFS)/planner-prompt.md; then \
				echo "FAIL: planner-prompt.md missing $$cat"; exit 1; \
			fi; \
			echo "PASS: planner-prompt.md contains $$cat"; \
		done; \
	else \
		echo "SKIP: planner-prompt.md not yet created"; \
	fi
	@# implementation-prompt.md validation
	@if [ -f "$(REFS)/implementation-prompt.md" ]; then \
		for cat in "test" "CodeIntel"; do \
			if ! grep -qi "$$cat" $(REFS)/implementation-prompt.md; then \
				echo "FAIL: implementation-prompt.md missing $$cat"; exit 1; \
			fi; \
			echo "PASS: implementation-prompt.md contains $$cat"; \
		done; \
	else \
		echo "SKIP: implementation-prompt.md not yet created"; \
	fi
	@# research-prompt.md validation
	@if [ -f "$(REFS)/research-prompt.md" ]; then \
		if ! grep -qi "search" $(REFS)/research-prompt.md; then \
			echo "FAIL: research-prompt.md missing search"; exit 1; \
		fi; \
		echo "PASS: research-prompt.md contains search"; \
	else \
		echo "SKIP: research-prompt.md not yet created"; \
	fi
	@# report-prompt.md validation
	@if [ -f "$(REFS)/report-prompt.md" ]; then \
		for cat in "changelog" "score"; do \
			if ! grep -qi "$$cat" $(REFS)/report-prompt.md; then \
				echo "FAIL: report-prompt.md missing $$cat"; exit 1; \
			fi; \
			echo "PASS: report-prompt.md contains $$cat"; \
		done; \
	else \
		echo "SKIP: report-prompt.md not yet created"; \
	fi

test-help:
	@echo "--- CLI validation ---"
	@# --help must exit 0 and show usage
	@bash $(SCRIPT) --help > /dev/null 2>&1 && echo "PASS: --help exits 0"
	@# --help must mention all flags and correctly omit --focus
	@HELP=$$(bash $(SCRIPT) --help 2>&1); \
	for flag in "--max-loops" "--hours" "--skip-research" "--push" "--verbose" "--follow" "--inline" "--dry-run" "--version"; do \
		if ! echo "$$HELP" | grep -q -- "$$flag"; then \
			echo "FAIL: --help missing $$flag"; exit 1; \
		fi; \
		echo "PASS: --help documents $$flag"; \
	done; \
	if echo "$$HELP" | grep -q -- "--focus"; then \
		echo "FAIL: --help should not contain --focus (Night Dev always does everything)"; exit 1; \
	fi; \
	echo "PASS: --help correctly omits --focus"

test-version:
	@echo "--- Version validation ---"
	@bash $(SCRIPT) --version | grep -q "1.0.0" && echo "PASS: --version outputs version"
	@bash $(SCRIPT) --version > /dev/null 2>&1 && echo "PASS: --version exits 0"

test-dry-run:
	@echo "--- Dry-run validation ---"
	@# --dry-run with a clean temp git repo should exit 0 and print confirmation
	@TMPDIR=$$(mktemp -d) && \
	cd "$$TMPDIR" && \
	git init -q && git commit --allow-empty -m "init" -q && \
	printf 'test:\n\t@echo ok\n' > Makefile && git add . && git commit -m "add Makefile" -q && \
	OUTPUT=$$(NO_COLOR=1 bash "$(CURDIR)/$(SCRIPT)" --dry-run "$$TMPDIR" 2>&1) && \
	echo "$$OUTPUT" | grep -q "Dry run complete" && \
	echo "PASS: --dry-run exits 0 and confirms pre-flight" && \
	rm -rf "$$TMPDIR" || { echo "FAIL: --dry-run did not complete successfully"; rm -rf "$$TMPDIR"; exit 1; }

test-parse-results:
	@echo "--- parse_test_results validation ---"
	@bash tests/test_parse_results.sh

test-detect-runner:
	@echo "--- detect_test_runner validation ---"
	@bash tests/test_detect_runner.sh

test-validate-numeric:
	@echo "--- validate_numeric_arg validation ---"
	@bash tests/test_validate_numeric.sh

test-arg-parsing:
	@echo "--- argument parsing validation ---"
	@bash tests/test_arg_parsing.sh

test-score-calc:
	@echo "--- score calculation validation ---"
	@bash tests/test_score_calc.sh

test-url-matching:
	@echo "--- URL matching validation ---"
	@bash tests/test_url_matching.sh

test-shellcheck:
	@echo "--- shellcheck validation ---"
	@command -v shellcheck >/dev/null 2>&1 || { echo "SKIP: shellcheck not installed"; exit 0; }; \
	shellcheck $(SCRIPT) && echo "PASS: shellcheck clean"

test-git-checks:
	@echo "--- git checks validation ---"
	@bash tests/test_git_checks.sh
