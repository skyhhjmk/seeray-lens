# Acquisition reports

Acquisition reports use session-level attribution facts, retaining the first non-empty referrer host and UTM values observed in each session: `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, and `utm_content`. UTM fields remain available as report dimensions and segment rules; campaign term/content are not interpreted as click IDs.

Channel classification follows this precedence:

1. Any non-empty UTM field is `campaign`.
2. Missing referrer, a same-site referrer, or a configured allowed site domain is `direct`.
3. Known AI assistant referrers are `ai_assistant`.
4. Known search providers are `search_engine`.
5. Known social networks are `social`.
6. Other external referrers are `referral`.

The current provider list is maintained in `AcquisitionClassifier`: AI assistants include ChatGPT/OpenAI, Claude, Perplexity, Gemini, Copilot, You.com, Poe, Phind, and Mistral; search includes Google, Bing, Yahoo, DuckDuckGo, Baidu, Yandex, Ecosia, Brave Search, Qwant, and Naver; social includes Facebook, Instagram, Threads, X/Twitter, LinkedIn, Reddit, Pinterest, TikTok, YouTube, Snapchat, and Mastodon.social. This list is intentionally explicit and may need updates as providers change domains.

Cached, unsegmented reports and live segmented reports use the same channel precedence. The acquisition UI and traffic dashboard expose source, medium, campaign, term, and content. Custom reports and saved segments additionally expose campaign term/content dimensions.

The existing traffic breakdown remains session-level source classification. It does not collect advertising click IDs or estimate paid-media cost. Existing source/medium values are retained rather than inferred from a channel label.

## Conversion attribution

The authenticated `GET /api/v1/sites/{siteId}/analytics/attribution` report attributes configured goal conversions to the visitor's eligible acquisition sessions. It accepts the selected event-date range, optional `goalId` and saved `segmentId`, one of `first_touch`, `last_touch`, `linear`, `position_based`, or `time_decay`, and a 7-, 30-, or 90-day `lookbackDays` window. A saved segment filters the conversion session; earlier touch sessions in the lookback window are still considered even when they do not match that segment.

For this report, a conversion is one enabled goal matched in one session, even if the goal fires repeatedly during that session. The UI labels the resulting measure “attributed conversions”; fractional credits across all included touch sessions sum to one for each such goal/session conversion. Goal fixed value is credited using the same share. Direct visits remain eligible and can receive credit. Position-based attribution uses 40% for the first touch, 40% for the last, and shares the remaining 20% evenly across middle touches (a single touch receives 100%, and two touches receive 50% each). Time decay uses a seven-day half-life and normalizes the shares within each conversion. The time-decay half-life is fixed while the lookback window is selectable.

Attribution is a reporting model, not causal evidence. The conversion and its touches are joined through the site's pseudonymous visitor/session facts; clearing visitor storage or switching devices can fragment a journey. Click IDs, ad spend/cost import, and external ad-platform export remain unsupported. The Acquisition page links to a graphical model comparison with goal, lookback-window, and saved-segment controls; no JSON configuration is exposed to operators.
