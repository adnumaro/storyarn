# Research: Efficient Page-Level Version Control at Scale

> **Date:** February 2026
> **Status:** Research
> **Goal:** Maximum functionality with minimum cost for 10,000+ pages per project

---

## Executive Summary

After researching industry practices, there are several viable approaches to implement full page-level version control efficiently. The key insight is that **storing deltas instead of full copies can achieve 10-100x storage reduction**.

**Recommended approach:** Hybrid system combining:
1. **RFC 6902 JSON Patch** for delta storage
2. **zstd compression** with shared dictionary
3. **PostgreSQL + S3 tiered storage** (hot/cold)
4. **Periodic snapshots** for fast reconstruction

**Projected storage:** ~5-10MB/year per active project (vs 90MB with naive approach)

---

## Part 1: Delta Compression Strategies

### 1.1 Git's Approach (Packfiles)

Git achieves incredible compression through delta encoding:

| Project         | Raw Size  | Compressed  | Ratio     |
|-----------------|-----------|-------------|-----------|
| SQLite (Fossil) | 7.1 GB    | 97 MB       | **74:1**  |
| Linux Kernel    | ~1 TB     | ~4 GB       | **250:1** |

**How it works:**
- Store most recent version as full text
- Store older versions as deltas pointing backwards
- Use rolling hash to find similar chunks
- Apply zlib compression on top

**Key insight from Git:**
> "The second (more recent) version is stored intact, the original is stored as a delta—because you need faster access to recent versions."

**Sources:**
- [Git Packfiles Documentation](https://git-scm.com/book/en/v2/Git-Internals-Packfiles)
- [GitHub Blog: Git's Database Internals](https://github.blog/open-source/git/gits-database-internals-i-packed-object-store/)
- [Fossil Delta Format](https://fossil-scm.org/home/doc/tip/www/delta_format.wiki)

### 1.2 RFC 6902: JSON Patch Standard

Perfect for Storyarn since pages are stored as JSON/JSONB.

**Example:**
```json
// Original page
{
  "name": "Jaime",
  "age": 35,
  "description": "A knight"
}

// After edit
{
  "name": "Jaime",
  "age": 36,
  "description": "A legendary knight"
}

// RFC 6902 Patch (what we store)
[
  { "op": "replace", "path": "/age", "value": 36 },
  { "op": "replace", "path": "/description", "value": "A legendary knight" }
]
```

**Storage comparison for typical page edit:**
| Method | Size |
|--------|------|
| Full page copy | ~5 KB |
| JSON Patch | ~100-200 bytes |
| **Reduction** | **25-50x** |

**Elixir library:** [Jsonpatch](https://elixirforum.com/t/jsonpatch-pure-elixir-implementation-of-rfc-6902/32007)

**Sources:**
- [RFC 6902 Specification](https://datatracker.ietf.org/doc/html/rfc6902)
- [jsondiffpatch](https://github.com/benjamine/jsondiffpatch)

### 1.3 Content-Addressable Storage (CAS)

Store content by its hash, enabling automatic deduplication.

```
Page content → SHA-256 hash → Storage key
"Hello world" → abc123... → stored once

If another page has same content → same hash → no duplicate storage
```

**Benefits:**
- Automatic deduplication across all pages
- Data integrity verification built-in
- Efficient for similar pages (templates, variations)

**Used by:** Git, Docker, IPFS, Terraform

**Sources:**
- [Content Addressable Storage Overview](https://lab.abilian.com/Tech/Databases%20&%20Persistence/Content%20Addressable%20Storage%20(CAS)/)

---

## Part 2: Compression Algorithms

### 2.1 zstd vs gzip for JSON

| Algorithm   | Compression Ratio   | Compress Speed   | Decompress Speed   |
|-------------|---------------------|------------------|--------------------|
| gzip -6     | 3.09x               | 34 MB/s          | 380 MB/s           |
| **zstd -3** | **3.17x**           | **300 MB/s**     | **1200 MB/s**      |
| zstd -19    | 3.8x                | 5 MB/s           | 1100 MB/s          |

**Key findings:**
- zstd compresses **7-8x faster** than gzip
- zstd decompresses **2-3x faster** than gzip
- Similar or better compression ratios

**zstd Dictionary Mode (Game Changer for JSON):**
> "Zstd's unique dictionary feature can achieve 90%+ compression for small JSON files. Similar JSON structures compress extremely well with shared dictionary."

For Storyarn, all pages in a project share similar structure. A trained dictionary could compress individual page versions from ~5KB to ~200-500 bytes.

**Sources:**
- [Daniel Lemire: Compressing JSON: gzip vs zstd](https://lemire.me/blog/2021/06/30/compressing-json-gzip-vs-zstd/)
- [Zstandard Official](http://facebook.github.io/zstd/)

### 2.2 PostgreSQL TOAST with LZ4

PostgreSQL 14+ supports LZ4 compression for TOAST (large values).

| Compression    | Storage Size  | Query Performance   |
|----------------|---------------|---------------------|
| PGLZ (default) | 41 GB         | Slower              |
| **LZ4**        | **38 GB**     | **Fastest**         |
| None           | 98 GB         | Baseline            |

**Warning:** TOAST has performance cliffs for values >2KB. Updates require full detoast+retoast.

**Sources:**
- [PostgreSQL TOAST Performance Tests](https://www.credativ.de/en/blog/postgresql-en/toasted-jsonb-data-in-postgresql-performance-tests-of-different-compression-algorithms/)
- [5mins of Postgres: JSONB and TOAST](https://pganalyze.com/blog/5mins-postgres-jsonb-toast)

---

## Part 3: Specialized Databases

### 3.1 Dolt (Git for Data)

SQL database with Git-like version control built-in.

**Performance:**
- 1.8x slower than MySQL on sysbench
- 4.5x slower on TPC-C (heavy writes)
- Gap is "unnoticeable in most applications"

**Pros:**
- Full SQL compatibility
- Branch, merge, diff built-in
- DoltgreSQL (PostgreSQL flavor) available

**Cons:**
- Write overhead by design
- Relatively new (stability concerns for production)

**Sources:**
- [Dolt GitHub](https://github.com/dolthub/dolt)
- [State of Dolt 2024](https://www.dolthub.com/blog/2024-04-03-state-of-dolt/)

### 3.2 TerminusDB

Immutable database with Git-like semantics, designed for JSON documents.

**Architecture:**
- Stores changes as deltas (immutable)
- Time-travel queries to any commit
- Push/pull/clone operations
- Apache 2.0 license

**Good fit for Storyarn because:**
- Native JSON document support
- Built-in versioning without extra tables
- Delta compression by design

**Cons:**
- Smaller community than PostgreSQL
- In-memory design may need tuning for large projects
- Less ecosystem/tooling

**Sources:**
- [TerminusDB GitHub](https://github.com/terminusdb/terminusdb)
- [TerminusDB Official](https://terminusdb.org/)

### 3.3 EventStoreDB

Purpose-built for event sourcing pattern.

**Good for:**
- Append-only immutable events
- High write throughput
- Built-in subscriptions
- Strong audit trail

**Not ideal for:**
- Long-lived entities with thousands of events (needs snapshots)
- Complex queries on current state

**Sources:**
- [EventStoreDB GitHub](https://github.com/EventStore/EventStore)
- [Building Event Sourcing in Production](https://developersvoice.com/blog/dotnet/building-event-sourcing-with-eventstore-and-dotnet/)

### 3.4 ClickHouse (for Activity/Audit Logs)

Columnar database with extreme compression for logs.

**Compression achievements:**
- 170x compression on nginx logs
- 10-20x typical for structured logs
- 17x on AWS's largest cluster (10 trillion rows)

**Perfect for:** Activity log storage (Layer 1 from original strategy)

**Sources:**
- [ClickHouse: 170x Log Compression](https://clickhouse.com/blog/log-compression-170x)
- [Building 19 PiB Logging Platform](https://clickhouse.com/blog/building-a-logging-platform-with-clickhouse-and-saving-millions-over-datadog)

---

## Part 4: Storage Tiers & Costs

### 4.1 AWS S3 Storage Classes

| Tier                     | Cost/GB/month   | Retrieval    | Use Case                    |
|--------------------------|-----------------|--------------|-----------------------------|
| S3 Standard              | $0.023          | Instant      | Hot data (current versions) |
| S3 Infrequent Access     | $0.0125         | Instant      | Warm data (recent history)  |
| S3 Glacier Instant       | $0.004          | Milliseconds | Cold data (old versions)    |
| S3 Glacier Flexible      | $0.0036         | 3-5 hours    | Archive                     |
| **Glacier Deep Archive** | **$0.00099**    | 12-48 hours  | Long-term archive           |

**Key insight:** Glacier Deep Archive is **$1/TB/month**

**Sources:**
- [AWS S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [S3 Glacier Storage Classes](https://aws.amazon.com/s3/storage-classes/glacier/)

### 4.2 Tiered Storage Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                     VERSION STORAGE TIERS                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  HOT (PostgreSQL)              WARM (S3 Standard)               │
│  ─────────────────             ─────────────────                │
│  • Current version             • Last 30 days of deltas         │
│  • Last 24h of deltas          • Recent snapshots               │
│  • Fast queries                • ~$0.023/GB/month               │
│                                                                  │
│  COLD (S3 Glacier Instant)     ARCHIVE (Deep Archive)           │
│  ─────────────────────────     ───────────────────              │
│  • 30-90 day old deltas        • 90+ day old deltas             │
│  • Older snapshots             • Historical snapshots           │
│  • ~$0.004/GB/month            • ~$0.001/GB/month               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Proposed Architecture for Storyarn

### 5.1 Hybrid Delta + Snapshot System

```
┌─────────────────────────────────────────────────────────────────┐
│                    PAGE VERSION STORAGE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  WRITE PATH:                                                     │
│  ───────────                                                     │
│  1. User edits page                                              │
│  2. Compute JSON Patch (RFC 6902) from previous version         │
│  3. Compress patch with zstd (shared dictionary per project)    │
│  4. Store in PostgreSQL (page_versions table)                   │
│  5. Every N edits OR daily: create compressed snapshot          │
│                                                                  │
│  READ PATH (reconstruct version):                                │
│  ─────────────────────────────────                               │
│  1. Find nearest snapshot before target version                  │
│  2. Load snapshot                                                │
│  3. Apply patches in sequence until target version               │
│  4. Return reconstructed page                                    │
│                                                                  │
│  STORAGE LAYOUT:                                                 │
│  ───────────────                                                 │
│  PostgreSQL:                                                     │
│  ├── pages (current state)                                       │
│  ├── page_versions (compressed deltas, last 30 days)            │
│  └── page_snapshots (compressed full copies, every 50 edits)    │
│                                                                  │
│  S3:                                                             │
│  ├── /snapshots/{project_id}/{page_id}/ (older snapshots)       │
│  └── /deltas/{project_id}/{page_id}/ (archived deltas)          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Database Schema

```sql
-- Page versions (deltas)
CREATE TABLE page_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
  version_number INTEGER NOT NULL,

  -- Delta storage
  patch BYTEA NOT NULL,              -- zstd-compressed JSON Patch
  patch_size_bytes INTEGER NOT NULL, -- For monitoring

  -- Metadata
  changed_by UUID REFERENCES users(id),
  changed_fields TEXT[],             -- Quick reference without decompressing
  created_at TIMESTAMP DEFAULT NOW(),

  -- For reconstruction optimization
  is_snapshot BOOLEAN DEFAULT FALSE, -- True = full copy, not delta
  snapshot_url TEXT,                 -- S3 URL if archived

  CONSTRAINT unique_page_version UNIQUE(page_id, version_number)
);

-- Indexes for efficient queries
CREATE INDEX idx_versions_page_recent ON page_versions(page_id, version_number DESC);
CREATE INDEX idx_versions_snapshots ON page_versions(page_id, version_number)
  WHERE is_snapshot = TRUE;

-- Archival tracking
CREATE TABLE version_archives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  page_id UUID NOT NULL,
  version_from INTEGER NOT NULL,
  version_to INTEGER NOT NULL,
  s3_key TEXT NOT NULL,              -- S3 path to archived bundle
  storage_class TEXT NOT NULL,       -- 'GLACIER_IR', 'DEEP_ARCHIVE'
  archived_at TIMESTAMP DEFAULT NOW()
);
```

### 5.3 Elixir Implementation Sketch

```elixir
defmodule Storyarn.Versions do
  @snapshot_interval 50  # Create snapshot every 50 edits

  def save_version(page, new_content, user) do
    current_content = page.content

    # Compute delta using RFC 6902
    patch = Jsonpatch.diff(current_content, new_content)

    # Compress with zstd
    compressed = :ezstd.compress(Jason.encode!(patch), get_dictionary(page.project_id))

    # Determine if we need a snapshot
    version_number = get_next_version(page.id)
    is_snapshot = rem(version_number, @snapshot_interval) == 0

    if is_snapshot do
      # Store full compressed snapshot
      snapshot_data = :ezstd.compress(Jason.encode!(new_content))
      save_snapshot(page.id, version_number, snapshot_data, user)
    else
      # Store delta only
      save_delta(page.id, version_number, compressed, user, changed_fields(patch))
    end
  end

  def get_version(page_id, target_version) do
    # Find nearest snapshot before target
    snapshot = get_nearest_snapshot(page_id, target_version)

    # Load and decompress snapshot
    content = decompress_snapshot(snapshot)

    # Apply patches from snapshot to target
    patches = get_patches_range(page_id, snapshot.version_number + 1, target_version)

    Enum.reduce(patches, content, fn patch, acc ->
      Jsonpatch.apply!(acc, decompress_patch(patch))
    end)
  end
end
```

### 5.4 Storage Estimates (Revised)

**Assumptions:**
- Project with 10,000 pages
- Average page: 5KB
- 50 edits/day
- Average patch size: 150 bytes (compressed)
- Snapshot every 50 edits

| Component             | Calculation      | Monthly     | Yearly    |
|-----------------------|------------------|-------------|-----------|
| Deltas (30 days)      | 50 × 150B × 30   | 225 KB      | -         |
| Snapshots (hot)       | 50/50 × 5KB × 30 | 150 KB      | -         |
| Archived deltas       | 50 × 150B × 335  | -           | 2.5 MB    |
| Archived snapshots    | 365 × 5KB        | -           | 1.8 MB    |
| **Total per project** |                  | **~400 KB** | **~5 MB** |

**For 1,000 projects:**
- Hot storage (PostgreSQL): ~400 MB
- Archive (S3 Glacier): ~5 GB/year

**Cost (1,000 projects):**
- PostgreSQL (RDS): Part of existing infrastructure
- S3 Glacier Deep Archive: 5 GB × $0.001 = **$0.005/month**

**Comparison with original strategy:**

| Approach             | Storage/year/project   | 1000 Projects  |
|----------------------|------------------------|----------------|
| Full page copies     | 90 MB                  | 90 GB          |
| Original proposal    | 21 MB                  | 21 GB          |
| **Delta + Snapshot** | **5 MB**               | **5 GB**       |

**Reduction: 95% less storage than naive, 76% less than original proposal**

---

## Part 6: Feature Comparison

### What This Enables

| Feature             | Naive Copy  | Original Proposal   | Delta+Snapshot     |
|---------------------|-------------|---------------------|--------------------|
| See any version     | ✅           | ❌ (snapshots only)  | ✅                  |
| See what changed    | ✅           | ✅ (field names)     | ✅ (full diff)      |
| See who changed     | ✅           | ✅                   | ✅                  |
| Restore single page | ✅           | ❌                   | ✅                  |
| Compare versions    | ✅           | ❌                   | ✅                  |
| Storage efficient   | ❌           | ✅                   | ✅✅                 |
| Fast reconstruction | ✅           | N/A                 | ✅ (with snapshots) |

### Trade-offs

**Pros:**
- Full version history for every page
- Efficient storage through delta compression
- Fast reconstruction via periodic snapshots
- Scalable to 10,000+ pages
- Can show exact field-level changes

**Cons:**
- More complex implementation than simple copies
- Reconstruction time depends on distance to nearest snapshot
- Need to maintain zstd dictionaries per project
- Archival/retrieval logic adds complexity

---

## Part 7: Implementation Phases

### Phase 1: Core Delta System
1. Add `page_versions` table
2. Implement JSON Patch diff/apply (use `jsonpatch` hex package)
3. Add zstd compression (use `ezstd` hex package)
4. Version pages on every save

### Phase 2: Snapshots
1. Implement snapshot creation logic
2. Add snapshot-based reconstruction
3. Configure snapshot interval (50 edits recommended)

### Phase 3: UI
1. Version history timeline per page
2. Diff viewer (side-by-side or inline)
3. Restore to version button
4. "Who changed what" attribution

### Phase 4: Archival
1. Background job to archive old versions to S3
2. Lifecycle policies for Glacier transition
3. On-demand retrieval from archive

### Phase 5: Optimization
1. Train zstd dictionaries per project
2. Batch delta compression
3. Pre-compute common diffs for faster display

---

## Part 8: Alternative Approaches Considered

### 8.1 Use TerminusDB Instead of PostgreSQL

**Pros:** Built-in versioning, no custom implementation
**Cons:** Migration risk, smaller ecosystem, team learning curve
**Verdict:** Consider for v2 if PostgreSQL approach hits limits

### 8.2 Use Dolt for Version-Controlled Tables

**Pros:** SQL + Git semantics out of the box
**Cons:** 2-4x slower writes, less mature than PostgreSQL
**Verdict:** Interesting but risky for production

### 8.3 Event Sourcing with EventStoreDB

**Pros:** Perfect audit trail, high write throughput
**Cons:** Overkill for page versioning, adds infrastructure complexity
**Verdict:** Better suited for real-time collaboration events, not page history

### 8.4 ClickHouse for Everything

**Pros:** Extreme compression, fast analytics
**Cons:** Not designed for transactional workloads, complex setup
**Verdict:** Use only for activity logs, not page content

---

## Conclusion

**Recommended approach:** PostgreSQL + JSON Patch + zstd + S3 tiered storage

This gives us:
- **Full page-level version history** (not just snapshots)
- **95% storage reduction** vs naive approach
- **Exact field-level diffs** visible to users
- **Scalable to 10,000+ pages** per project
- **Uses existing infrastructure** (PostgreSQL + S3)

The implementation complexity is manageable with existing Elixir libraries (`jsonpatch`, `ezstd`), and the architecture allows future optimization (better dictionaries, smarter snapshot intervals) without schema changes.

---

## Sources

### Delta Compression & Git
- [Git Packfiles Documentation](https://git-scm.com/book/en/v2/Git-Internals-Packfiles)
- [GitHub Blog: Git's Database Internals](https://github.blog/open-source/git/gits-database-internals-i-packed-object-store/)
- [Fossil Delta Format](https://fossil-scm.org/home/doc/tip/www/delta_format.wiki)
- [Pure Storage: Delta Encoding](https://www.purestorage.com/uk/knowledge/what-is-delta-encoding.html)

### JSON Patch
- [RFC 6902 Specification](https://datatracker.ietf.org/doc/html/rfc6902)
- [jsondiffpatch Library](https://github.com/benjamine/jsondiffpatch)
- [Elixir Jsonpatch](https://elixirforum.com/t/jsonpatch-pure-elixir-implementation-of-rfc-6902/32007)

### Compression
- [Daniel Lemire: Compressing JSON](https://lemire.me/blog/2021/06/30/compressing-json-gzip-vs-zstd/)
- [Zstandard Official](http://facebook.github.io/zstd/)
- [PostgreSQL TOAST Compression Tests](https://www.credativ.de/en/blog/postgresql-en/toasted-jsonb-data-in-postgresql-performance-tests-of-different-compression-algorithms/)

### Specialized Databases
- [Dolt: Git for Data](https://github.com/dolthub/dolt)
- [TerminusDB](https://terminusdb.org/)
- [EventStoreDB](https://github.com/EventStore/EventStore)
- [ClickHouse Log Compression](https://clickhouse.com/blog/log-compression-170x)

### Storage & Costs
- [AWS S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [S3 Glacier Storage Classes](https://aws.amazon.com/s3/storage-classes/glacier/)

### Event Sourcing
- [Event Sourcing Pattern (Microsoft)](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing)
- [AWS Event Sourcing with DynamoDB](https://aws.amazon.com/blogs/database/build-a-cqrs-event-store-with-amazon-dynamodb/)
