# `maludb/client` — PHP driver for MaluDB

PHP 8.2+ client for the maludb_core extension. Mirrors the
[Python](../python/README.md) and [Node.js](../nodejs/README.md)
drivers in shape and method names.

Status: **alpha**. v0.1.0 covers the headline read/write surface;
streaming, pool retrieval, and the workflow-extraction helpers land
in later versions.

## Requirements

| | |
|---|---|
| PHP | >= 8.2 |
| Extensions | `ext-pdo`, `ext-pdo_pgsql`, `ext-json` |
| PostgreSQL | maludb_core 0.41.0+ installed in the target DB |

On Ubuntu 24.04:

```bash
sudo apt install php-cli php-pgsql
```

Composer is needed for the autoload + dev deps:

```bash
# If composer isn't installed:
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
```

## Install

```bash
composer require maludb/client
```

Or from this source tree:

```bash
cd drivers/php
composer install
```

## Quickstart

```php
<?php
use MaluDB\Client;

require 'vendor/autoload.php';

// `postgresql:///mydb` would default pg's PDO to TCP+localhost which
// then requires SCRAM password auth. Append ?host=/var/run/postgresql
// for peer-auth via the Unix socket on a default PGDG install.
$client = Client::fromDsn(
    "postgresql:///mydb?host=/var/run/postgresql",
);

$sp = $client->registerSourcePackage(
    sourceType: 'log',
    contentText: 'oncall: 14:22Z api-gateway 5xx burst',
    originJsonb: ['uri' => 'log://oncall/2026-05-13'],
);

$c1 = $client->registerClaim(
    subject: 'api_gateway',
    verb: 'observed',
    objectValue: '5xx_burst',
    statementText: 'Initial 5xx surge at 14:22Z',
    sourcePackageId: $sp,
);

foreach ($client->retrieve('api_gateway', null, null, null, null, null, 10) as $hit) {
    echo "$hit->objectType {$hit->objectId} {$hit->rank}\n";
}
```

## Available methods

| Group | Methods |
|---|---|
| Ingest | `registerSourcePackage`, `registerClaim`, `registerFact`, `registerMemory`, `registerEpisode` |
| Retrieve | `textSearch`, `retrieve`, `replayEpisode` |
| Pool | `createPool`, `poolAddObservation`, `poolPromoteToClaim` |
| Skill | `registerSkill`, `addSkillState`, `addSkillTransition`, `beginSkillExecution`, `stepSkillExecution`, `abortSkillExecution` |
| Node | `registerLocalNode`, `nodeSubmit`, `nodeAccept`, `nodeReject`, `revokeLocalNode` |
| Misc | `version()`, `raw` (the underlying `PDO` instance) |

## Exception hierarchy

```
MaluDBError
├── MaluDBNotFound                       (P0002 / 02000)
├── MaluDBInvalidParameter               (22023 / 22P02)
├── MaluDBObjectNotInPrerequisiteState   (55000)
├── MaluDBCheckViolation                 (23514)
└── MaluDBPermissionDenied               (42501)
```

`catch (MaluDBNotFound $e) { … }`. All classes live in
`MaluDB\Exceptions\`.

## Running tests

```bash
cd drivers/php
composer install
MALUDB_TEST_DSN="postgresql:///maludb_bench?host=/var/run/postgresql" \
    vendor/bin/phpunit
```
