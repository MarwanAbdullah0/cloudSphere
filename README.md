# Private GitLab Platform on Azure

A self-hosted GitLab platform deployed on Microsoft Azure for private source control, CI/CD, infrastructure management, and monitoring.

The platform provides development teams with a private environment for hosting repositories, reviewing code, running automated pipelines, and monitoring the infrastructure supporting the service.

## What It Provides

- **Private Git repositories** using GitLab CE
- **Merge Requests** for code review and collaboration
- **CI/CD pipelines** executed by a self-hosted GitLab Runner
- **Infrastructure monitoring** with Prometheus
- **Dashboards and metrics** through Grafana
- **Secure remote access** through an Azure VPN
- **Automated infrastructure provisioning** with Terraform
- **Persistent storage and backups** for application data

## How It Is Used

Users first connect to the Azure VPN to access the private environment.

Once connected, developers can use GitLab normally:

1. Create or join a GitLab project.
2. Clone the repository over HTTPS.
3. Create a branch and make changes.
4. Push the branch to GitLab.
5. Open a Merge Request for review.
6. GitLab automatically starts the configured CI/CD pipeline.
7. The GitLab Runner executes the pipeline jobs.
8. Approved changes can then be merged and deployed.

Infrastructure health and resource metrics can be viewed through Grafana.

## Architecture

The platform is divided into two main workloads:

**GitLab**
- GitLab Community Edition
- Repository and project management
- Merge Requests
- CI/CD coordination
- Node Exporter

**Monitoring & CI**
- GitLab Runner
- Prometheus
- Grafana
- Node Exporter

Both workloads run on Azure virtual machines inside a private Azure network and are accessed through VPN rather than public VM endpoints.

## Technology Stack

- Microsoft Azure
- Terraform
- Linux
- Docker & Docker Compose
- GitLab CE
- GitLab Runner
- Prometheus
- Grafana
- Azure VPN

## Project Status

The platform has been deployed and validated.

Core functionality including GitLab access, Git operations, CI/CD execution, monitoring, persistent storage, backups, and recovery has been tested successfully.# cloudSphere
