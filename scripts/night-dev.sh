#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"

# --- Constants ---
MAX_CLAUDE_TURNS=200          # Max conversation turns per Claude invocation
CIRCUIT_BREAKER_THRESHOLD=3   # Consecutive zero-applied loops before stopping
STAGNATION_THRESHOLD=2        # Consecutive loops without score improvement before stopping

# --- Defaults ---
MAX_LOOPS=5
MAX_HOURS=8
SKIP_RESEARCH=false
PROJECT_PATH=""
CLONE_BRANCH=""
IS_CLONED=false
AUTO_PUSH=false
VERBOSE=false
FOLLOW_MODE=false
INLINE_MODE=false
DRY_RUN=false
HAS_JQ=false

# --- Colors ---
# Respect NO_COLOR (https://no-color.org/) and non-TTY output
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
fi

# --- Usage ---
usage() {
    cat <<EOF
Night Dev v${VERSION} - Evolutionary software development agent

Usage: night-dev.sh <project-path-or-github-url> [OPTIONS]

Arguments:
  <project-path>          Local path to the project directory (must be a git repo)
  <github-url>            GitHub URL (https://github.com/user/repo) — will be cloned automatically

Options:
  --max-loops N           Maximum number of development loops (default: ${MAX_LOOPS})
  --hours H               Maximum hours to run (default: ${MAX_HOURS})
  --skip-research         Skip the research phase
  --branch BRANCH         Branch to checkout after clone (default: repo default branch)
  --push                  Auto-push to remote after each loop
  --verbose               Stream Claude output to terminal
  --follow <path>         Attach to a running Night Dev
  --inline                Run from inside Claude Code session
  --dry-run               Run pre-flight checks only, no worktree or Claude invocation
  --version               Show version and exit
  --help                  Show this help message
EOF
    exit 0
}

# --- GitHub URL Detection and Clone ---
resolve_project_path() {
    local input="$1"

    # Detect GitHub URLs (https or git@)
    if [[ "$input" =~ ^https?://github\.com/ ]] || [[ "$input" =~ ^git@github\.com: ]]; then
        echo -e "${CYAN}Detected GitHub URL: ${input}${NC}"

        # Extract repo name from URL
        local repo_name
        repo_name="${input##*/}"
        repo_name="${repo_name%.git}"

        # Validate repo name to prevent path traversal
        if [[ ! "$repo_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            echo "Error: Invalid repository name '${repo_name}'" >&2
            exit 1
        fi

        # Clone destination: ~/night-dev-repos/<repo-name>
        local clone_dir="$HOME/night-dev-repos/${repo_name}"

        if [[ -d "$clone_dir/.git" ]]; then
            echo -e "${YELLOW}Repository already cloned at ${clone_dir}. Pulling latest...${NC}"
            git -C "$clone_dir" fetch --all --prune 2>/dev/null || true
            git -C "$clone_dir" pull --ff-only 2>/dev/null || true
        else
            echo -e "${CYAN}Cloning ${input} to ${clone_dir}...${NC}"
            mkdir -p "$HOME/night-dev-repos"
            git clone -- "$input" "$clone_dir"
        fi

        # Checkout specific branch if requested
        if [[ -n "$CLONE_BRANCH" ]]; then
            echo -e "${CYAN}Checking out branch: ${CLONE_BRANCH}${NC}"
            git -C "$clone_dir" checkout "$CLONE_BRANCH" 2>/dev/null || \
            git -C "$clone_dir" checkout -b "$CLONE_BRANCH" "origin/$CLONE_BRANCH" 2>/dev/null || {
                echo -e "${RED}Error: Branch '${CLONE_BRANCH}' not found.${NC}" >&2
                exit 1
            }
        fi

        PROJECT_PATH="$clone_dir"
        IS_CLONED=true
        echo -e "${GREEN}Repository ready: ${PROJECT_PATH}${NC}"
    fi
}

# --- Argument Validation ---
validate_numeric_arg() {
    local flag="$1" value="${2:-}"
    if [[ -z "$value" ]]; then
        echo -e "${RED}Error: ${flag} requires a numeric argument${NC}" >&2
        exit 1
    fi
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: ${flag} requires a numeric argument${NC}" >&2
        exit 1
    fi
}

# --- Argument Parsing ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                usage
                ;;
            --version)
                echo "night-dev.sh ${VERSION}"
                exit 0
                ;;
            --max-loops)
                validate_numeric_arg "--max-loops" "${2:-}"
                if [[ "$2" -eq 0 ]]; then
                    echo -e "${RED}Error: --max-loops must be >= 1${NC}" >&2
                    exit 1
                fi
                MAX_LOOPS="$2"
                shift 2
                ;;
            --hours)
                validate_numeric_arg "--hours" "${2:-}"
                MAX_HOURS="$2"
                shift 2
                ;;
            --skip-research)
                SKIP_RESEARCH=true
                shift
                ;;
            --branch)
                if [[ -z "${2:-}" ]]; then
                    echo -e "${RED}Error: --branch requires a branch name${NC}" >&2
                    exit 1
                fi
                CLONE_BRANCH="$2"
                shift 2
                ;;
            --push)
                AUTO_PUSH=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --inline)
                INLINE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --follow)
                FOLLOW_MODE=true
                if [[ -n "${2:-}" ]] && [[ "${2:0:1}" != "-" ]]; then
                    PROJECT_PATH="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -*)
                echo -e "${RED}Error: Unknown option: $1${NC}" >&2
                echo "Run with --help for usage information." >&2
                exit 1
                ;;
            *)
                if [[ -z "$PROJECT_PATH" ]]; then
                    PROJECT_PATH="$1"
                else
                    echo -e "${RED}Error: Unexpected argument: $1${NC}" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # --- Follow Mode: attach to a running Night Dev ---
    if [[ "$FOLLOW_MODE" == "true" ]]; then
        follow_night_dev
        exit 0
    fi

    # Validate project path is provided
    if [[ -z "$PROJECT_PATH" ]]; then
        echo -e "${RED}Error: Project path or GitHub URL is required.${NC}" >&2
        echo "Run with --help for usage information." >&2
        exit 1
    fi

    # --- GitHub URL Detection and Clone ---
    resolve_project_path "$PROJECT_PATH"

    # Warn if --branch is used with a local path (only applies to GitHub URLs)
    if [[ -n "$CLONE_BRANCH" ]] && [[ "$IS_CLONED" != "true" ]]; then
        echo -e "${YELLOW}Warning: --branch is only used with GitHub URLs, ignoring for local path${NC}" >&2
    fi

    # Validate project path exists (for local paths or after clone)
    if [[ ! -d "$PROJECT_PATH" ]]; then
        echo -e "${RED}Error: Project path does not exist: ${PROJECT_PATH}${NC}" >&2
        exit 1
    fi

    # Resolve to absolute path (single fork: try readlink, fallback to cd+pwd)
    PROJECT_PATH=$(readlink -f "$PROJECT_PATH" 2>/dev/null) || PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)
}

# --- Pre-flight Checks ---

check_git_repo() {
    if ! git -C "$PROJECT_PATH" rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}Error: ${PROJECT_PATH} is not a git repository.${NC}" >&2
        exit 1
    fi
}

check_dirty_state() {
    if git -C "$PROJECT_PATH" status --porcelain 2>/dev/null | read -r _; then
        echo -e "${RED}Error: Working tree has uncommitted changes. Please commit or stash before running Night Dev.${NC}" >&2
        exit 1
    fi
}

detect_test_runner() {
    local project="$PROJECT_PATH"
    DETECTED_RUNNER=""

    # Python: pytest.ini
    if [[ -f "$project/pytest.ini" ]]; then
        DETECTED_RUNNER="pytest"
        return 0
    fi

    # Python: pyproject.toml [tool.pytest] — pure bash, no grep fork
    if [[ -f "$project/pyproject.toml" ]]; then
        local content
        content=$(<"$project/pyproject.toml")
        if [[ "$content" == *'[tool.pytest'* ]]; then
            DETECTED_RUNNER="pytest"
            return 0
        fi
    fi

    # Python: setup.cfg [tool:pytest] — pure bash, no grep fork
    if [[ -f "$project/setup.cfg" ]]; then
        local content
        content=$(<"$project/setup.cfg")
        if [[ "$content" == *'[tool:pytest]'* ]]; then
            DETECTED_RUNNER="pytest"
            return 0
        fi
    fi

    # Python: tox.ini
    if [[ -f "$project/tox.ini" ]]; then
        DETECTED_RUNNER="tox"
        return 0
    fi

    # Node: package.json with scripts.test (not the default placeholder) — pure bash, single read
    if [[ -f "$project/package.json" ]]; then
        local content
        content=$(<"$project/package.json")
        if [[ "$content" == *'"test"'* ]] && [[ "$content" != *'no test specified'* ]]; then
            DETECTED_RUNNER="npm test"
            return 0
        fi
    fi

    # Rust: Cargo.toml
    if [[ -f "$project/Cargo.toml" ]]; then
        DETECTED_RUNNER="cargo test"
        return 0
    fi

    # Generic: Makefile with test target (checked before Go to avoid expensive find)
    # Single-read pattern matching — consistent with package.json optimization
    if [[ -f "$project/Makefile" ]]; then
        local makefile_content
        makefile_content=$(<"$project/Makefile")
        if [[ "$makefile_content" =~ (^|$'\n')test[[:space:]]*: ]]; then
            DETECTED_RUNNER="make test"
            return 0
        fi
    fi

    # Go: *_test.go files (check root and common subdirectories, no find fork)
    local _go_found=false
    if compgen -G "$project"/*_test.go &>/dev/null; then
        _go_found=true
    else
        local _go_depth
        for _go_depth in "$project"/*/ "$project"/*/*/ "$project"/*/*/*/ "$project"/*/*/*/*/ "$project"/*/*/*/*/*/; do
            if compgen -G "${_go_depth}"*_test.go &>/dev/null 2>&1; then
                _go_found=true
                break
            fi
        done
    fi
    if [[ "$_go_found" == "true" ]]; then
        DETECTED_RUNNER="go test ./..."
        return 0
    fi

    # None found
    echo -e "${RED}Error: No supported test runner detected in ${project}.${NC}" >&2
    echo -e "Supported runners:" >&2
    echo -e "  - Python: pytest.ini, pyproject.toml [tool.pytest], setup.cfg [tool:pytest], tox.ini" >&2
    echo -e "  - Node:   package.json with scripts.test" >&2
    echo -e "  - Rust:   Cargo.toml" >&2
    echo -e "  - Go:     *_test.go files" >&2
    echo -e "  - Generic: Makefile with test target" >&2
    exit 1
}

check_claude_cli() {
    if ! command -v claude &>/dev/null; then
        echo -e "${RED}Error: 'claude' CLI not found. Please install Claude Code first.${NC}" >&2
        exit 1
    fi
}

check_jq() {
    if command -v jq &>/dev/null; then
        HAS_JQ=true
    else
        echo -e "${YELLOW}Warning: 'jq' not found. Some features may be limited.${NC}" >&2
    fi
}

# Parse test results from a test output file and extract counts
# Pure bash: tries pytest, jest, cargo patterns + coverage + duration (no awk fork)
# Sets global variables: _PARSE_PASSED, _PARSE_FAILED, _PARSE_TOTAL, _PARSE_COV, _PARSE_DUR
parse_test_results() {
    local test_output_file="$1"
    _PARSE_PASSED=0 _PARSE_FAILED=0 _PARSE_TOTAL=0 _PARSE_COV=0 _PARSE_DUR=0

    if [[ ! -f "$test_output_file" ]] || [[ ! -s "$test_output_file" ]]; then
        return
    fi

    local py_p=0 py_f=0 js_p=0 js_f=0 js_t=0 cg_p=0 cg_f=0 cov=0 dur=0
    local line word words
    while IFS= read -r line || [[ -n "$line" ]]; do
        # pytest-style: "X passed" / "X failed"
        if [[ "$line" == *passed* ]]; then
            read -ra words <<< "$line"
            for ((i=0; i<${#words[@]}-1; i++)); do
                [[ "${words[i+1]}" == passed* ]] && py_p="${words[i]}"
            done
        fi
        if [[ "$line" == *failed* ]]; then
            read -ra words <<< "$line"
            for ((i=0; i<${#words[@]}-1; i++)); do
                [[ "${words[i+1]}" == failed* ]] && py_f="${words[i]}"
            done
        fi
        # jest/vitest-style: "Tests: X passed, Y failed, Z total"
        if [[ "$line" == *Tests:*passed* ]]; then
            read -ra words <<< "$line"
            for ((i=0; i<${#words[@]}-1; i++)); do
                case "${words[i+1]}" in
                    "passed,") js_p="${words[i]}" ;;
                    "failed,") js_f="${words[i]}" ;;
                    "total")   js_t="${words[i]}" ;;
                esac
            done
        fi
        # cargo-style: "test result: ok. X passed; Y failed"
        if [[ "$line" == *"test result:"* ]]; then
            read -ra words <<< "$line"
            for ((i=0; i<${#words[@]}-1; i++)); do
                [[ "${words[i+1]}" == "passed;" ]] && cg_p="${words[i]}"
                [[ "${words[i+1]}" == failed* ]]   && cg_f="${words[i]}"
            done
        fi
        # coverage: line with "cover" and a percentage
        if [[ "$line" == *[Cc]over* ]] && [[ "$line" =~ ([0-9]+)(\.[0-9]+)?% ]]; then
            local pct="${BASH_REMATCH[1]}"
            (( pct > 0 )) && cov="$pct"
        fi
        # duration: line with time/duration/finished/ran/in and Ns
        if [[ "$line" =~ ([Tt]ime|[Dd]uration|[Ff]inished|[Rr]an|\ in\ ) ]] && [[ "$line" =~ ([0-9]+)(\.[0-9]+)?s ]]; then
            local secs="${BASH_REMATCH[1]}"
            (( secs > 0 )) && dur="$secs"
        fi
    done < "$test_output_file"

    # Priority: pytest > jest > cargo
    _PARSE_PASSED=$((py_p + 0)); _PARSE_FAILED=$((py_f + 0))
    if (( _PARSE_PASSED == 0 && _PARSE_FAILED == 0 )); then
        _PARSE_PASSED=$((js_p + 0)); _PARSE_FAILED=$((js_f + 0)); _PARSE_TOTAL=$((js_t + 0))
    fi
    if (( _PARSE_PASSED == 0 && _PARSE_FAILED == 0 )); then
        _PARSE_PASSED=$((cg_p + 0)); _PARSE_FAILED=$((cg_f + 0))
    fi
    (( _PARSE_TOTAL == 0 )) && _PARSE_TOTAL=$((_PARSE_PASSED + _PARSE_FAILED))
    _PARSE_COV=$((cov + 0)); _PARSE_DUR=$((dur + 0))
}

# Calculate composite score from test metrics (integer arithmetic, x10 precision)
# Sets: _CALC_SCORE (string like "123.4"), _CALC_SCORE_X10 (integer like 1234)
calculate_score() {
    local passing=$1 failing=$2 total=$3 coverage=$4 time_s=$5
    _CALC_SCORE_X10=$(( (passing * 100) + (total * 20) + (coverage * 50) - (failing * 200) - time_s ))
    local sign="" abs=$_CALC_SCORE_X10
    [[ $_CALC_SCORE_X10 -lt 0 ]] && { sign="-"; abs=$(( -_CALC_SCORE_X10 )); }
    _CALC_SCORE="${sign}$(( abs / 10 )).$(( abs % 10 ))"
}

# --- Banner ---
print_banner() {
    local research_status
    if [[ "$SKIP_RESEARCH" == "true" ]]; then
        research_status="SKIPPED"
    else
        research_status="ENABLED"
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Night Dev v${VERSION}${NC} — Evolutionary Development                 ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    local display_path="$PROJECT_PATH"
    if [[ ${#display_path} -gt 50 ]]; then
        display_path="...${display_path: -47}"
    fi
    echo -e "${CYAN}║${NC}  Project:       ${BOLD}${display_path}${NC}"
    if [[ "$IS_CLONED" == "true" ]]; then
    echo -e "${CYAN}║${NC}  Source:        ${YELLOW}GitHub clone${NC}"
    fi
    if [[ -n "$CLONE_BRANCH" ]]; then
    echo -e "${CYAN}║${NC}  Branch:        ${CLONE_BRANCH}"
    fi
    echo -e "${CYAN}║${NC}  Max loops:     ${MAX_LOOPS}"
    echo -e "${CYAN}║${NC}  Max hours:     ${MAX_HOURS}"
    echo -e "${CYAN}║${NC}  Research:      ${research_status}"
    local auto_push_display verbose_display
    if [[ "$AUTO_PUSH" = true ]]; then
        auto_push_display="${GREEN}ENABLED${NC}"
    else
        auto_push_display="disabled"
    fi
    if [[ "$VERBOSE" = true ]]; then
        verbose_display="${GREEN}LIVE STREAM${NC}"
    else
        verbose_display="silent (use --verbose or --follow)"
    fi
    echo -e "${CYAN}║${NC}  Auto-push:     ${auto_push_display}"
    echo -e "${CYAN}║${NC}  Verbose:       ${verbose_display}"
    echo -e "${CYAN}║${NC}  Test runner:   ${DETECTED_RUNNER}"
    echo -e "${CYAN}║${NC}  Score:         ${YELLOW}tracking enabled${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Pre-flight checks: PASSED${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- Follow Mode ---
follow_night_dev() {
    local search_path="${PROJECT_PATH:-.}"
    # Local has_jq: follow_night_dev() is called before check_jq() initializes global HAS_JQ
    local has_jq=false
    command -v jq &>/dev/null && has_jq=true

    # Find active Night Dev worktrees — find + bash loop to track newest (avoids sort/head/cut forks)
    local status_file="" _best_ts="0" _ts _path
    while IFS=' ' read -r _ts _path; do
        [[ "$_ts" > "$_best_ts" ]] && _best_ts="$_ts" && status_file="$_path"
    done < <(find "$search_path" "$HOME/night-dev-repos" -maxdepth 4 \
        -name "status.json" -path "*/.night-dev/*" -printf '%T@ %p\n' 2>/dev/null)

    if [[ -z "$status_file" ]]; then
        echo -e "${RED}No Night Dev instances found.${NC}"
        exit 1
    fi
    local nd_dir
    nd_dir="${status_file%/*}"

    # Single jq call extracts all needed fields (PERF-04: consolidate 3 jq forks into 1)
    local wt_path="" phase="" loop="" max_loops="" score="" current_loop_num=""
    if [[ "$has_jq" == "true" ]]; then
        local all_data
        all_data=$(jq -r '[.worktree_path // "", .phase // "", .current_loop // 0, .max_loops // 0, (.current_tests.score // "N/A")] | @tsv' "$status_file" 2>/dev/null)
        if [[ -n "$all_data" ]]; then
            IFS=$'\t' read -r wt_path phase loop max_loops score <<< "$all_data"
            current_loop_num="$loop"
        fi
    fi
    if [[ -z "${wt_path:-}" ]]; then
        wt_path="${nd_dir%/*}"
    fi

    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Night Dev — Live Monitor${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Worktree: ${wt_path}"
    if [[ -n "$phase" ]]; then
        echo -e "${CYAN}║${NC}  Phase:    ${BOLD}${phase}${NC}"
        echo -e "${CYAN}║${NC}  Loop:     ${loop} / ${max_loops}"
        echo -e "${CYAN}║${NC}  Score:    ${BOLD}${YELLOW}${score}${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local latest_log=""
    if [[ "$current_loop_num" =~ ^[0-9]+$ ]] && [[ "$current_loop_num" -gt 0 ]]; then
        local candidate="$nd_dir/loop-${current_loop_num}/claude_output.log"
        [[ -f "$candidate" ]] && latest_log="$candidate"
    fi
    # Fallback: find latest log via filesystem glob (no hardcoded upper bound)
    if [[ -z "$latest_log" ]]; then
        local candidate
        # Bash glob + arithmetic to find max loop number (avoids ls|sort|tail forks)
        local _max_loop=0 _loop_logs=("$nd_dir"/loop-*/claude_output.log)
        local _ll
        for _ll in "${_loop_logs[@]}"; do
            [[ -f "$_ll" ]] || continue
            local _num="${_ll##*loop-}"
            _num="${_num%%/*}"
            (( _num > _max_loop )) && _max_loop=$_num && latest_log="$_ll"
        done
    fi

    if [[ -z "$latest_log" ]]; then
        echo -e "${YELLOW}No output log yet. Waiting for first loop to start...${NC}"
        while true; do
            local current_loop_num="1"
            local _raw
            _raw=$(<"$status_file" 2>/dev/null) || _raw=""
            [[ "$_raw" =~ \"current_loop\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && current_loop_num="${BASH_REMATCH[1]}"
            latest_log="$nd_dir/loop-${current_loop_num}/claude_output.log"
            [[ -f "$latest_log" ]] && break
            latest_log=""
            sleep 2
        done
    fi

    echo -e "${GREEN}Streaming: ${latest_log}${NC}"
    echo -e "${YELLOW}Press Ctrl+C to detach (Night Dev keeps running)${NC}"
    echo ""

    # Tail with follow — switches to new log files as loops advance
    tail -f "$latest_log" &
    local tail_pid=$!

    # Monitor for new loop logs
    while kill -0 $tail_pid 2>/dev/null; do
        sleep 5
        local current_loop_num="" current_phase="" new_log=""
        # Bash regex extraction avoids jq fork every 5 seconds
        local _raw
        _raw=$(<"$status_file" 2>/dev/null) || _raw=""
        if [[ -n "$_raw" ]]; then
            [[ "$_raw" =~ \"current_loop\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && current_loop_num="${BASH_REMATCH[1]}"
            [[ "$_raw" =~ \"phase\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && current_phase="${BASH_REMATCH[1]}"
        fi
        if [[ "$current_loop_num" =~ ^[0-9]+$ ]]; then
            local candidate="$nd_dir/loop-${current_loop_num}/claude_output.log"
            [[ -f "$candidate" ]] && new_log="$candidate"
        fi
        if [[ "$new_log" != "$latest_log" ]] && [[ -n "$new_log" ]]; then
            # New loop started — switch tail
            kill $tail_pid 2>/dev/null || true
            wait $tail_pid 2>/dev/null || true
            latest_log="$new_log"
            local loop_num="$current_loop_num"
            echo ""
            echo -e "${CYAN}═══ Switching to Loop ${loop_num} ═══${NC}"
            echo ""
            tail -f "$latest_log" &
            tail_pid=$!
        fi

        # Check if Night Dev has completed
        if [[ "$current_phase" == "COMPLETED" ]]; then
            sleep 3  # Let tail flush remaining output
            kill $tail_pid 2>/dev/null || true
            echo ""
            echo -e "${GREEN}═══ Night Dev Completed ═══${NC}"
            if [[ "$has_jq" == "true" ]]; then
                printf '%s\n' "$(jq -r '"Applied: \(.stats.total_applied) | Skipped: \(.stats.total_skipped) | Reverted: \(.stats.total_reverted) | Score: \(.current_tests.score // "N/A")"' "$status_file")"
            fi
            break
        fi
    done
}

# --- Main ---
main() {
    parse_args "$@"

    # Pre-flight checks in order
    check_git_repo
    check_dirty_state
    detect_test_runner
    if [[ "$INLINE_MODE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        check_claude_cli
    fi
    check_jq

    print_banner

    # --- Dry Run Mode ---
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${GREEN}Dry run complete: pre-flight checks passed${NC}"
        exit 0
    fi

    # --- Variables Setup ---
    START_TIME=${EPOCHSECONDS:-$(date +%s)}
    printf -v DATE_TAG '%(%Y-%m-%d)T' "$START_TIME"
    BRANCH_NAME="night-dev/${DATE_TAG}"
    WORKTREE_PATH="${PROJECT_PATH}/.night-dev-worktree"
    ND_DIR="${WORKTREE_PATH}/.night-dev"
    SKILL_DIR="${NIGHT_DEV_SKILL_DIR:-$HOME/.claude/skills/night-dev}"
    DEADLINE=$((START_TIME + MAX_HOURS * 3600))
    _STATUS_TMP=""  # initialized after ND_DIR is created

    # --- Pre-run Backup ---
    # Create a full backup of the project before any changes
    BACKUP_DIR="${PROJECT_PATH}/.night-dev-backup-${DATE_TAG}"
    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "${YELLOW}Removing previous backup: ${BACKUP_DIR}${NC}"
        rm -rf "$BACKUP_DIR"
    fi
    echo -e "${CYAN}Creating pre-run backup...${NC}"
    # check_dirty_state guarantees clean worktree — no stash needed
    git -C "$PROJECT_PATH" clone --local "$PROJECT_PATH" "$BACKUP_DIR" 2>/dev/null
    echo -e "${GREEN}Backup created: ${BACKUP_DIR}${NC}"
    echo -e "${GREEN}To restore: rm -rf ${PROJECT_PATH} && mv ${BACKUP_DIR} ${PROJECT_PATH}${NC}"

    # --- Worktree Creation ---
    # Clean up existing worktree from previous failed run
    if [[ -d "$WORKTREE_PATH" ]]; then
        echo -e "${YELLOW}Cleaning up existing worktree...${NC}"
        git -C "$PROJECT_PATH" worktree remove --force "$WORKTREE_PATH" 2>/dev/null || true
        git -C "$PROJECT_PATH" worktree prune 2>/dev/null || true
    fi

    # Delete existing branch with same name (ignore errors)
    git -C "$PROJECT_PATH" branch -D "$BRANCH_NAME" 2>/dev/null || true

    # Create new worktree with dedicated branch
    git -C "$PROJECT_PATH" worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"

    # Create .night-dev directory inside worktree
    mkdir -p "$ND_DIR"
    _STATUS_TMP="${ND_DIR}/status.tmp.json"

    # --- status.json Initialization ---
    # ISO-8601 timestamps via printf (no forks)
    printf -v STARTED_AT '%(%Y-%m-%dT%H:%M:%S%z)T' "$START_TIME"
    printf -v DEADLINE_ISO '%(%Y-%m-%dT%H:%M:%S%z)T' "$DEADLINE"

    # Write initial status.json via heredoc (no jq fork — all values are pre-validated)
    cat > "$ND_DIR/status.json" <<EOSTATUS
{
  "version": "${VERSION}",
  "started_at": "${STARTED_AT}",
  "current_loop": 0,
  "max_loops": ${MAX_LOOPS},
  "max_hours": ${MAX_HOURS},
  "deadline": "${DEADLINE_ISO}",
  "branch": "${BRANCH_NAME}",
  "worktree_path": "${WORKTREE_PATH}",
  "test_runner": "${DETECTED_RUNNER}",
  "skip_research": ${SKIP_RESEARCH},
  "phase": "INITIALIZED",
  "current_task": "",
  "stats": {
    "total_applied": 0,
    "total_skipped": 0,
    "total_reverted": 0,
    "total_escalated": 0,
    "consecutive_zero_applied": 0
  },
  "baseline_tests": {
    "passing": 0,
    "failing": 0,
    "total": 0,
    "coverage": 0,
    "time_s": 0,
    "score": "0.0"
  },
  "current_tests": {
    "passing": 0,
    "failing": 0,
    "total": 0,
    "coverage": 0,
    "time_s": 0,
    "score": "0.0"
  },
  "score_history": [],
  "circuit_breaker": "CLOSED"
}
EOSTATUS

    echo -e "${GREEN}Worktree created: ${WORKTREE_PATH}${NC}"
    echo -e "${GREEN}Branch: ${BRANCH_NAME}${NC}"
    echo -e "${GREEN}Status: ${ND_DIR}/status.json${NC}"

    # --- CodeIntel indexing ---
    # Known issue: KuzuDB may segfault during cleanup (exit code 139) but data is saved correctly.
    # Use || true to prevent set -e from aborting on any exit code.
    CODEINTEL_AVAILABLE="false"
    if command -v npx &> /dev/null && [ -f "/root/firmamento-codeintel/src/cli/index.ts" ]; then
      echo -e "${CYAN}[CodeIntel] Indexing project...${NC}"
      if npx tsx /root/firmamento-codeintel/src/cli/index.ts analyze "$WORKTREE_PATH" --registry "$ND_DIR/codeintel-registry.json" 2>/dev/null; then
        CODEINTEL_AVAILABLE="true"
      fi
      echo -e "${GREEN}[CodeIntel] Indexing step complete (available: ${CODEINTEL_AVAILABLE}).${NC}"
    fi

    # --- Project-level permissions for claude -p sub-agents ---
    # Without this, claude -p sessions can't write files or run commands
    # Validate DETECTED_RUNNER against allowlist to prevent JSON injection via unquoted heredoc
    case "$DETECTED_RUNNER" in
      pytest|"npm test"|"cargo test"|"go test ./..."|"make test"|tox) ;;
      *) echo -e "${RED}Error: Unknown test runner '${DETECTED_RUNNER}' — cannot generate safe settings.json${NC}" >&2; exit 1 ;;
    esac
    local wt_claude_dir="${WORKTREE_PATH}/.claude"
    mkdir -p "$wt_claude_dir"
    cat > "$wt_claude_dir/settings.json" <<EOSETTINGS
{
  "permissions": {
    "allow": [
      "Bash(${DETECTED_RUNNER})",
      "Bash(${DETECTED_RUNNER} *)",
      "Bash(git *)",
      "Bash(cd *)",
      "Bash(ls *)",
      "Bash(wc *)",
      "Bash(cat *)",
      "Bash(mkdir *)",
      "Bash(find *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Grep(*)",
      "Glob(*)",
      "Agent(*)"
    ],
    "defaultMode": "auto"
  }
}
EOSETTINGS

    # Alias for prompt template
    TEST_RUNNER="$DETECTED_RUNNER"

    # --- Helper Functions ---

    # --- Cleanup Trap ---

    cleanup() {
      # Skip cleanup if main loop variables are not yet initialized
      [[ -n "${CURRENT_LOOP:-}" ]] || return 0
      echo ""
      echo "═══ Night Dev Terminated ═══"
      echo "Loops completed: $CURRENT_LOOP / $MAX_LOOPS"
      echo "Branch: $BRANCH_NAME"
      echo "Worktree: $WORKTREE_PATH"
      if [[ -d "${BACKUP_DIR:-}" ]]; then
        echo "Backup: $BACKUP_DIR"
      fi
      if [[ "$HAS_JQ" == "true" ]] && [[ -f "$ND_DIR/status.json" ]]; then
        # Batched cleanup: single jq call for circuit breaker + phase completion
        local jq_cleanup='.phase = "COMPLETED"'
        if [[ "${_CIRCUIT_BREAKER_TRIGGERED:-false}" == "true" ]]; then
          jq_cleanup='.circuit_breaker = "OPEN" | .phase = "COMPLETED"'
        fi
        local tmp="$_STATUS_TMP"
        jq "$jq_cleanup" "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
        # Extract score with bash regex instead of forking another jq
        local final_score="N/A" _raw
        _raw=$(<"$ND_DIR/status.json" 2>/dev/null) || _raw=""
        [[ "$_raw" =~ \"score\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && final_score="${BASH_REMATCH[1]}"
        echo "Final score: $final_score"
      fi
      echo ""
      if [[ -f "$ND_DIR/summary.md" ]]; then
        cat "$ND_DIR/summary.md"
      else
        echo "To review:  git diff main...$BRANCH_NAME"
        echo "To merge:   git checkout main && git merge $BRANCH_NAME"
        echo "To discard: git worktree remove $WORKTREE_PATH && git branch -D $BRANCH_NAME"
      fi
    }
    trap cleanup EXIT

    # --- Main Loop ---

    # Cache SKILL.md once — content does not change during execution
    local SKILL_CONTENT
    if [[ -f "${SKILL_DIR}/SKILL.md" ]]; then
        SKILL_CONTENT=$(<"${SKILL_DIR}/SKILL.md")
    else
        SKILL_CONTENT="ERROR: SKILL.md not found at ${SKILL_DIR}/SKILL.md"
    fi

    # Cache static parts of the prompt template (PERF-19)
    local _PROMPT_STATIC
    _PROMPT_STATIC="You are Night Dev, an evolutionary software development agent.

CONTEXT:
- Worktree: ${WORKTREE_PATH}
- Test runner: ${TEST_RUNNER}
- Skip research: ${SKIP_RESEARCH}
- Night dev dir: ${ND_DIR}
- CodeIntel available: ${CODEINTEL_AVAILABLE}

${SKILL_CONTENT}
"

    CURRENT_LOOP=0
    CONSECUTIVE_ZERO=0
    _CIRCUIT_BREAKER_TRIGGERED=false
    CONSECUTIVE_NO_IMPROVEMENT=0
    PREVIOUS_SCORE="0.0"
    PREVIOUS_SCORE_X10=0
    CACHED_PREV_APPLIED=""
    CACHED_PREV_REVERTED=""

    while true; do
      CURRENT_LOOP=$((CURRENT_LOOP + 1))

      # Exit: max loops
      if [[ $CURRENT_LOOP -gt $MAX_LOOPS ]]; then
        echo "Max loops ($MAX_LOOPS) reached. Stopping." >&2
        break
      fi

      # Exit: time limit
      NOW=${EPOCHSECONDS:-$(date +%s)}
      if [[ $NOW -ge $DEADLINE ]]; then
        echo "Time limit ($MAX_HOURS hours) reached. Stopping." >&2
        break
      fi

      # Exit: circuit breaker (3 consecutive loops with all implementations failing tests)
      if [[ $CONSECUTIVE_ZERO -ge $CIRCUIT_BREAKER_THRESHOLD ]]; then
        echo "Circuit breaker: $CIRCUIT_BREAKER_THRESHOLD consecutive loops with 0 successful changes. Stopping." >&2
        _CIRCUIT_BREAKER_TRIGGERED=true
        break
      fi

      # Exit: score stagnation (2 consecutive loops without score improvement)
      if [[ $CONSECUTIVE_NO_IMPROVEMENT -ge $STAGNATION_THRESHOLD ]]; then
        echo "Early exit: score hasn't improved for $STAGNATION_THRESHOLD consecutive loops. Stopping." >&2
        break
      fi

      # Exit: diminishing returns (previous loop applied 0 changes without reverts = nothing left)
      # Uses cached counts from previous loop's changelog parse (avoids re-parsing with awk)
      if [[ $CURRENT_LOOP -gt 1 ]] && [[ -n "$CACHED_PREV_APPLIED" ]]; then
        if [[ "$CACHED_PREV_APPLIED" -eq 0 ]] && [[ "$CACHED_PREV_REVERTED" -eq 0 ]]; then
          echo "Early exit: previous loop found nothing to improve. Stopping." >&2
          break
        fi
      fi

      # Update status (batched single jq call — sets phase directly to RUNNING CLAUDE)
      if [[ "$HAS_JQ" == "true" ]]; then
        local tmp="$_STATUS_TMP"
        jq --argjson cl "$CURRENT_LOOP" --arg ph "LOOP $CURRENT_LOOP — RUNNING CLAUDE" \
          '.current_loop = $cl | .phase = $ph' \
          "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
      fi

      REMAINING_SECS=$((DEADLINE - NOW))
      REMAINING_H=$((REMAINING_SECS / 3600))
      REMAINING_M=$(( (REMAINING_SECS % 3600) / 60 ))

      echo ""
      echo -e "═══ Loop $CURRENT_LOOP / $MAX_LOOPS ═══  ${YELLOW}Score: ${PREVIOUS_SCORE}${NC}"
      echo "Time remaining: ${REMAINING_H}h ${REMAINING_M}m"

      # Create loop directory
      LOOP_DIR="$ND_DIR/loop-${CURRENT_LOOP}"
      mkdir -p "$LOOP_DIR"

      # Pre-compute first-loop flag (avoids subshell fork in prompt heredoc)
      IS_FIRST_LOOP="false"
      [[ $CURRENT_LOOP -eq 1 ]] && IS_FIRST_LOOP="true"

      # Build prompt for Claude — read previous changelog for context
      PREV_CHANGELOG=""
      if [[ $CURRENT_LOOP -gt 1 ]] && [[ -f "$ND_DIR/loop-$((CURRENT_LOOP - 1))/changelog.md" ]]; then
        local prev_changelog_cached
        prev_changelog_cached=$(<"$ND_DIR/loop-$((CURRENT_LOOP - 1))/changelog.md")
        PREV_CHANGELOG="Previous loop changelog:
${prev_changelog_cached}"
      fi

      # Build prompt: static template first (avoids claude -p treating "- Loop:" as a CLI flag)
      LOOP_PROMPT="${_PROMPT_STATIC}

DYNAMIC CONTEXT:
- Loop: ${CURRENT_LOOP} / ${MAX_LOOPS}
- Loop directory: ${LOOP_DIR}
- Is first loop: ${IS_FIRST_LOOP}
- Previous score: ${PREVIOUS_SCORE}
${PREV_CHANGELOG}"

      # Invoke Claude
      if [[ "$INLINE_MODE" == "true" ]]; then
        # Inline mode: write prompt to file, wait for orchestrator to create 'done' marker
        echo "$LOOP_PROMPT" > "$LOOP_DIR/prompt.txt"
        echo "WAITING" > "$LOOP_DIR/inline_status"
        echo "Inline mode: prompt written to $LOOP_DIR/prompt.txt"
        echo "Waiting for orchestrator to process and create $LOOP_DIR/done ..."

        # Wait for done marker (check every 5 seconds, timeout after max_hours)
        while [[ ! -f "$LOOP_DIR/done" ]]; do
          sleep 5
          # Check time limit
          NOW=${EPOCHSECONDS:-$(date +%s)}
          if [[ $NOW -ge $DEADLINE ]]; then
            echo "Time limit reached while waiting for inline processing."
            echo "TIMEOUT" > "$LOOP_DIR/inline_status"
            break
          fi
        done
        # Only write DONE if the loop completed normally (not on TIMEOUT)
        [[ -f "$LOOP_DIR/done" ]] && echo "DONE" > "$LOOP_DIR/inline_status"

        # Guard: inline mode may finish without producing claude_output.log
        if [[ ! -s "$LOOP_DIR/claude_output.log" ]]; then
          echo -e "${YELLOW}WARNING: Inline mode produced no output. Skipping score calculation.${NC}" >&2
          CONSECUTIVE_ZERO=$((CONSECUTIVE_ZERO + 1))
          APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0
          if [[ "$HAS_JQ" == "true" ]]; then
            local tmp="$_STATUS_TMP"
            jq --argjson cz "$CONSECUTIVE_ZERO" \
               '.stats.consecutive_zero_applied = $cz' \
               "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
          fi
          continue
        fi
      else
        echo "Invoking Claude for loop $CURRENT_LOOP..."
        local claude_cmd=(claude -p "$LOOP_PROMPT" --max-turns "$MAX_CLAUDE_TURNS" --permission-mode auto)
        local claude_exit=0
        if [[ "$VERBOSE" == "true" ]]; then
          # Stream output to terminal AND log file simultaneously
          # Use PIPESTATUS[0] to capture Claude's exit code, not tee's
          set +e
          (cd "$WORKTREE_PATH" && "${claude_cmd[@]}" 2>"$LOOP_DIR/claude_stderr.log") \
            | tee "$LOOP_DIR/claude_output.log"
          claude_exit=${PIPESTATUS[0]}
          set -e
        else
          (cd "$WORKTREE_PATH" && "${claude_cmd[@]}") \
            > "$LOOP_DIR/claude_output.log" 2>"$LOOP_DIR/claude_stderr.log" || claude_exit=$?
        fi

        if [[ $claude_exit -ne 0 ]] || [[ ! -s "$LOOP_DIR/claude_output.log" ]]; then
          echo -e "${YELLOW}WARNING: Claude invocation failed (exit=$claude_exit). Skipping score calculation.${NC}" >&2
          CONSECUTIVE_ZERO=$((CONSECUTIVE_ZERO + 1))
          APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0
          # Persist consecutive_zero to status.json so it survives script kill between loops
          if [[ "$HAS_JQ" == "true" ]]; then
            local tmp="$_STATUS_TMP"
            jq --argjson cz "$CONSECUTIVE_ZERO" \
               '.stats.consecutive_zero_applied = $cz' \
               "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
          fi
          continue
        fi
      fi

      # --- Score Calculation ---
      # Parse test results from Claude output or test log
      local test_output="$LOOP_DIR/claude_output.log"
      if [[ -f "$LOOP_DIR/test_results.log" ]]; then
        test_output="$LOOP_DIR/test_results.log"
      fi

      parse_test_results "$test_output"
      local cur_passing=$_PARSE_PASSED cur_failing=$_PARSE_FAILED cur_total=$_PARSE_TOTAL
      local cur_coverage=$_PARSE_COV cur_time_s=$_PARSE_DUR

      # Score calculation (test_health dimension)
      # code_quality and architecture_quality (per SKILL.md) are evaluated by
      # the Claude sub-agent in analysis.md, not by this bash wrapper.
      calculate_score "$cur_passing" "$cur_failing" "$cur_total" "$cur_coverage" "$cur_time_s"
      local score_x10=$_CALC_SCORE_X10
      local current_score="$_CALC_SCORE"

      echo -e "Score: ${YELLOW}${current_score}${NC} (passing=${cur_passing}, failing=${cur_failing}, total=${cur_total}, coverage=${cur_coverage}%)"

      # Defer status.json updates — batch all jq calls into one at end of loop iteration

      # Check score improvement using raw x10 integers (handles negative scores correctly)
      local improved="no"
      if (( score_x10 > PREVIOUS_SCORE_X10 )); then
        improved="yes"
      fi
      if [[ "$improved" == "yes" ]]; then
        CONSECUTIVE_NO_IMPROVEMENT=0
        echo -e "${GREEN}Score improved: ${PREVIOUS_SCORE} -> ${current_score}${NC}"
      else
        CONSECUTIVE_NO_IMPROVEMENT=$((CONSECUTIVE_NO_IMPROVEMENT + 1))
        echo -e "${YELLOW}Score did not improve (${CONSECUTIVE_NO_IMPROVEMENT}/${STAGNATION_THRESHOLD} stagnant loops)${NC}"
      fi
      PREVIOUS_SCORE="$current_score"
      PREVIOUS_SCORE_X10=$score_x10

      # Single-pass changelog parsing — pure bash pattern matching
      if [[ -f "$LOOP_DIR/changelog.md" ]]; then
        APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0
        local _cl_line
        while IFS= read -r _cl_line; do
          case "$_cl_line" in
            *"- APPLICATA"*|*"APPLICATA:"*)   APPLIED=$((APPLIED + 1)) ;;
            *"- SKIPPATA"*|*"SKIPPATA:"*)     SKIPPED=$((SKIPPED + 1)) ;;
            *"- REVERTITA"*|*"REVERTITA:"*)   REVERTED=$((REVERTED + 1)) ;;
            *"- ESCALATED"*|*"- URGENTE"*|*"ESCALATED:"*|*"URGENTE:"*)
              ESCALATED=$((ESCALATED + 1)) ;;
          esac
        done < "$LOOP_DIR/changelog.md"

        # Cache for next iteration's early-exit check (avoids re-parsing)
        CACHED_PREV_APPLIED="$APPLIED"
        CACHED_PREV_REVERTED="$REVERTED"

        echo "Loop $CURRENT_LOOP results: applied=$APPLIED, skipped=$SKIPPED, reverted=$REVERTED, escalated=$ESCALATED"

        if [[ "$APPLIED" -eq 0 ]]; then
          if [[ "$REVERTED" -gt 0 ]]; then
            # Changes attempted but all failed tests = circuit breaker signal
            CONSECUTIVE_ZERO=$((CONSECUTIVE_ZERO + 1))
            echo "WARNING: All changes failed tests. Consecutive zero: $CONSECUTIVE_ZERO/3"
          else
            # Nothing attempted or only skipped = reset counter (not a failure)
            CONSECUTIVE_ZERO=0
          fi
        else
          CONSECUTIVE_ZERO=0
        fi

      else
        echo "WARNING: Loop $CURRENT_LOOP did not produce changelog. Claude may have errored." >&2
        echo "Check: $LOOP_DIR/claude_stderr.log" >&2
        if [[ -f "$LOOP_DIR/claude_stderr.log" ]] && [[ -s "$LOOP_DIR/claude_stderr.log" ]]; then
          echo "HINT: claude_stderr.log is non-empty — possible permission or runtime error:" >&2
          tail -5 "$LOOP_DIR/claude_stderr.log" >&2
        fi
        CONSECUTIVE_ZERO=$((CONSECUTIVE_ZERO + 1))
        APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0
      fi

      # Batched status.json update — single jq call for scores, history, and stats
      if [[ "$HAS_JQ" == "true" ]]; then
        local tmp="$_STATUS_TMP"
        local jq_expr='.current_tests = {passing: $p, failing: $f, total: $t, coverage: $c, time_s: $ts, score: $s}
          | .score_history += [{loop: $l, score: $s}]
          | .stats.total_applied += $a
          | .stats.total_skipped += $sk
          | .stats.total_reverted += $r
          | .stats.total_escalated += $e
          | .stats.consecutive_zero_applied = $cz'
        # On first loop, also set baseline
        if [[ $CURRENT_LOOP -eq 1 ]]; then
          jq_expr=".baseline_tests = {passing: \$p, failing: \$f, total: \$t, coverage: \$c, time_s: \$ts, score: \$s} | ${jq_expr}"
        fi
        jq --argjson p "$cur_passing" --argjson f "$cur_failing" --argjson t "$cur_total" \
           --argjson c "$cur_coverage" --argjson ts "$cur_time_s" --arg s "$current_score" \
           --argjson l "$CURRENT_LOOP" \
           --argjson a "${APPLIED:-0}" --argjson sk "${SKIPPED:-0}" \
           --argjson r "${REVERTED:-0}" --argjson e "${ESCALATED:-0}" \
           --argjson cz "$CONSECUTIVE_ZERO" \
           "$jq_expr" "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
      fi

      # --- Push to remote if --push enabled ---
      if [[ "$AUTO_PUSH" == "true" ]]; then
        echo -e "${CYAN}Pushing to remote: origin/$BRANCH_NAME${NC}"
        if git -C "$WORKTREE_PATH" push origin "$BRANCH_NAME" 2>/dev/null; then
          echo -e "${GREEN}Push successful.${NC}"
        else
          # First push — need to set upstream
          git -C "$WORKTREE_PATH" push -u origin "$BRANCH_NAME" 2>/dev/null || \
            echo -e "${YELLOW}WARNING: Push failed. Check remote access.${NC}"
        fi
      fi

      echo "═══ Loop $CURRENT_LOOP complete ═══"
    done
}

# Allow sourcing without triggering main (enables unit testing of functions)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
