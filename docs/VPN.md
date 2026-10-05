<p align="center"><img src="assets/cloudsphere-logo.png" alt="cloudSphere logo" width="150"></p>

# Manage Entra ID VPN access

Use Azure point-to-site VPN with a dedicated Entra application for assigned Windows and macOS users. Users import a shared connection profile and sign in with their own account. Send them the [user guide](USER_GUIDE.md); they do not need personal VPN certificates.

## Access model

The encrypted tunnel gives users a network route. GitLab accounts/project roles, Grafana local login, and administrator SSH keys grant service permissions separately. Entra VPN sign-in does not enable application SSO or automatically enforce MFA.

| Client | Release support |
| --- | --- |
| Supported Windows Azure VPN Client | Primary user path |
| Supported macOS Azure VPN Client | Primary user path; validate on a real client before rollout |
| WSL through a Windows connection | Conditional on successful checks inside WSL |
| Native Linux, iOS, Android | Outside this release |

Microsoft retired Azure VPN Client for Linux on 31 August 2026. Use the current [client instructions](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-vpn-client) and [retirement guidance](https://learn.microsoft.com/en-us/azure/virtual-wan/azure-vpn-client-linux-retirement) when reviewing supported platforms.

## 1. Configure the dedicated application

For an existing installation, inspect its application and gateway before creating anything. Reuse the intended application; keep its tenant/client IDs in ignored operator configuration.

Follow Microsoft's [custom audience procedure](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-register-custom-app):

1. Register a single-tenant application in the company tenant, such as `cloudSphere VPN Access`.
2. Expose an enabled API scope with administrator consent.
3. Authorize the Microsoft-registered Azure VPN Client for that scope. For Azure Public, its client ID is `c632b3df-fb67-4d84-bdcf-b95ad541b5c8`; this is a published Microsoft identifier, not your custom audience.
4. In the corresponding enterprise application, set **Assignment required** to **Yes** and assign an approved test user.
5. Review the tenant's sign-in policies separately if MFA is required. Confirm licensing before using group assignment or Conditional Access.

Use **your dedicated application's client ID** as the gateway audience. Direct user assignment keeps the small installation simple. Follow Microsoft's [user assignment guidance](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-users-access).

## 2. Prepare the gateway configuration

Set these in ignored `terraform/terraform.tfvars`:

```hcl
vpn_entra_audience = "YOUR_CUSTOM_APP_CLIENT_ID"
entra_tenant_id    = "YOUR_TENANT_ID"
```

The current source adds Entra **alongside legacy certificate authentication**, uses OpenVPN only, and still reads `vpn_root_certificate_path`. Retain the existing public root certificate at that ignored path. For a fresh installation, the administrator must prepare that public trust input using [Azure's certificate procedure](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-certificates-linux-openssl); keep all private keys outside Git. Do not issue personal certificates to new users as part of this release's onboarding.

Review a fresh Terraform plan for an in-place gateway change and no VM replacement, following the [deployment guide](DEPLOYMENT_PLAN.md). Removing the retained certificate path requires an infrastructure change and a check that existing users still have access.

## 3. Generate and distribute the profile

After a P2S configuration change, download a fresh VPN client package from the gateway's **Point-to-site configuration** page. Use its Entra XML profile, commonly named `azurevpnconfig_aad.xml`.

For a custom audience, verify the profile's `<aad>` settings against [Microsoft's client instructions](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-vpn-client), including the Microsoft-registered client `<applicationid>` when required. Test the profile before distributing it. Keep generated profiles and deployment identifiers in private operator storage; distribute only through an approved internal channel.

## 4. Onboard a user

1. Approve the requested access. For an external collaborator, invite the correct B2B guest account and have them accept the invitation.
2. Assign that account to the dedicated VPN enterprise application.
3. Create or approve the separate GitLab local account and grant the required project role. Give Grafana access only if needed.
4. Supply the tested XML profile, GitLab URL, [user guide](USER_GUIDE.md), and support contact.
5. Confirm VPN connection, trusted GitLab HTTPS, GitLab login, and Git clone/push from the shell the user actually uses.

Users should not receive administrator SSH keys. Current NSGs allow all admitted VPN clients to reach both SSH ports and Grafana; keys and application accounts enforce login permissions. There is no separate administrator network segment.

## 5. Verify before rollout

Test an assigned user and an unassigned account; the latter must be denied. Test a guest if guests will use the service. Verify Windows and macOS independently; record WSL results separately.

Windows PowerShell, replacing the hostname:

```powershell
Resolve-DnsName gitlab.internal.example.com
Test-NetConnection gitlab.internal.example.com -Port 443
curl.exe -I --connect-timeout 10 https://gitlab.internal.example.com
git ls-remote https://gitlab.internal.example.com/YOUR_NAMESPACE/YOUR_PROJECT.git
```

macOS Terminal:

```bash
dscacheutil -q host -a name gitlab.internal.example.com
curl -I --connect-timeout 10 https://gitlab.internal.example.com
git ls-remote https://gitlab.internal.example.com/YOUR_NAMESPACE/YOUR_PROJECT.git
```

DNS should resolve the GitLab name to `10.0.1.10`, and the client needs a route to `10.0.0.0/16`. A successful port check alone is insufficient: verify HTTPS trust, application login, and a real push. Administrators additionally verify SSH to both VMs. Record evidence privately.

## 6. Remove access

Remove VPN application assignment and GitLab project/account access. Remove Grafana access and authorized SSH keys if the person had them. Review token revocation, existing VPN connections, application sessions, and guest account lifecycle under company policy; removing assignment alone does not establish that every existing session has ended.

Legacy certificate holders require certificate revocation too. Keep their inventory and revocation procedure privately, and reconcile gateway changes with Terraform. Preserve legacy access until its removal is explicitly reviewed and deployed.

[User guide](USER_GUIDE.md) · [Operations](OPERATIONS.md) · [Architecture](SOLUTION_ARCHITECTURE.md)
