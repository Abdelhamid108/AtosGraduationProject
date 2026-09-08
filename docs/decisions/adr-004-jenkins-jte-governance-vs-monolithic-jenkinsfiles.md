# ADR-004: Jenkins JTE Governance vs. Monolithic Jenkinsfiles

## Context
When building multiple applications and services, embedding large, custom `Jenkinsfile` scripts into every application repository leads to code duplication, configuration drift, and weak pipeline governance.

## Decision
We chose the **Jenkins Templating Engine (JTE)** to manage our CI/CD pipelines.

## Comparison

| Criteria | Monolithic Jenkinsfile | Jenkins Templating Engine (Selected) |
| :--- | :--- | :--- |
| **Pipeline Location** | 200+ lines of Groovy stored directly inside the application repository. | Centralized workflow template stored in the governance repository (`/home/devops/Atos/JTE`). |
| **Step Reusability** | Steps are copy-pasted across repositories. Fixing a bug requires editing every repo. | Common steps (`maven`, `sonar`, `trivy`, `docker`) are shared Groovy libraries in `libraries/`. |
| **Security Governance** | Developers can remove SonarQube or Trivy stages from their local Jenkinsfile. | Security gates and quality rules are mandatory parts of the template and cannot be bypassed. |
| **Repository Overhead** | Heavy Jenkinsfile maintenance for application developers. | Application repository only needs a short `pipeline_config.groovy` defining variables. |

## Implementation
- Governance repository: `/home/devops/Atos/JTE`
- Pipeline template: [`/home/devops/Atos/JTE/pipelines_templates/AtosGradProj/app_ci/Jenkinsfile`](file:///home/devops/Atos/JTE/pipelines_templates/AtosGradProj/app_ci/Jenkinsfile)
- Configuration: [`/home/devops/Atos/JTE/pipelines_templates/AtosGradProj/app_ci/pipeline_config.groovy`](file:///home/devops/Atos/JTE/pipelines_templates/AtosGradProj/app_ci/pipeline_config.groovy)

## Consequences
- Requires installing the Jenkins Templating Engine plugin on the Jenkins controller.
- Pipeline logic must be written as modular JTE steps rather than freeform inline shell scripts.
