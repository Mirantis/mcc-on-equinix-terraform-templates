# MCC Equinix private net day0 infrastructure

This terraform template will manage following setup:

1. Creates desired amount of VLAN's per each MCC installation
2. Creates inter-vlan router, seed node to provide mgmt-regional-child
   connectivity and allowes you to bootstrap MCC
3. You need to choose unique name for your edge router as `your_env_name`
4. Need to generate `ssh key` that will be used to access into
   edge router and seed node, and manage `ssh_private_key_path`,
   `ssh_public_key_path` variables.

```bash
ssh-keygen -f ssh_key -t ecdsa -b 521
```

   (Optionally) Create Equinix `Project SSH key` with name like
   `mcc_infra_access` and inject `ssh_key.pub` as metadata.
   It allowes to reuse Equinix key object for other deployments.
   To handle such scenario, need to declare additional variable
   for terraform `-var use_existing_ssh_key_name="mcc_infra_access"`
   Note that `ssh_private_key_path` and `ssh_public_key_path` should
   match metadata, declared in `Project SSH key' object`.

5. Form `terraform.tfvars` file with all required variables, declared
   in `vars.tf` file. Use `terraform plan` command to receive help messages for
   each required variable. You need to specify amount of VLAN's
   needed for MCC as `vlans_amount`. Pay attention,
   that if `deploy_seed` is true - one of vlans will be
   automatically scoped as management/regional and
   seed node will be placed there.

```bash
export METAL_AUTH_TOKEN="XXXXXXXX"

terraform init
terraform plan
terraform apply
```

6. As result of `terraform apply` - resources will be created and
   several files generated:
   `equinix_network_config.yaml` - contains all network
   specification to provide connectivity for all machines
   in scope of inter-vlan operations, both for edge router and the
   seed node. Note that by default seed node will have connectivity
   with all created vlans via edge-router.
   `ansible-hosts.ini` file contains credentials
   needed to access in created nodes. Review files before ansible
   playbook start

7. Ansible playbook will reconcile network config for edge router,
   seed node packages and network management.

```bash
ansible-lint ansible/private_mcc_infra.yaml

ansible-playbook ansible/private_mcc_infra.yaml \
-i ansible-hosts.ini \
-e "network_config_path=$(pwd)/equinix_network_config.yaml" -vvv
```

8. Login into seed node using `ubuntu` username and your specified
   ssh private key. Credentials and endpoints can be found in
   `ansible-hosts.ini`. Start MCC bootstrap.

9. After bootstrap, you need to re-run playbook with
   `mgmt_dhcp_addr` (or addresses comma-separated) pointed to
   IP address(es) of ironic dhcp endpoint(s) placed
   in the management cluster.

```bash
ansible-lint ansible/private_mcc_infra.yaml

ansible-playbook ansible/private_mcc_infra.yaml \
-i ansible-hosts.ini \
-e "network_config_path=$(pwd)/equinix_network_config.yaml" \
-e "isc_relay_dhcp_endpoint=${mgmt_dhcp_addr}" -vvv
```

10. Optionally you may delete the seed node after successful
    MCC bootstrap. Keep `vlans_amount` the same, but turn
    `deploy_seed` to `false`.

```bash
terraform plan -var deploy_seed=false
terraform apply -var deploy_seed=false
```

11. (optionally) Destroy terraform template in case of
    whole MCC cleanup.

```bash
terraform destroy
```
