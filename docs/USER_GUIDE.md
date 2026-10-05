<p align="center"><img src="assets/cloudsphere-logo.png" alt="cloudSphere logo" width="150"></p>

# Get started with cloudSphere

Connect to your company's private network, open GitLab, and start working with your team's repositories. This guide covers supported Windows and macOS clients using Microsoft Entra ID VPN sign-in.

## Before you start

Ask your administrator for:

- Approval for your Entra account to use the VPN. Accept any guest invitation first.
- The company VPN profile, `azurevpnconfig_aad.xml`, through an approved internal channel.
- Your GitLab address, GitLab account setup instructions, and project access.
- A support contact. Ask for Grafana access separately if your role needs it.

The VPN profile contains connection settings; it should not contain a personal private key. You do not need to generate or install a VPN client certificate. VPN sign-in and GitLab login are separate.

## 1. Install Azure VPN Client

Install the official Azure VPN Client for your operating system:

- Windows: [Microsoft Store](https://apps.microsoft.com/detail/9np355qt2sqb).
- macOS: [Mac App Store](https://apps.apple.com/us/app/azure-vpn-client/id1553936137).

Use a currently supported OS/client combination from [Microsoft's client instructions](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-vpn-client). Native Linux and mobile VPN access are not supported by this release. WSL has the additional check below.

## 2. Import and connect

1. Save the profile your administrator supplied.
2. Open Azure VPN Client. Choose **Import** (under **+** on clients that show it), select the XML file, and save the connection.
3. Select **Connect**, sign in with the assigned Entra account, and complete any required sign-in prompts.
4. Wait for **Connected**, then open the GitLab address supplied by your administrator.
5. Sign in with your GitLab account. Open your assigned project.

Import the profile once. On later visits, connect the VPN and open GitLab. If the administrator changes the gateway settings, they may supply a replacement profile. Follow [Microsoft's instructions](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-vpn-client) if your client's controls differ.

## 3. Clone and push over HTTPS

Install Git on your workstation. In your GitLab project, copy **Code → Clone with HTTPS**. Run this in PowerShell, Terminal, or your supported development shell, replacing the example URL:

```bash
git clone https://gitlab.internal.example.com/YOUR_NAMESPACE/YOUR_PROJECT.git
cd YOUR_PROJECT
git checkout -b onboarding-check
# Edit a project file, then stage only the file you changed.
git add YOUR_CHANGED_FILE
git commit -m "Update project documentation"
git push -u origin onboarding-check
```

Open GitLab and create a merge request for your branch. Use a branch you are permitted to push to; protected branches may require review. Set your Git author name and email if this is your first commit on the workstation.

When Git asks for credentials, use your GitLab username. If a token is required, create a short-lived personal access token in GitLab with `read_repository` for cloning, or `write_repository` for pushing, and use it as the password. A token is required when GitLab two-factor authentication is enabled. Store it using your OS credential manager; never put it in a repository URL, script, or commit. See [GitLab's token guidance](https://docs.gitlab.com/user/profile/personal_access_tokens/).

Host port 22 is for VM administration. This release uses Git over HTTPS.

## Windows with WSL

Connect the VPN in Windows, then check access **inside WSL**, using your own hostname and repository:

```bash
curl -I --connect-timeout 10 https://gitlab.internal.example.com
git ls-remote https://gitlab.internal.example.com/YOUR_NAMESPACE/YOUR_PROJECT.git
```

WSL is usable only when these checks succeed with trusted HTTPS. If Windows works but WSL does not, use Windows Git/PowerShell and contact your administrator. Do not disable TLS verification or rely on an undocumented forwarding bridge.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| VPN sign-in is denied | Use the assigned account; accept the guest invitation if applicable. Ask the administrator to check application assignment and sign-in logs. |
| VPN connects, but GitLab does not open | Confirm the URL. Disconnect/reconnect once, then ask support to check DNS, routes, and GitLab health. |
| Browser reports a certificate warning | Stop and report the hostname and warning. Do not bypass it or turn off Git TLS verification. |
| GitLab login fails | Use your separate GitLab account; ask for account recovery if needed. |
| Git returns 401/403 or push is denied | Check token validity, repository permissions, and branch protection. |
| A CI job stays pending | The Runner serves one trusted project and may be busy. Ask a maintainer to check its tag, protected refs, and status. |
| Windows works; WSL fails | Use the WSL checks above and report the difference. |

When requesting help, include your OS, client version, time of failure, and error message. Do not send passwords, tokens, private keys, or VPN profiles to a public issue tracker.

## When you finish

Disconnect the VPN when you no longer need it. Keep your profile and credentials private. If a device or credential is lost, notify the administrator promptly so they can remove access.

[Back to cloudSphere](../README.md) · [VPN administration](VPN.md)
