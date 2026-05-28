SNOWFLAKE_CONNECTION ?= MainAnthonyAccount

.PHONY: help run teardown clean logs

help:
	@echo "Usage: make [target]"
	@echo "  run        - Install/upgrade the app in dev mode"
	@echo "  teardown   - Remove the app and package"
	@echo "  clean      - Clean local build artifacts"
	@echo "  logs       - View app event logs"

run:
	snow app run -c $(SNOWFLAKE_CONNECTION)

logs-all:
	snow app events -c $(SNOWFLAKE_CONNECTION)

logs:
	@echo "Recent application events:"
	snow app events --since 1h -c $(SNOWFLAKE_CONNECTION)

teardown:
	snow app teardown -c $(SNOWFLAKE_CONNECTION) --force

clean:
	rm -rf .snow/ __pycache__/
	find . -name "*.pyc" -delete
