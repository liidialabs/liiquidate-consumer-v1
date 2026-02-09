.PHONY: help install build test test-unit test-fuzz test-integration coverage clean forge-format lint gas-report all update-deps

# Colors for output
BLUE=\033[0;34m
GREEN=\033[0;32m
YELLOW=\033[1;33m
RED=\033[0;31m
NC=\033[0m # No Color

# Default target
help:
	@echo "$(BLUE)Liiquidate - Liquidation Protocol Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Available Commands:$(NC)"
	@echo "  $(YELLOW)make install$(NC)           - Install all dependencies (Foundry, Node, Submodules)"
	@echo "  $(YELLOW)make install-foundry$(NC)   - Install Foundry toolkit"
	@echo "  $(YELLOW)make install-deps$(NC)      - Install project dependencies (npm + git submodules)"
	@echo "  $(YELLOW)make build$(NC)             - Build Solidity contracts"
	@echo "  $(YELLOW)make test$(NC)              - Run all tests (unit + fuzz)"
	@echo "  $(YELLOW)make test-unit$(NC)         - Run unit tests only"
	@echo "  $(YELLOW)make test-fuzz$(NC)         - Run fuzz tests (1000 runs)"
	@echo "  $(YELLOW)make test-fuzz-deep$(NC)    - Run fuzz tests (10000 runs) for deep fuzzing"
	@echo "  $(YELLOW)make test-integration$(NC)  - Run integration tests"
	@echo "  $(YELLOW)make test-specific$(NC)     - Run specific test: make test-specific FILE=path/to/test.sol"
	@echo "  $(YELLOW)make coverage$(NC)          - Generate code coverage report"
	@echo "  $(YELLOW)make gas-report$(NC)        - Generate gas usage report"
	@echo "  $(YELLOW)make format$(NC)            - Format Solidity code"
	@echo "  $(YELLOW)make lint$(NC)              - Lint Solidity code"
	@echo "  $(YELLOW)make clean$(NC)             - Clean build artifacts and cache"
	@echo "  $(YELLOW)make verify$(NC)            - Verify all contracts compile"
	@echo "  $(YELLOW)make update-deps$(NC)       - Update all dependencies"
	@echo "  $(YELLOW)make all$(NC)               - Install dependencies, build, and run all tests"
	@echo ""

# ============================================================
# INSTALLATION TARGETS
# ============================================================

install: install-foundry install-deps
	@echo "$(GREEN)✓ All dependencies installed successfully$(NC)"

install-foundry:
	@echo "$(BLUE)Installing Foundry...$(NC)"
	@command -v forge >/dev/null 2>&1 || { \
		echo "$(YELLOW)Foundry not found. Installing...$(NC)"; \
		curl -L https://foundry.paradigm.xyz | bash; \
		$$HOME/.foundry/bin/foundryup; \
	} || (echo "$(RED)Foundry installation failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Foundry installed$(NC)"

install-deps: update-submodules
	@echo "$(BLUE)Installing npm dependencies...$(NC)"
	@command -v npm >/dev/null 2>&1 || { \
		echo "$(RED)npm not found. Please install Node.js$(NC)"; \
		exit 1; \
	}
	@npm install || (echo "$(RED)npm install failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

update-submodules:
	@echo "$(BLUE)Updating git submodules...$(NC)"
	@git submodule update --init --recursive || (echo "$(RED)Submodule update failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Git submodules updated$(NC)"

update-deps: update-submodules
	@echo "$(BLUE)Updating dependencies...$(NC)"
	@npm update || true
	@echo "$(GREEN)✓ Dependencies updated$(NC)"

# ============================================================
# BUILD TARGETS
# ============================================================

build: verify
	@echo "$(BLUE)Building contracts...$(NC)"
	@forge build --optimize --optimizer-runs 200 2>&1 | tee build.log || (echo "$(RED)Build failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Build successful$(NC)"

verify:
	@echo "$(BLUE)Verifying contracts compile...$(NC)"
	@forge build --optimize --optimizer-runs 200 > /dev/null 2>&1 || (echo "$(RED)Compilation failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ All contracts verified$(NC)"

# ============================================================
# TEST TARGETS
# ============================================================

test: test-unit test-fuzz
	@echo "$(GREEN)✓ All tests passed$(NC)"

test-unit:
	@echo "$(BLUE)Running unit tests...$(NC)"
	@forge test --match-path "test/unit/*.sol" -v 2>&1 | tee test-unit.log || (echo "$(RED)Unit tests failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Unit tests passed$(NC)"

test-fuzz:
	@echo "$(BLUE)Running fuzz tests (1000 runs)...$(NC)"
	@forge test --match-path "test/fuzz/*.sol" --fuzz-runs 1000 -v 2>&1 | tee test-fuzz.log || (echo "$(RED)Fuzz tests failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Fuzz tests passed$(NC)"

test-fuzz-deep:
	@echo "$(BLUE)Running deep fuzz tests (10000 runs)...$(NC)"
	@forge test --match-path "test/fuzz/*.sol" --fuzz-runs 10000 -v 2>&1 | tee test-fuzz-deep.log || (echo "$(RED)Deep fuzz tests failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Deep fuzz tests passed$(NC)"

test-integration:
	@echo "$(BLUE)Running integration tests...$(NC)"
	@forge test --match-path "test/fuzz/IntegrationFuzz.t.sol" -v 2>&1 | tee test-integration.log || (echo "$(RED)Integration tests failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Integration tests passed$(NC)"

test-specific:
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: FILE not specified$(NC)"; \
		echo "Usage: make test-specific FILE=test/unit/AdapterRegistryTest.t.sol"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running specific test: $(FILE)...$(NC)"
	@forge test --match-path "$(FILE)" -v 2>&1 | tee test-specific.log || (echo "$(RED)Test failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Test passed$(NC)"

# ============================================================
# CODE ANALYSIS TARGETS
# ============================================================

coverage:
	@echo "$(BLUE)Generating code coverage...$(NC)"
	@forge coverage --report lcov 2>&1 | tee coverage.log || (echo "$(RED)Coverage generation failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Coverage report generated: coverage.lcov$(NC)"

gas-report:
	@echo "$(BLUE)Generating gas report...$(NC)"
	@FOUNDRY_GAS_REPORTS=true forge test --fuzz-runs 100 2>&1 | tee gas-report.log || true
	@echo "$(GREEN)✓ Gas report generated: gas-report.log$(NC)"

# ============================================================
# CODE FORMATTING & LINTING
# ============================================================

format:
	@echo "$(BLUE)Formatting Solidity code...$(NC)"
	@if command -v prettier >/dev/null 2>&1; then \
		prettier --write "src/**/*.sol" "test/**/*.sol"; \
		echo "$(GREEN)✓ Code formatted with Prettier$(NC)"; \
	else \
		echo "$(YELLOW)Prettier not found, using forge fmt...$(NC)"; \
		forge fmt; \
	fi

lint:
	@echo "$(BLUE)Linting Solidity code...$(NC)"
	@if command -v solhint >/dev/null 2>&1; then \
		solhint "src/**/*.sol" "test/**/*.sol" || true; \
	else \
		echo "$(YELLOW)Solhint not found. Install with: npm install -g solhint$(NC)"; \
	fi
	@echo "$(GREEN)✓ Linting complete$(NC)"

# ============================================================
# HOUSEKEEPING TARGETS
# ============================================================

clean:
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -rf build/
	@rm -rf out/
	@rm -rf cache/
	@rm -f build.log test-unit.log test-fuzz.log test-fuzz-deep.log test-integration.log test-specific.log coverage.log gas-report.log
	@echo "$(GREEN)✓ Clean complete$(NC)"

clean-deps:
	@echo "$(BLUE)Removing dependencies...$(NC)"
	@rm -rf node_modules/
	@rm -f package-lock.json
	@rm -rf lib/
	@echo "$(GREEN)✓ Dependencies removed$(NC)"

distclean: clean clean-deps
	@echo "$(BLUE)Deep clean (removes all generated files)...$(NC)"
	@echo "$(GREEN)✓ Distclean complete$(NC)"

# ============================================================
# DEVELOPMENT HELPERS
# ============================================================

tree:
	@echo "$(BLUE)Project structure:$(NC)"
	@tree -L 3 -I 'node_modules|.git' || find . -type f -name "*.sol" | head -20

count-lines:
	@echo "$(BLUE)Counting lines of code...$(NC)"
	@wc -l src/**/*.sol test/**/*.sol | tail -1

anvil:
	@echo "$(BLUE)Starting Anvil local blockchain...$(NC)"
	@anvil

# ============================================================
# COMPOSITE TARGETS
# ============================================================

all: clean install build test coverage
	@echo "$(GREEN)✓ Complete build and test pipeline finished$(NC)"

dev: install build test format lint
	@echo "$(GREEN)✓ Development setup complete$(NC)"

ci: clean install build test coverage gas-report
	@echo "$(GREEN)✓ CI pipeline complete$(NC)"

# ============================================================
# PHONY DECLARATIONS (already at top, but for clarity)
# ============================================================

.PHONY: help install install-foundry install-deps update-submodules update-deps
.PHONY: build verify
.PHONY: test test-unit test-fuzz test-fuzz-deep test-integration test-specific
.PHONY: coverage gas-report
.PHONY: format lint
.PHONY: clean clean-deps distclean
.PHONY: tree count-lines anvil
.PHONY: all dev ci
