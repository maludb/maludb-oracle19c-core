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
# If composer isn't installed, install it system-wide:
curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php
sudo mv composer.phar /usr/local/bin/composer
rm composer-setup.php
composer --version
```

If you do not have sudo access, install Composer for your user instead:

```bash
mkdir -p "$HOME/.local/bin"
curl -sS https://getcomposer.org/installer | php -- --install-dir="$HOME/.local/bin" --filename=composer
"$HOME/.local/bin/composer" --version
```

If the user-local `composer` command is not found in a new shell, add
`$HOME/.local/bin` to your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
. ~/.profile
```

## Install

The PHP driver is currently distributed from this repository. The
Packagist package name is reserved as `maludb/client`, but a plain
`composer require maludb/client` only works after the package has been
published to Packagist.

To run examples or tests from this source tree:

```bash
git clone https://github.com/maludb/maludb-core.git
cd maludb-core/drivers/php
composer install
```

To use the driver from another PHP project before the Packagist package is
published, point Composer at your local checkout:

```bash
cd /path/to/your/php-project
composer init --no-interaction --name=local/maludb-app   # skip if composer.json already exists
composer config repositories.maludb-client path /path/to/maludb-core/drivers/php
composer require 'maludb/client:*@dev'
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
