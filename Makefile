PWD := $(shell pwd)
BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H_%M_%SZ')
ARTIFACTS_OUTPUT_DIR := $(PWD)/tf-ansible-output
$(ARTIFACTS_OUTPUT_DIR):
	mkdir -p $(ARTIFACTS_OUTPUT_DIR)

TF_VAR_FILE := terraform.tfvars
init-tf:
	terraform init -input=false

apply-tf: init-tf $(ARTIFACTS_OUTPUT_DIR)
	terraform apply \
	-state=${ARTIFACTS_OUTPUT_DIR}/apply-tfout \
	-input=false \
	-auto-approve \
	-var-file=${TF_VAR_FILE}

output-tf: init-tf
	terraform output \
	-state=${ARTIFACTS_OUTPUT_DIR}/apply-tfout \
	-json > ${ARTIFACTS_OUTPUT_DIR}/output.json

ansible-playbook: apply-tf output-tf
	env ANSIBLE_LOG_PATH=${ARTIFACTS_OUTPUT_DIR}/ansible-${BUILD_DATE}.log \
	ansible-playbook ansible/private_mcc_infra.yaml \
	-i $(ARTIFACTS_OUTPUT_DIR)/ansible-inventory.yaml \
	-e "network_config_path=$(ARTIFACTS_OUTPUT_DIR)/output.json"

destroy-tf: init-tf $(ARTIFACTS_OUTPUT_DIR)
	terraform destroy \
	-state=${ARTIFACTS_OUTPUT_DIR}/apply-tfout \
	-state-out=${ARTIFACTS_OUTPUT_DIR}/destroy-tfout \
	-input=false \
	-auto-approve \
	-var-file=${TF_VAR_FILE}
