# VPN preparation and access

The reference network uses a P2S gateway with certificate authentication by default. Entra authentication is optional. VPN access gives a route to the services; users still need GitLab/Grafana accounts or SSH keys. The [SAD](SOLUTION_ARCHITECTURE.md) defines the access boundary.

## Certificate access

1. Create a VPN root CA and a separate client certificate per user following [Azure's certificate instructions](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-certificates-linux-openssl). Keep CA and client private keys in protected operator storage outside Git.
2. Put only the root's public PEM certificate at the local ignored path specified by `vpn_root_certificate_path`, relative to `terraform/`. The example is `../certs/vpn-root.crt`. This file is an input to Terraform, not a file to publish.
3. Review the Terraform plan, authorize deployment separately, and apply the gateway configuration with the rest of the infrastructure. For an existing gateway, confirm it updates in place and preserves existing access.
4. Generate the client configuration package from the gateway's Point-to-site configuration page. Configure the supported client for your OS with its assigned certificate and private key.
5. Test connection, routes, DNS, trusted GitLab HTTPS, Git clone/push, Grafana login, and authorized SSH. Keep profiles and test results private.

Never distribute a personal profile containing someone else's private key. Issue separate user credentials and maintain an operator revocation procedure. The Terraform root-certificate trust configuration does not automate per-user certificate revocation; reconcile any portal changes with Terraform before later applies.

## Optional Entra access

Use Microsoft's [custom audience instructions](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-register-custom-app) to create a dedicated VPN app in the intended tenant. Require user assignment on its enterprise application and assign approved users before enabling access. Follow the official instructions for client authorization and supported client configuration.

Set these values in ignored `terraform/terraform.tfvars`:

```hcl
vpn_entra_audience = "YOUR_CUSTOM_APP_CLIENT_ID"
entra_tenant_id    = "YOUR_TENANT_ID"
```

The configuration adds Entra alongside certificate authentication and switches to OpenVPN only. Review the plan for an in-place gateway update, keeping certificate access during migration. Generate a new Azure VPN Client profile after the change; keep gateway addresses, tenant details, and generated XML profiles outside the public repository.

Test one assigned user, one unassigned user who must be denied, and a guest if you intend to use guest access. Check current OS/client support in Microsoft's documentation before onboarding. A Windows VPN connection does not establish that WSL has the required routes: test from the shell where Git and SSH run. Validate sign-in policies separately if MFA is required.

## Client acceptance

With the VPN connected, use your own hostname and test project:

```bash
getent hosts gitlab.internal.example.com
curl -I https://gitlab.internal.example.com
ssh azureadmin@10.0.1.10
ssh azureadmin@10.0.3.10
git ls-remote https://gitlab.internal.example.com/YOUR_NAMESPACE/YOUR_PROJECT.git
```

The hostname should resolve to `10.0.1.10`; the VPN client should have a route to `10.0.0.0/16`. Use your OS's DNS/route tools if `getent` is unavailable. Open Grafana at `http://10.0.3.10:3000` through the VPN. Do not disable TLS verification to make checks pass. Configure private CA trust in the clients, Runner, and CI images when using a private CA.

All VPN clients can reach GitLab HTTPS, Grafana, and both SSH ports under these NSGs. Application accounts and authorized SSH keys enforce login permissions; this is not a separate developer/admin network. Removing a user's VPN access does not remove their GitLab account: offboard both. Git uses HTTPS; host port 22 stays reserved for administration.
