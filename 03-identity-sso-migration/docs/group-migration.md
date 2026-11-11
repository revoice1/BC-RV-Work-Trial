# Group Migration: Keycloak & Google → Okta

> Part of [Phase 1 (inventory)](../PLAN.md#phase-1-discovery--analysis) and [Phase 2 (build)](../PLAN.md#phase-2-foundation). Sample groups match the [app inventory](../../app-inventory.md).
> Items marked **(proposed)** are recommended values to confirm with stakeholders; **[verify]** = confirm against vendor docs during the build.

## Principles

1. **Okta owns groups that grant access** (app assignments) and **org-structure groups** (all-company, department, location), pushing them to Google where they're also used as mailing lists.
2. **Google keeps collaboration-only groups**: project lists, shared mailboxes, ad-hoc team lists. They grant no app access, so they stay owned by their teams in Google.
3. **Baseline access comes from attribute rules** (Rippling `department`, `userType`, `countryCode`, etc.).
4. **Privileged groups are never rule-based.** Admin access (e.g., AWS admin) is assigned by hand, with approval, and reviewed quarterly. A department attribute shouldn't make anyone an admin.
5. **Rebuild membership, don't copy it.** Old groups carry stale members (the [assignment review](../../app-inventory.md#assignment-review) found 9 apps with the wrong people). Build the new group from rules, then **compare old vs. new membership** and have the owner approve the differences before cutover.
6. **Every rule excludes the Pre-start Limited Access group** ([04 ULM](../../04-hris-lifecycle-automation/PLAN.md#joiner-pre-start-access)).

## Naming Convention (proposed)

| Prefix | Purpose | Example | Membership |
| --- | --- | --- | --- |
| `all-` | Everyone of a type | `all-employees`, `all-contractors` | Rule |
| `dept-` | Department | `dept-engineering` | Rule |
| `loc-` | Region/location | `loc-emea` | Rule |
| `app-<app>-<role>` | App access | `app-aws-readonly`, `app-aws-admin` | Rule for baseline roles; **manual + approval** for admin roles |
| `sys-` | Okta system groups | `sys-prestart-limited`, `sys-test-users` | Workflow / manual |

## Key Groups (sample)

| Source group | Source | Used for today | Target in Okta | Membership | Pushed to Google? |
| --- | --- | --- | --- | --- | --- |
| `all@` | Google | Company-wide mailing list | `all-employees` | Rule: `userType = Employee` | Yes (keeps `all@`) |
| `eng@`, `sales@`, etc. | Google | Department mailing lists | `dept-*` | Rule: `department` | Yes |
| `eng-aws-readonly` | Keycloak | AWS read-only access | `app-aws-readonly` | Rule: `department = Engineering` | No |
| `eng-aws-admins` | Keycloak | AWS admin access | `app-aws-admin` | **Manual + approval**; quarterly review | No |
| `engineering@` | Keycloak | GitHub access (all repos) | `app-github-<team>` | Rule on team attribute, or owner-managed **(proposed)** | No |
| `recruiting@` | Keycloak | Greenhouse | `app-greenhouse-recruiting` | Rule: `department = Talent` | No |
| `hiring-managers@` | Keycloak | Greenhouse (hand-maintained, stale) | `app-greenhouse-hiring-managers` | Rule on a Rippling "is people manager" attribute **[verify]** | No |
| _(none: Slack domain sign-up)_ | — | Slack access | `all-employees` + `app-slack-contractors` | Rules | No |
| `support@` | Google | Shared mailbox | **Stays in Google** | Team-owned | n/a |
| Project / team lists | Google | Collaboration | **Stay in Google** | Team-owned | n/a |

## Pushing Groups to Google **[verify]**

- When Okta pushes a group to Google, **link it to the existing Google group** rather than creating a duplicate, so the address and history stay the same.
- After linking, **Okta owns the membership.** Changes made in Google get overwritten. Tell group owners before it happens.
- Push org-structure groups only. Collaboration groups stay unlinked.

## Steps

1. **Phase 1:** export groups and members from Keycloak and Google; tag each group as access, org-structure, privileged, or collaboration
2. **Phase 2:** create Okta groups and rules using the naming convention; privileged groups created empty
3. **Phase 2:** compare rule-built membership against the old groups; owners approve the differences
4. **Phase 2:** privileged group owners approve each admin member individually
5. **Phase 4:** link org-structure groups to Google at the Google cutover; app groups are assigned as each app cuts over
6. **After cutover:** archive the old Keycloak groups with Keycloak; collaboration groups in Google get owners confirmed during the access review
