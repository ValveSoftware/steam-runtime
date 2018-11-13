all:
	@echo "Nothing to build."
	@echo "You probably want to run build-runtime.py instead, see README.md"

check:
	prove -v tests/*.py tests/*.sh
