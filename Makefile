TF_DIR := terraform

.PHONY: fmt init validate plan apply destroy

fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

init:
	terraform -chdir=$(TF_DIR) init

validate: init fmt
	terraform -chdir=$(TF_DIR) validate

plan: validate
	terraform -chdir=$(TF_DIR) plan

apply: validate
	terraform -chdir=$(TF_DIR) apply

destroy:
	terraform -chdir=$(TF_DIR) destroy
