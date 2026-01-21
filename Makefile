.PHONY: test format lint check clean

PLENARY_DIR ?= /tmp/plenary.nvim

# Run tests with plenary
test: $(PLENARY_DIR)
	@echo "Running tests..."
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"

# Clone plenary if needed
$(PLENARY_DIR):
	@echo "Cloning plenary.nvim..."
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)

# Format code with stylua
format:
	@echo "Formatting Lua files..."
	stylua lua/ tests/

# Check formatting without modifying files
format-check:
	@echo "Checking Lua formatting..."
	stylua --check lua/ tests/

# Lint with selene
lint:
	@echo "Linting Lua files..."
	selene lua/ tests/

# Run all checks (format + lint)
check: format-check lint
	@echo "All checks passed!"

# Clean temporary files
clean:
	@echo "Cleaning up..."
	rm -rf $(PLENARY_DIR)
