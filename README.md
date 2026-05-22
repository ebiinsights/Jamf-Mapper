# Jamf Mapper

Jamf Mapper is a native macOS application for Jamf Pro administrators who need a clear, local-first view of how Jamf objects depend on each other. It connects to Jamf Pro with OAuth client credentials, crawls read-only configuration data, stores snapshots in local SQLite, and presents object relationships by name and ID so admins can audit scope, cleanup risk, and stale configuration safely.

![Jamf Mapper login screen](docs/screenshot.png)

## What It Does

- Connects to Jamf Cloud or on-prem Jamf Pro tenants with API Client ID and Client Secret.
- Stores API client secrets in macOS Keychain, not in source files, UserDefaults, or SQLite.
- Crawls Jamf objects into local snapshots so each crawl is auditable and repeatable.
- Maps relationships between policies, smart groups, static groups, extension attributes, scripts, packages, categories, profiles, patch objects, prestages, and other supported objects.
- Shows dependencies in an inspector view with "Depends On" and "Used By" sections.
- Shows IDs, object names, scope counts, enabled/disabled state where applicable, and direct "Open in Jamf Pro" links.
- Provides script source previews for Jamf scripts and script-backed extension attributes after a fresh crawl.
- Provides audit reports for orphaned objects, empty groups, duplicate scripts, stale/empty policies, circular smart group criteria, and high blast-radius groups.
- Exports graph data as JSON or CSV.

Jamf Mapper is intentionally read-only. It does not create, update, or delete Jamf Pro objects.

## Requirements

- macOS 13 Ventura or later.
- Xcode 15 or later if building from source.
- A Jamf Pro API Client with a read-only API Role.
- Network access from the Mac to the Jamf tenant URL.

## Build And Run

Jamf Mapper is a Swift Package Manager macOS app. There is no Xcode project file required.

From Terminal:

```bash
cd /path/to/Jamf-Mapper
swift test
./script/build_and_run.sh run
```

Or open the package in Xcode:

1. Open `Package.swift`.
2. Select the `JamfMapper` executable target.
3. Select `My Mac`.
4. Press `Cmd+R`.

The helper script creates a local app bundle at `dist/JamfMapper.app`. The `dist/` directory is ignored by git.

## First-Time Use

1. Open Jamf Mapper.
2. Enter the Jamf Pro URL, for example `https://example.jamfcloud.com`.
3. Enter the API Client ID.
4. Enter the API Client Secret.
5. Click `Connect Securely`.
6. After login, click `Crawl Jamf Objects` in the sidebar.
7. Select an object type from the sidebar.
8. Select an object row to inspect mappings and audit details.

Use `Refresh Objects` whenever you want a new snapshot from Jamf Pro.

## Navigation

- `Objects`: Shows the crawled object types and counts.
- `Crawl Jamf Objects` / `Refresh Objects`: Starts a read-only crawl.
- Main object list: Search by name or ID and optionally show only orphaned objects.
- Inspector: Shows object metadata, source preview where available, dependency mappings, warnings, and the Jamf Pro console link.
- `Audit Reports`: Groups cleanup findings into expandable sections.
- Toolbar exports: Export the current graph to JSON or CSV.
- `Sign Out`: Removes the selected connection profile and deletes its client secret from Keychain.

## Supported Object Coverage

Current crawl coverage includes these Classic API objects:

- Policies
- Computer groups, including smart and static groups
- Computer extension attributes
- Scripts
- Categories
- Advanced computer searches
- Restricted software
- Packages
- Printers
- Dock items
- Directory bindings
- Network segments
- macOS configuration profiles
- Mobile device configuration profiles
- Mac applications

Current Jamf Pro API coverage includes:

- Scripts
- Packages
- Computer extension attributes
- Smart computer groups
- Static computer groups
- Patch policy details
- Patch software title configurations
- Jamf Connect configuration profiles
- Computer prestages

Some newer Jamf areas, such as App Installers and DDM declarations, may vary by tenant and Jamf Pro version. The app is structured to add those adapters as stable public list/detail endpoints are available.

## Dependency Mapping

Jamf Mapper extracts directed relationships such as:

- Policy uses script
- Policy installs package
- Policy scoped to group
- Policy excludes group
- Policy references network segment
- Policy uses printer, dock item, or directory binding
- Policy indirectly evaluates extension attributes through scoped smart group criteria
- Smart group evaluates extension attribute
- Smart group references another smart group in criteria
- Configuration profile scoped to group
- Patch policy depends on patch title or patch configuration
- Extension attribute uses embedded script input
- Object assigned to category

The inspector shows both sides of a relationship:

- `Depends On`: Objects the selected object references.
- `Used By`: Objects that reference the selected object.

## Audit Reports

Audit Reports group findings into expandable sections:

- Orphaned objects by type
- Empty smart and static groups
- Duplicate script content
- Stale disabled policies
- Empty policies
- Policies scoped broadly enough to deserve review
- Circular smart group criteria
- High blast-radius groups referenced by many objects

These are cleanup signals, not deletion instructions. Review each finding in Jamf Pro before changing production objects.

## Required Jamf API Role Permissions

Create a dedicated API Role and API Client in Jamf Pro:

1. In Jamf Pro, go to `Settings > System > API Roles and Clients`.
2. Create an API Role named something like `Jamf Mapper Read Only`.
3. Add only read privileges.
4. Create an API Client assigned to that role.
5. Copy the Client ID and Client Secret into Jamf Mapper.

Minimum practical read privileges:

| Area | Required privilege intent |
| --- | --- |
| Jamf Pro information | Read Jamf Pro server information |
| Policies | Read policies |
| Computer groups | Read smart computer groups and static computer groups |
| Extension attributes | Read computer extension attributes |
| Scripts | Read scripts |
| Categories | Read categories |
| Advanced searches | Read advanced computer searches |
| Restricted software | Read restricted software |
| Packages | Read packages |
| Printers | Read printers |
| Dock items | Read dock items |
| Directory bindings | Read directory bindings |
| Network segments | Read network segments |
| Configuration profiles | Read macOS configuration profiles and mobile device configuration profiles |
| Mac applications | Read Mac applications |
| Patch management | Read patch policies and patch software title configurations |
| Jamf Connect | Read Jamf Connect configuration profiles, if licensed and used |
| Computer prestages | Read computer prestage enrollments |

Jamf privilege names can differ slightly across Jamf Pro versions. If a crawl records a `403` for a specific endpoint, add the matching read privilege for that object family and run `Refresh Objects` again.

The app does not require create, update, or delete permissions.

## Security And Privacy

- API client secrets are saved in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Connection profile metadata is stored locally in SQLite.
- Crawl snapshots are stored locally on the Mac.
- The app does not upload tenant data anywhere.
- Exports can contain sensitive tenant configuration names, script bodies, and relationships. Treat exported JSON, CSV, and `.jamfmapper` bundles as confidential.

## Troubleshooting

### `HTTP 400 {"error":"invalid_request"}` during login

This usually means Jamf rejected the OAuth token request. Current builds encode the OAuth form body using proper `application/x-www-form-urlencoded` escaping, including secrets that contain `+`, `&`, `=`, `/`, spaces, or `%`.

If this still happens:

- Confirm you copied the API Client ID, not the API Role ID.
- Confirm the Client Secret has not been rotated.
- Remove leading or trailing spaces from the URL, Client ID, and Secret.
- Confirm the URL is the tenant root, such as `https://example.jamfcloud.com`, not `/api` or `/api/doc`.
- Confirm the API Client is enabled and assigned to the read-only role.

### Crawl shows missing object types

Check the crawl progress errors. A `403` usually means the API Role is missing the relevant read privilege. A `404` can mean the endpoint is unavailable in that Jamf Pro version or not licensed for the tenant.

### Script source is not visible

Run `Refresh Objects` with the latest build. Script previews require a fresh crawl because script source is stored in graph metadata during extraction.

## Development Checks

Run:

```bash
swift test
```

Current test coverage includes graph extraction, dependency resolution, audit algorithms, Jamf console URL generation, and OAuth form encoding.

## Repository Hygiene

Ignored by git:

- Swift build output
- Local app bundles and release archives
- Local SQLite snapshots and `.jamfmapper` exports
- Environment files and `.netrc`
- Local assistant/tooling state

Do not commit tenant exports, API credentials, local databases, generated app bundles, or screenshots that contain private tenant data.
