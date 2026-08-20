.PHONY: help demo demo-down demo-shell verify check lint

help:
	@echo "make demo        Start a throwaway Zabbix 7.4 lab and run the playbook"
	@echo "make demo-down   Remove the lab including its volumes"
	@echo "make demo-shell  Open a shell on the Ansible controller"
	@echo "make verify      Check that the lab hosts really report in encrypted"
	@echo "make check       Syntax-check both playbooks"
	@echo "make lint        Run ansible-lint if it is installed"

demo:
	@bash demo/run.sh

demo-down:
	@docker compose -f demo/docker-compose.yml down -v --remove-orphans

demo-shell:
	@docker compose -f demo/docker-compose.yml exec controller bash

verify:
	@bash demo/verify.sh

check:
	@ansible-playbook --syntax-check install_agent.yml update_config.yml

lint:
	@command -v ansible-lint >/dev/null && ansible-lint || echo "ansible-lint not installed - skipping"
