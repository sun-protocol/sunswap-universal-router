# Contributing

This guide describes the GitHub release workflow for SunSwap Universal Router.

## Development and release responsibilities

Routine development, integration, review, and release validation take place
internally. GitHub receives a fixed version only after it has merged into the
internal stable branch (`main` or `master`). GitHub is the public
release and distribution surface; it is not a second day-to-day integration branch.

Community contributors can open an issue or PR here. Maintainers coordinate functional
changes through the internal integration process before including them in a GitHub
release. Do not ask contributors to disclose private repository contents or obtain
internal access to report an issue.
GitHub-specific documentation and release metadata can use focused PRs into `main`;
functional changes must retain an auditable internal release origin.

## Branch model

The default branch is `main`. Synchronize an approved internal release through one
`sync/*` PR directly into `main`. Existing `develop` and `release/*` branches are
retained for history, not used for routine release staging, and must not be deleted
or rewritten as part of this transition.

| Branch | Purpose | Pull request target |
| --- | --- | --- |
| `main` | Reviewed public release source and release documentation | — |
| `sync/<release-or-description>` | Import an approved internal release or patch | `main` |
| `docs/<description>` | GitHub-specific documentation and metadata | `main` |
| `release/vX.Y.Z` | Retained historical release branch | No routine updates |
| `develop` | Retained historical branch | No routine updates |

Create `sync/vX.Y.Z` (or a descriptive `sync/*` branch) from the latest GitHub
`main`, import the selected approved release increment, and open its PR directly
into `main`. A staging `release/*` branch and a second release-to-main PR are not
required. Internal release preparation and validation remain prerequisites.

An existing unmerged `sync/*` PR targeting `release/*` may be retargeted to `main`
after coordinating with its author and reviewing the resulting diff against `main`.
Preserve GitHub-specific content and revalidate if the new integration changes
tested behavior. Do not overwrite or delete historical branches during the transition.

## Review and merge policy

The following policy applies to `main` and retained `release/*` or `develop` branches:

- Changes must go through a PR; direct updates, force pushes, and branch deletion are prohibited.
- At least **two reviewers other than the PR author** must approve the final changes.
- Code-changing commits invalidate earlier approvals and require renewed review.
- Resolve all review conversations and blocking feedback before merging.
- Both `contract-dev` and `contract-maintain` may merge reviewed maintenance PRs targeting retained `release/*` branches.
- Only `contract-maintain` may merge PRs targeting `main` or retained `develop`.
- Merge authority does not waive approvals, validation, or review of the final revision.

GitHub enforces the PR, two-approval, stale-approval dismissal, last-push approval,
conversation-resolution, force-push, and deletion rules for these branches, with no
review-rule bypass actors. Both `contract-dev` and `contract-maintain` may update
`release/*` through PRs; only `contract-maintain` may update `main` or retained
`develop` through PRs. These exceptions to update restrictions apply only through
a PR and cannot bypass the separate review requirements. Existing creation
permissions for `release/*` remain in place but are not needed for the normal
synchronization flow. The `sync/*` to `main` release PR is restricted to
`contract-maintain` for merging.
The development team can also push unprotected feature branches, open PRs, and
participate in reviews. `main` is the default branch.
This document and PR checkboxes do not themselves enforce GitHub permissions.

Prefer merge commits for release synchronization so release lineage remains traceable.
Do not require linear history for a workflow that uses release merge commits. Squash
may be used for standalone documentation PRs when no shared release history is lost.
No new CI workflow or required status check is introduced by this policy. Review
existing workflow results and disclose failures; local validation remains required.

## Synchronize a release

1. Select the fixed internal stable commit after its release review and validation.
   Record the full source SHA, version, corresponding dependency revisions, and compatibility
   requirements in the internal release record.
2. Compare that source with GitHub `main` and any existing release PRs. GitHub-specific
   package metadata, dependency locations, documentation, and workflows may intentionally
   differ. Reconcile these differences explicitly; do not mirror or force-push blindly.
3. Create `sync/vX.Y.Z` from the latest GitHub `main` and import only the approved
   release increment. Do not publish internal CI/deployment
   configuration, secrets, private data, or unrelated development history. If commit
   history cannot be published, use a reviewed content import and retain internal provenance.
4. Open `sync/vX.Y.Z` → `main` directly. Include a public-safe scope summary, source-version
   provenance, validation results, intentional differences, and companion release order.
   Keep confidential source links and evidence in the internal release record.
5. Complete the validation below and obtain two non-author approvals. An authorized
   release maintainer merges the final reviewed revision. Revalidate if the final
   integration changes the tested behavior.
6. Create the immutable `vX.Y.Z` tag on the validated GitHub `main` commit and publish
   GitHub release notes with compatible versions and artifacts. Record both internal
   source SHA and GitHub release SHA in the internal release record; they may differ.
7. Track deployments or package publications separately. Return any functional fix
   discovered during GitHub review to the internal development process and produce
   an updated fixed release source.

Never move or overwrite a release tag. Use a new version for corrections. Do not
merge unrelated open PRs merely to make the repositories look identical.

## Local validation

Use the checked-in Hardhat/Sun Studio and Foundry configuration. Inspect lifecycle
scripts before installation and record the exact Node.js, package-manager, Foundry,
compiler, and dependency revisions used. From a clean checkout:

```sh
npm install
forge build
forge test -vvv
FOUNDRY_PROFILE=ci forge test -vvv
git diff --check
```

The `ci` Foundry profile is a local test profile, not a GitHub Actions configuration.
Run `forge fmt --check` for changed Solidity paths. If a lockfile is introduced,
validate it using the corresponding frozen installation command. Do not regenerate
dependencies solely for a documentation change. FFI-enabled tests may execute local
programs; use an isolated validation environment. Match TRON compilation and test-network
validation to the release's recorded compiler settings.

Current installation scripts still reference private dependencies. Public
source availability does not yet imply an independently reproducible public install.
Before a public release, verify accessible, fixed dependency revisions and document
any remaining access requirements. Dependency URL changes belong in a reviewed
companion PR; do not silently replace a dependency with a different revision.

For behavior changes, cover exact-input and exact-output boundaries, rounding,
insufficient liquidity, recipient/settlement handling, route encoding, and compatible
contract and SDK revisions as applicable. Security fixes should reproduce the failure
and demonstrate that valid operations still succeed. Documentation-only changes need
link/content review and `git diff --check`, not a full runtime test run.

## Pull request format

Use `type(scope): description`, for example:

```text
docs(release): clarify public release verification
fix(routing): validate exact-output settlement
```

Describe the problem and resulting behavior, the source version, intentional GitHub
adaptations, ABI/API or consumer impact, validation commands and results, companion
releases, and any uncompleted checks. Never mark a review or test checkbox complete
without evidence. Prefer one focused change per PR.

## Artifacts and publication

For contracts, archive ABI, creation/runtime bytecode, compiler and optimizer settings,
dependency revisions, linking and constructor arguments, checksums, test results, and
release notes. Track network deployments, addresses, transaction hashes, source
verification, and ownership separately. A source release does not update deployed contracts.

Never commit private keys, seed phrases, access tokens, or populated environment files.
Use separately authorized release credentials and verify the destination before publishing.

## Urgent fixes

Fix the affected version through the internal hotfix process first. Once merged into the
internal stable branch, synchronize the fixed patch release through a `sync/*` → `main` PR
with the same approval and validation requirements. Do not quietly create a second
source of truth by applying functional fixes only on GitHub. Track any deployment,
consumer upgrade, and return of the fix to the internal active branches separately.

## Reporting security issues

Report suspected vulnerabilities privately to the maintainers through an established
security contact channel. Do not post exploit details, keys, or private deployment
information in public issues or PRs. Include affected versions, impact, and a minimal
reproduction through the private channel.
