SCHEME ?= chibi-scheme

.PHONY: test generate demo

test:
	$(SCHEME) tests/report.scm
	$(SCHEME) tests/run.scm
	$(SCHEME) tests/restart.scm

generate:
	$(SCHEME) generate.scm $(ARGS)

demo:
	$(SCHEME) run-calc.scm generated/calc.scm < examples/arithmetic.scm
