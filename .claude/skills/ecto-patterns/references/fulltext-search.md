# PostgreSQL Full-Text Search Reference

Native full-text search without external dependencies. Suitable for most content search needs.

## Migration Setup

```elixir
defmodule MyApp.Repo.Migrations.AddFullTextSearchToArticles do
  use Ecto.Migration

  def up do
    # Add tsvector column
    alter table(:articles) do
      add :search_vector, :tsvector
    end

    # GIN index for fast searches
    create index(:articles, [:search_vector], using: :gin)

    # Function to extract searchable text
    execute """
    CREATE OR REPLACE FUNCTION articles_search_vector(title text, body text)
    RETURNS tsvector AS $$
    BEGIN
      RETURN
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(body, '')), 'B');
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """

    # Trigger to auto-update search_vector
    execute """
    CREATE OR REPLACE FUNCTION articles_search_vector_trigger()
    RETURNS trigger AS $$
    BEGIN
      NEW.search_vector := articles_search_vector(NEW.title, NEW.body);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER articles_search_vector_update
    BEFORE INSERT OR UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION articles_search_vector_trigger();
    """

    # Backfill existing records
    execute """
    UPDATE articles SET search_vector = articles_search_vector(title, body);
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS articles_search_vector_update ON articles"
    execute "DROP FUNCTION IF EXISTS articles_search_vector_trigger()"
    execute "DROP FUNCTION IF EXISTS articles_search_vector(text, text)"

    alter table(:articles) do
      remove :search_vector
    end
  end
end
```

## Schema

```elixir
defmodule MyApp.Content.Article do
  use Ecto.Schema

  schema "articles" do
    field :title, :string
    field :body, :string
    field :search_vector, :any, virtual: true  # Not loaded by default

    timestamps()
  end
end
```

## Query with Search

### Basic Search

```elixir
def search_articles(query_string) when is_binary(query_string) do
  from(a in Article,
    where: fragment(
      "search_vector @@ websearch_to_tsquery('english', ?)",
      ^query_string
    ),
    order_by: [desc: fragment(
      "ts_rank_cd(search_vector, websearch_to_tsquery('english', ?), 32)",
      ^query_string
    )]
  )
  |> Repo.all()
end
```

### Search with Pagination and Highlights

```elixir
def search_articles(query_string, opts \\ []) do
  page = Keyword.get(opts, :page, 1)
  per_page = Keyword.get(opts, :per_page, 20)

  from(a in Article,
    where: fragment(
      "search_vector @@ websearch_to_tsquery('english', ?)",
      ^query_string
    ),
    select: %{
      id: a.id,
      title: a.title,
      # Highlight matching terms
      headline: fragment(
        "ts_headline('english', ?, websearch_to_tsquery('english', ?), 'StartSel=<mark>, StopSel=</mark>')",
        a.body,
        ^query_string
      ),
      rank: fragment(
        "ts_rank_cd(search_vector, websearch_to_tsquery('english', ?), 32)",
        ^query_string
      )
    },
    order_by: [desc: fragment("ts_rank_cd(search_vector, websearch_to_tsquery('english', ?), 32)", ^query_string)],
    offset: ^((page - 1) * per_page),
    limit: ^per_page
  )
  |> Repo.all()
end
```

## websearch_to_tsquery Syntax

Users can use Google-style search syntax:

| Input                | Matches                              |
|----------------------|--------------------------------------|
| `elixir phoenix`     | Articles with both words             |
| `"exact phrase"`     | Articles with exact phrase           |
| `elixir OR phoenix`  | Articles with either word            |
| `-deprecated`        | Excludes articles with "deprecated"  |
| `elixir -deprecated` | Elixir articles without "deprecated" |

## Weight Meanings

| Weight | Typical Use           | Boost Factor |
|--------|-----------------------|--------------|
| A      | Title, most important | Highest      |
| B      | Subtitles, headings   | High         |
| C      | Body text             | Medium       |
| D      | Metadata, tags        | Lower        |

## Performance Considerations

```elixir
# ALWAYS use GIN index
create index(:articles, [:search_vector], using: :gin)

# For large tables, consider partial index
create index(:articles, [:search_vector],
  using: :gin,
  where: "published_at IS NOT NULL"
)

# Monitor index size
# SELECT pg_size_pretty(pg_relation_size('articles_search_vector_index'));
```

## Anti-patterns

```elixir
# WRONG: Computing tsvector at query time (slow!)
from(a in Article,
  where: fragment(
    "to_tsvector('english', title || ' ' || body) @@ to_tsquery(?)",
    ^query
  )
)

# RIGHT: Pre-computed tsvector column with index
from(a in Article,
  where: fragment(
    "search_vector @@ websearch_to_tsquery('english', ?)",
    ^query
  )
)

# WRONG: Using LIKE for search (no ranking, slow)
from(a in Article, where: ilike(a.title, ^"%#{query}%"))

# RIGHT: Full-text search with ranking
# (as shown above)

# WRONG: Forgetting to sanitize search input
# websearch_to_tsquery handles this, but plainto_tsquery doesn't
```

## When to Use External Search

PostgreSQL FTS is great for:

- 100K-10M documents
- Simple search requirements
- Budget constraints

Consider Elasticsearch/Algolia/Meilisearch for:

- Typo tolerance (fuzzy matching)
- Faceted search with complex filters
- Multi-language with mixed alphabets
- Real-time indexing of 10M+ documents
- Advanced analytics on searches
