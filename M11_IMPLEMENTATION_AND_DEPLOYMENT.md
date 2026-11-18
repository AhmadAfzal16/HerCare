# M11 — live content recommendations

Implemented 2026-10-15. This replaces the old fixed Flutter verse list with a database-managed, reviewed content catalog and live personalized feed. The original retired widget is recoverable in Git.

## What changes for the mother and guardian

- **For You** appears on the mother's home and has a full content screen. The guardian gets a separate family-education feed, without access to the mother's recommendation history, preferences, feedback or clinical inputs.
- Separate optional **Islamic content** and **music** switches start off. Neither choice changes risk scores or guardian-sharing consent. Categories can also be disabled.
- Cards can contain Quran text/translation/transliteration/recitation, Islamic educational content, soothing audio/video, psychoeducation or existing lightweight M9 activities. No additional form is required for a recommendation; optional helpful/not-helpful/dismissed feedback informs future ranking.
- Media opens in the browser only after a confirmation and fresh availability check. No autoplay, third-party thumbnails, hidden media downloads or health information appended to external links. The publisher may still use its own cookies, ads, IP/device information and tracking after the user opens its site.
- Explicitly saved **articles** can have short-lived encrypted native-device text copies. Media needs a connection; browser persistence is disabled. The copy is bound to the account and API, capped at 20 articles/160 KB and 24 hours, and respects earlier availability/review expiry. Logout/permission loss clears it. Existing offline copies cannot be remotely recalled while a device is disconnected, so the UI labels them as older copies and disables external actions.
- An unresolved recorded crisis takes priority over ordinary content, including saved items. Immediate Help is shown instead; selecting a verse, music or a game does not diagnose/treat a crisis or automatically contact a guardian.

## How recommendations work

The server reads authorized, already-recorded aggregate signals, not values manufactured on the phone:

- Latest mood/sleep observations and consented Android usage within two calendar days.
- Latest completed screening within 14 days and unresolved safety events, without reusing draft answers.
- Completed practice within 30 days; optional before/after ratings influence activity preference only after at least three pairs. This is a self-reported preference signal, not proven treatment benefit.
- Current content choices, feedback, saves, availability, source review and publication state.

Missing signals remain missing and receive a general feed. There is no new compulsory daily questionnaire. Raw journals, chats, notification text and audio are not read or sent to a publisher.

Ranking is an **explainable content-based heuristic with feedback**, not a newly trained or clinically validated ML model. Context-tag matches, editorial priority, helpfulness, saved status, practice preference, diversity and daily rotation determine order. Weights are versioned in PostgreSQL and can be changed by an administrator without rebuilding the app. Faith/music opt-outs are never treated as distress signals. The unvalidated M4 future-depression forecast is deliberately not presented as a reliable recommendation input.

The daily verse advances through eligible reviewed database verses on a **UTC calendar day**, with a stable account offset. It does not depend on a compiled list of verses or external API requests on each phone refresh.

## What “live” means here

The feed queries current database records. Visible foreground screens refresh approximately every **30 seconds**, with bounded backoff on failure, and on return/resume/manual refresh. Mood, screening and practice provider changes invalidate the feed immediately using an opaque in-memory change marker; the server retrieves the actual authorized records. Feedback/preferences refresh the ranking after confirmation. Hidden tabs/background routes stop requesting data.

Publishing, withdrawing, editing or expiring content changes the catalog revision; current readers revalidate it. Requests are coalesced and bounded. Candidate ranking loads metadata only, then hydrates selected cards. There are at most 1,000 published catalog items, 30 feed cards, 100 server-saved items and 20 offline article copies per account.

External discovery is a separate **draft-import and human-review workflow**. New content does not require a Flutter release, but unreviewed web search results are not automatically published to a maternal-health feed. Games use the existing safe M9 allow-list; new executable game code still requires an app update.

## Content sources and review

`hercare_backend/catalogs/content-starter.json` is an editable **17-item draft import manifest**, not an active hard-coded feed. It contains six Quran references, licensed nature/piano links, four brief educational article drafts and five existing M9 activity references. Nothing from it was automatically published or attributed to a fictitious reviewer.

- [Al Quran Cloud](https://alquran.cloud/api) supplies the actual Arabic, Jalandhry Urdu translation, Saheeh International English translation, transliteration and Alafasy recitation metadata. Six-reference live dry runs passed. Exact Quran text/diacritics are preserved; sources, translators and reciter are named. Its [terms](https://alquran.cloud/terms-and-conditions) require respect for retained rights and attribution and provide no uptime guarantee. Review current terms for the intended distribution.
- Nature video: [Small waterfall by Editor](https://commons.wikimedia.org/wiki/File:Small_waterfall.webm), CC BY 3.0. Piano: [Gymnopédie no.3 uploaded by Teknopazzo](https://commons.wikimedia.org/wiki/File:Gymnop%C3%A9die_no.3.ogg), CC0 performance. Original external files are linked, not copied into the app. Preferences control music independently of nature content.
- Short original English/Urdu educational drafts link to [NIMH](https://www.nimh.nih.gov/health/publications/perinatal-depression), [NHS postpartum rest information](https://www.nhs.uk/baby/support-and-services/sleep-and-tiredness-after-having-a-baby/) and [WHO's stress-management guide](https://www.who.int/publications/i/item/9789240003927). These are not endorsements of HerCare. Foreign emergency contacts are not copied into the module.

A real reviewer must check clinical wording, Urdu translations, religious context, media suitability and rights before approval/publication. Entering a qualification in the admin form records a declaration; software does not independently verify it. External sources/media require a future review expiry to be approved/published; expired or withdrawn material is excluded. No religious practice or entertainment is described as a depression cure, and no new religious ruling is generated.

## Administration and deployment

An existing authorized administrator opens **Recommendation catalog** from the admin workspace. Draft creation/editing, source fields, actual Quran translations, review notes/role, separate publication, withdrawal, archiving/restoration and version conflicts are supported. Editing returns a published item to draft. No account has been granted an admin role by this work.

1. Deploy Node 22+ and the existing PostgreSQL/HTTPS backend. The new `021_content_recommendations.sql` migration was applied normally to the local database after rollback tests; production needs the same migration. **Never edit applied migrations 001–021.**
2. Set `CONTENT_MEDIA_ALLOWED_HOSTS` to exact reviewed HTTPS hosts. The local ignored `.env` and tracked `.env.example` now contain the starter publishers; no credentials were changed. IPv4/IPv6/local/custom-scheme/credential/tracking-query links are rejected. The normal feed never fetches arbitrary media URLs server-side.
3. Provision real reviewer accounts through the existing controlled operator process. Mobile/public registration cannot grant administrator privileges.
4. Validate an operator-owned manifest from `hercare_backend`:

```text
node --env-file=.env scripts/content-import.js --file catalogs/content-starter.json
```

This is a dry run by default. Quran import uses a fixed HTTPS host/edition list, no redirect, eight-second timeout, 256 KB cap and cross-edition reference/audio checks; it has no paid API key. No original audio/video files are downloaded.

5. To create drafts after a real administrator signs in, supply `CONTENT_IMPORT_TOKEN` and `CONTENT_IMPORT_ACCOUNT_ID` through the operator environment, then add `--api https://YOUR-API/api/v1 --apply`. Never paste tokens into source, arguments or chat. Stable UUIDs make unchanged-manifest retries idempotent; changed content creates a new draft. Partial batch failures are reported honestly. This command never approves or publishes.
6. Review and publish suitable drafts in the app. Until then the mother/guardian sees an honest empty catalog state, not demo recommendations. External draft review dates in the starter file are 2027-01-13 and must be reassessed before then.
7. Build/deploy the updated app when requested. This implementation did **not** launch/install the app or start persistent backend/model services. M11 needs no extra Python model, paid recommendation API, video SDK or mobile dependency. Hosting, data traffic and human review can still cost money.

## Verification and boundaries

Final verification:

- **374 Flutter tests passed**, including **21 member-content** and **12 administrator-content** tests. English/Urdu compact screens, 200% text, keyboard dialogs/readers, exact retries, account changes, provider origins, optional preferences, live invalidation, bounded encrypted cache and in-memory expiry are covered. A changing clock fixture in an earlier run was corrected; the final full suite passed.
- **197 backend tests passed, 19 optional checks skipped**, using Node 24; full backend ESLint passed. Includes source adapter, validation, ranking, daily rotation, URL controls, privacy, CORS, account/role and strict date/expiry tests. The unrelated manual `test-chat.js` was excluded.
- **One separately enabled real PostgreSQL lifecycle test passed**, with multiple encryption-independent privacy, draft/review/publish, retry, preference, feedback, save, withdrawal, consent and crisis assertions. All synthetic rows/revisions roll back. Run with `RUN_CONTENT_DB_TESTS=1` and `node -r dotenv/config --test test/content.integration.test.js`.
- Actual public-source **17-item dry run passed**, including the six Quran references. The source/import adapter has **13 tests**, included in the backend total. No admin API write, publication or media download occurred in that check.
- Full Flutter analysis reports **no issues**; final whitespace checks passed. Existing Git LF/CRLF notices are not source errors.

Unit suites may use temporary synthetic/stub listeners, which close afterwards; no normal project service or real-user session is started. Automated layout coverage is not a guarantee for every physical device or font configuration.

No research collection/export was enabled, no real user was opted into sharing, no private record was sent to a publisher, no ML model was retrained and no content was publicly seeded. Public deployment still requires actual qualified review/publication, source maintenance, physical-device/browser acceptance, load/security testing and privacy/retention operations. The software cannot guarantee external availability, subjective soothing effects or clinical benefit.
