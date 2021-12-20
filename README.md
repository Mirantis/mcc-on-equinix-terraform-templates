# Container Cloud on Equinix Metal private net day0 infrastructure

Using the following instruction, apply the Terraform templates and Ansible
playbooks to set up a Mirantis Container Cloud Equinix Metal based
management cluster with private networking. During setup, the following
resources are created:

* The required amount of VLANs per each Container Cloud installation.
* The router that manages traffic between VLANs for management, regional,
  and managed clusters.
* The bootstrap (seed) node to bootstrap a management or regional cluster.

## To set up Container Cloud on Equinix Metal with private networking

1. Generate an SSH key to access the edge router and bootstrap node:

   ```bash
   ssh-keygen -f ssh_key -t ecdsa -b 521
   ```

   If you want to use the existing or generated key with a different name,
   provide paths for private and public parts of the key in the
   `ssh_private_key_path` and `ssh_public_key_path` variables respectively.

2. Optional. To reuse the Equinix key object for other deployments, create and
   apply the Equinix Metal `project SSH key`, for example,
   named `mcc_infra_access`:

   1. Log in to the Equinix Metal console.
   2. Select the project that you want to use for the Container Cloud deployment.
   3. In the "Project Settings" tab, select "Project SSH Keys"
      and click "Add New Key".
   4. Enter the "Key Name" and "Public Key" values and click "Add".
   5. Inject `ssh_key.pub` as the metadata to the created SSH key.
   6. Declare an additional variable in `terraform.tfvars`:
      `use_existing_ssh_key_name = "mcc_infra_access"`.

   Note that `ssh_private_key_path` and `ssh_public_key_path` should
   match metadata declared in the "Project SSH key" object.

3. Create the `terraform.tfvars` file with all required
   variables declared in `vars.tf`.

   * Specify the amount of VLANs required for Container Cloud as `vlans_amount`.
     If `deploy_seed` is set to `true`, one of VLANs will be automatically
     scoped as the management/regional one, and the bootstrap node will be
     placed on that VLAN.
   * Use the `terraform plan` command to output help messages for each required
     variable.

   ```bash
   export METAL_AUTH_TOKEN="XXXXXXXX"

   terraform init
   terraform plan
   terraform apply
   terraform output -json > output.json
   ```

   Review the following files that are generated using `terraform apply`:

   * `output.json` - contains all network specification to provide connectivity
     for all machines in scope of inter-VLAN operations, both for the edge
     router and bootstrap node. By default, the bootstrap node will have
     connectivity to all created VLANs through the edge router.
   * `ansible-inventory.yaml` - contains credentials to access the created nodes.

4. Run the following Ansible playbook that reconciles network configuration
   for the edge router, bootstrap node packages, and network management:

   ```bash
   ansible-lint ansible/private_mcc_infra.yaml

   ansible-playbook ansible/private_mcc_infra.yaml -vvv
   ```

5. Log in to the bootstrap node using the `ubuntu` user name and your specified
   SSH private key. Credentials and endpoints are located in
   `ansible-inventory.yaml`.

6. Bootstrap Container Cloud:

   1. [Download and run the Container Cloud bootstrap script](https://docs.mirantis.com/container-cloud/latest/qs-equinixv2/dwnld-bootstrap-script.html).
   2. [Obtain the Mirantis license](https://docs.mirantis.com/container-cloud/latest/qs-equinixv2/qs-equinixv2/obtain-license.html).
   3. [Verify the capacity of the Equinix Metal facility](https://docs.mirantis.com/container-cloud/latest/qs-equinixv2/qs-equinixv2/verify-capacity.html).
   4. [Prepare the Equinix Metal configuration](https://docs.mirantis.com/container-cloud/latest/qs-equinixv2/qs-equinixv2/conf-cluster-machines.html).
   5. [Finalize the bootstrap](https://docs.mirantis.com/container-cloud/latest/qs-equinixv2/qs-equinixv2/finalize-bootstrap.html).

7. When the bootstrap completes, re-run the playbook with
   the `mgmt_dhcp_addr` comma-separated addresses pointed to
   IP address(es) of the Ironic DHCP endpoint(s) placed
   in the management cluster:

   ```bash
   ansible-lint ansible/private_mcc_infra.yaml

   ansible-playbook ansible/private_mcc_infra.yaml \
   -e "isc_relay_dhcp_endpoint=${mgmt_dhcp_addr}" -vvv
   ```

   To obtain `mgmt_dhcp_addr`:

   ```bash
   kubectl --kubeconfig kubeconfig.yaml get machines -o yaml | grep privateIp
   ```

8. Optional. Delete the bootstrap node after a successful Container Cloud
   bootstrap. Keep the `vlans_amount` as is but set `deploy_seed` to `false`
   in `terraform.tfvars`:

   ```bash
   terraform plan
   terraform apply
   terraform output -json > output.json
   ```

9. Optional. If you delete the Container Cloud cluster, delete the
   Terraform template:

   ```bash
   terraform destroy
   ```
