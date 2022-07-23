Feature: Backup replicated merge tree table

  Background:
    Given default configuration
    And a working s3
    And a working zookeeper on zookeeper01
    And a working clickhouse on clickhouse01
    And a working clickhouse on clickhouse02

  Scenario: Backup replicated table
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', '{replica}')
    PARTITION BY CounterID % 10
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 10         | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    Then we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_less_than_22.7
  Scenario: Backup ReplicatedMergeTree table with static replica name
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', 'static_name')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.table_02 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', 'static_name')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_02 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.legacy_table
    (
        EventDate Date,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.legacy_table', 'static_name',
    EventDate, intHash32(UserID), (CounterID, EventDate, intHash32(UserID)), 8192);
    INSERT INTO test_db.legacy_table SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 3          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    override_replica_name: '{replica}'
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT replica_name FROM system.replicas WHERE database = 'test_db'
    """
    Then we get response
    """
    clickhouse02
    """
    And we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_22.7
  Scenario: Backup ReplicatedMergeTree table with static replica name
    Given ClickHouse settings
    """
    allow_deprecated_syntax_for_merge_tree: 1
    """
    And we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', 'static_name')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.table_02 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', 'static_name')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_02 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.legacy_table
    (
        EventDate Date,
        CounterID UInt32,
        UserID UInt32
    ) ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.legacy_table', 'static_name',
    EventDate, intHash32(UserID), (CounterID, EventDate, intHash32(UserID)), 8192);
    INSERT INTO test_db.legacy_table SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 3          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    override_replica_name: '{replica}'
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT replica_name FROM system.replicas WHERE database = 'test_db'
    """
    Then we get response
    """
    clickhouse02
    """
    And we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_less_than_22.7
  Scenario: Override replicated table to single-node on restore with cmd flag
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.table_02 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_02 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.legacy_table
    (
        EventDate Date,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.legacy_table', '{replica}}',
    EventDate, intHash32(UserID), (CounterID, EventDate, intHash32(UserID)), 8192);
    INSERT INTO test_db.legacy_table SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 3          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT engine FROM system.tables WHERE database = 'test_db' ORDER BY engine
    """
    Then we get response
    """
    MergeTree
    SummingMergeTree
    """
    Then we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_22.7
  Scenario: Override replicated table to single-node on restore with cmd flag
    Given ClickHouse settings
    """
    allow_deprecated_syntax_for_merge_tree: 1
    """
    And we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.table_02 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_02 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.legacy_table
    (
        EventDate Date,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.legacy_table', '{replica}}',
    EventDate, intHash32(UserID), (CounterID, EventDate, intHash32(UserID)), 8192);
    INSERT INTO test_db.legacy_table SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 3          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT engine FROM system.tables WHERE database = 'test_db' ORDER BY engine
    """
    Then we get response
    """
    MergeTree
    SummingMergeTree
    """
    Then we got same clickhouse data at clickhouse01 clickhouse02

  Scenario: Override replicated table to single-node on restore with config
    Given ch-backup configuration on clickhouse02
    """
    backup:
        force_non_replicated: True
    """
    And we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 1          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    And we execute query on clickhouse02
    """
    SELECT DISTINCT engine FROM system.tables WHERE database = 'test_db'
    """
    Then we get response
    """
    MergeTree
    """
    Then we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_less_than_22.7
  Scenario: Override replicated table to single-node incremental
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.table_02 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_02 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.legacy_table
    (
        EventDate Date,
        CounterID UInt32,
        UserID UInt32
    ) ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.legacy_table', '{replica}}',
    EventDate, intHash32(UserID), (CounterID, EventDate, intHash32(UserID)), 8192);
    INSERT INTO test_db.legacy_table SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 3          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    schema_only: true
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT engine FROM system.tables WHERE database = 'test_db' ORDER BY engine
    """
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    """
    Then we get response
    """
    MergeTree
    SummingMergeTree
    """
    Then we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_22.7
  Scenario: Override replicated table to single-node incremental
    Given ClickHouse settings
    """
    allow_deprecated_syntax_for_merge_tree: 1
    """
    And we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.table_02 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_02 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.legacy_table
    (
        EventDate Date,
        CounterID UInt32,
        UserID UInt32
    ) ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.legacy_table', '{replica}}',
    EventDate, intHash32(UserID), (CounterID, EventDate, intHash32(UserID)), 8192);
    INSERT INTO test_db.legacy_table SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 3          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    schema_only: true
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT engine FROM system.tables WHERE database = 'test_db' ORDER BY engine
    """
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    """
    Then we get response
    """
    MergeTree
    SummingMergeTree
    """
    Then we got same clickhouse data at clickhouse01 clickhouse02

  Scenario: Backup ReplicatedMergeTree materialized view with static replica name
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE MATERIALIZED VIEW test_db.view_01 (`n` Int32)
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', 'static_name')
    PARTITION BY tuple() ORDER BY n SETTINGS index_granularity = 8192
    AS
    SELECT number FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE MATERIALIZED VIEW test_db.view_02 (`n` Int32)
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', 'static_name')
    PARTITION BY tuple() ORDER BY n SETTINGS index_granularity = 8192
    AS
    SELECT number FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 0          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    override_replica_name: '{replica}'
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT replica_name FROM system.replicas WHERE database = 'test_db'
    """
    Then we get response
    """
    clickhouse02
    """
    And we got same clickhouse data at clickhouse01 clickhouse02

  Scenario: Override replicated view to single-node on restore
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE MATERIALIZED VIEW test_db.view_01 (`n` Int32)
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/shard_01/test_db.table_01', 'static_name')
    PARTITION BY tuple() ORDER BY n SETTINGS index_granularity = 8192
    AS
    SELECT number FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE MATERIALIZED VIEW test_db.view_02 (`n` Int32)
    ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/shard_01/test_db.table_02', 'static_name')
    PARTITION BY tuple() ORDER BY n SETTINGS index_granularity = 8192
    AS
    SELECT number FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 0          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT engine FROM system.tables WHERE database = 'test_db' ORDER BY engine
    """
    Then we get response
    """
    MaterializedView
    MergeTree
    SummingMergeTree
    """
    Then we got same clickhouse data at clickhouse01 clickhouse02

  Scenario: Restore dirty host
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db;
    CREATE TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/test_db.table_01', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 1          | 0          |
    When we dirty remove clickhouse data at clickhouse01
    And we restore clickhouse backup #0 to clickhouse01
    """
    override_replica_name: '{replica}'
    clean_zookeeper: True
    replica_name: clickhouse01
    """
    When we restore clickhouse backup #0 to clickhouse02
    Then we got same clickhouse data at clickhouse01 clickhouse02

  Scenario: Restore with default database
    Given we have executed queries on clickhouse01
    """
    CREATE TABLE default.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/test_db.table_01', '{replica}')
    PARTITION BY toYYYYMM(EventDate)
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO default.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 1          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    Then we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_20.10
  Scenario: Backup replicated table with implicit parameters
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db Engine = Atomic;
    CREATE TABLE test_db.table_01 ON CLUSTER 'default' (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree()
    PARTITION BY CounterID % 10
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);

    CREATE MATERIALIZED VIEW test_db.view_01 ON CLUSTER 'default' (
        `n` Int32
    )
    ENGINE = ReplicatedMergeTree()
    PARTITION BY tuple() ORDER BY n SETTINGS index_granularity = 8192
    AS SELECT CounterID n FROM test_db.table_01;

    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 11         | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    Then we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_20.10
  Scenario: Override replicated table with implicit parameters to single-node
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db Engine = Atomic;
    CREATE TABLE test_db.table_01 ON CLUSTER 'default' (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree()
    PARTITION BY CounterID % 10
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);

    CREATE MATERIALIZED VIEW test_db.view_01 ON CLUSTER 'default' (
        `n` Int32
    )
    ENGINE = ReplicatedMergeTree()
    PARTITION BY tuple() ORDER BY n SETTINGS index_granularity = 8192
    AS SELECT CounterID n FROM test_db.table_01;

    INSERT INTO test_db.table_01 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    And we have executed queries on clickhouse01
    """
    CREATE TABLE test_db.table_02 ON CLUSTER 'default' (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedSummingMergeTree()
    PARTITION BY CounterID % 10
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID);
    INSERT INTO test_db.table_02 SELECT now(), number, rand() FROM system.numbers LIMIT 10
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 21         | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    """
    force_non_replicated: true
    """
    And we execute query on clickhouse02
    """
    SELECT DISTINCT engine FROM system.tables WHERE database = 'test_db' ORDER BY engine
    """
    Then we get response
    """
    MaterializedView
    MergeTree
    SummingMergeTree
    """
    Then we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_21.8
  @require_version_less_than_22.7
  Scenario: Backup replicated table with invalid zk path
    Given we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db ENGINE Ordinary;
    ATTACH TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('invalid_path', '{replica}')
    PARTITION BY CounterID % 10
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID)
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 0          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    Then clickhouse02 has same schema as clickhouse01
    And we got same clickhouse data at clickhouse01 clickhouse02

  @require_version_22.7
  Scenario: Backup replicated table with invalid zk path
    Given ClickHouse settings
    """
    allow_deprecated_database_ordinary: 1
    """
    And we have executed queries on clickhouse01
    """
    CREATE DATABASE test_db ENGINE Ordinary;
    ATTACH TABLE test_db.table_01 (
        EventDate DateTime,
        CounterID UInt32,
        UserID UInt32
    )
    ENGINE = ReplicatedMergeTree('invalid_path', '{replica}')
    PARTITION BY CounterID % 10
    ORDER BY (CounterID, EventDate, intHash32(UserID))
    SAMPLE BY intHash32(UserID)
    """
    When we create clickhouse01 clickhouse backup
    Then we got the following backups on clickhouse01
      | num | state   | data_count | link_count |
      | 0   | created | 0          | 0          |
    When we restore clickhouse backup #0 to clickhouse02
    Then clickhouse02 has same schema as clickhouse01
    And we got same clickhouse data at clickhouse01 clickhouse02
