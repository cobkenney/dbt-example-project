# TODO

- [x] 1. Build semantic views — `marts/core_context_layer/`, four of them: one per grain of additive measure in `core_mart`, which is what stops a fan-out join from silently double-counting. Covers all 26 business questions. Materialized with `Snowflake-Labs/dbt_semantic_view`. Five verified figures from `analyses/` reproduced exactly through them; see that folder's README for the reconciliation and for what the syntax cannot express.
- [x] 2. Build a skill called wake-up-ae that opens a PR for new amenities or verification methods that trigger from test warning
- [x] 3. Determine if a new amenity is common enough (> 5% of listings have it) to be added to the marts layer
- [x] 4. Check whether any of the amenities columns are similar to each other
- [x] 5. Figure out if we really need `availability_windows` — is `fct_listing_daily` enough to answer that question easily? **Yes it is.** Both dependent questions (#3 and #25 in `BUSINESS_QUESTIONS.md`) reproduce exactly from the daily fact, so the 2 models / 258 lines / 25 tests were collapsed into `analyses/03`. The clamp rule survives as `tests/assert_stay_cap_binds.sql`; see "Collapsed models" in `dbt/models/README.md`.
- [x] 6. Think of 20 more business questions we could ask about this data — written up in `BUSINESS_QUESTIONS.md` (26 questions, plus the gaps the source data can't fill and the caveats that change answers)
- [x] 7. Review tests to ensure consistency
- [x] 9. Join the READMEs in `models/` together — consolidated into `models/README.md`
- [ ] 10. clean up all comments / docs / etc
  - remove all comments that are so specific to rows or values in the tables today, just include those in project summary about decisions made
- [x] 11. make amenities closer to host verifications, account for history even though it doesn't exist
- [x] 12. skill that updates descriptions in semantic views if updated in marts tables, runs on commit
- [x] 13. build verified queries in semantic views — `AI_VERIFIED_QUERIES`, plan settled and the syntax probed against Snowflake; nothing written yet
- [ ] 14. verify query / view outputs — a `run-operation` that executes every verified query and fails on error, since Snowflake accepts one referencing a table that does not exist (probed: `select no_such_column from no_such_table` created fine). Pin each result to the figure in `analyses/` where one exists, so a query that still runs but has quietly drifted is caught too.
- [ ] 15. test skills / demonstrate example PR
- [x] 16. clean up tests (too many on models, some on sources for no reason, bespoke tests)
- [x] 17. clean up business questions
- [x] 18. clean up seeds
- [ ] 19. review macros





- [ ] 17. summary of project
  - could have used seeds for sources instead of staging in snowflake — the two seeds in the project (`known_amenity_names`, `known_verification_methods`) are pinned value lists rather than source data, and they show the tradeoff: regenerable by macro and they make the generated flag columns a committed decision instead of a function of today's rows, but `dbt test` and `dbt run` both now need `dbt seed` to have run first, and the models carry an explicit `-- depends_on:` because a `ref()` inside a macro is invisible to the parser
  - could consider incrementals, particulary for calendar & amenities changelog if they were big enough
  - amenities changelog is kind of a snapshot already (SCD2)
  - could have built a specific model for question 3, but it felt overfit, calculated all the availability windows
  - elements:
    - dbt project setup
      - snowflake schemas
    - stg, int, marts, sv
      - include decisions made when building
        - no amenities history needed bc history predates calendar, not very meaningful on its own
        - hard deletes
        - pii
        - null ids
        - bath outliers
        - reservation id vs reservation key
        - calendar limitations
    - necessary packages (utils, snowflake semantic view)
    - standalone tests
    - test warn vs fail
    - CI pre commit config (linter, maybe description check?)
    - Skills to add new possible columns
    - when I used AI vs not
- [ ] 18. next steps
  - figure out how to best maximize the context layer / make it available in tools like Claude or Snowflake directly (some agent) - real testing
  - combine / collapse some amenities
  - monitor noise of skills
  - set up monitoring on tables (tools like Monte Carlo), might be built in, might need to distinguish between layers what is necessary
  - similarity assessment of metrics
  - extend wake up ae to semantic view additions
  - other sources needed
- [ ] 19. read every file
