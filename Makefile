all:
	@echo "Nothing to build."
	@echo "You probably want to run build-runtime.py instead, see README.md"

check:
	@set -e; \
	e=0; \
	for t in tests/*.py; do \
		echo "$$t..."; \
		if $$t; then \
			echo "$$t: PASS"; \
		else \
			echo "$$t: FAIL"; \
			e=1; \
		fi; \
	done; \
	exit $$e
