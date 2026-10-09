TF ?= terraform
PYTHON ?= python3

.PHONY: init fmt check check-licenses test
init:
	$(TF) init -backend=false -input=false

fmt:
	$(TF) fmt -recursive

check:
	$(TF) fmt -check -recursive
	$(TF) validate

check-licenses:
	$(PYTHON) scripts/check_licenses.py

test: check
	$(TF) test
