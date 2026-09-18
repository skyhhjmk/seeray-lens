# Media analytics

Media analytics is deliberately opt-in at both levels: the tracker script must include `data-track-media`, and each measured `<audio>` or `<video>` element must carry a stable non-personal `data-seeray-media` ID. The generated example is available from the site's Integration → Media analytics tab.

```html
<script src="https://analytics.example.test/tracker.js" data-site-id="TRACKING_ID" data-track-media></script>
<video data-seeray-media="product-demo" controls>
  <source src="/media/product-demo.mp4" type="video/mp4">
</video>
```

The tracker reports one start per media element and page visit, the first time playback reaches 25%, 50%, 75%, and 90%, and natural playback completion (`ended`). Reaching a milestone by seeking counts as reaching that point; seeking straight to the end does not count as a completion. Live streams and media without a finite duration can still report start and natural completion but do not report progress milestones.

Only the explicit media ID, generic audio/video type, milestone, bounded duration on completion, page path, and the tracker's normal anonymous session context are stored. The tracker does not read or transmit media source URLs, titles, captions, poster URLs, or media content. Add `data-seeray-no-track` to the media element or an ancestor to suppress its measurement. Do Not Track and the site's consent policy still govern collection.

The Behaviour → Media report aggregates starts, unique visitors, milestone reach, natural completions, non-completion sessions, average completed-media duration, and completion rate by media ID and page. It does not return raw event properties or media source data. Reports use the site's timezone and the shared analytics date range.
