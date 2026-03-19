.PHONY: test test-syntax test-structure test-help

SHELL := /bin/bash
SCRIPT := scripts/night-dev.sh
SKILL := SKILL.md
REFS := references

# Required reference files that SKILL.md dispatches to
REQUIRED_REFS := analyze-prompt.md planner-prompt.md implementation-prompt.md \
                 risk-gate-prompt.md report-prompt.md research-prompt.md \
                 codeintel-reference.md

test: test-syntax test-structure test-help
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

test-help:
	@echo "--- CLI validation ---"
	@# --help must exit 0 and show usage
	@bash $(SCRIPT) --help > /dev/null 2>&1 && echo "PASS: --help exits 0"
	@# --help must mention all flags
	@HELP=$$(bash $(SCRIPT) --help 2>&1); \
	for flag in "--max-loops" "--hours" "--skip-research" "--push" "--verbose" "--follow" "--inline"; do \
		if ! echo "$$HELP" | grep -q -- "$$flag"; then \
			echo "FAIL: --help missing $$flag"; exit 1; \
		fi; \
		echo "PASS: --help documents $$flag"; \
	done
	@# Verify --focus is NOT in help (Night Dev doesn't have it)
	@HELP=$$(bash $(SCRIPT) --help 2>&1); \
	if echo "$$HELP" | grep -q -- "--focus"; then \
		echo "FAIL: --help should not contain --focus (Night Dev always does everything)"; exit 1; \
	fi; \
	echo "PASS: --help correctly omits --focus"
