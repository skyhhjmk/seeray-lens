package io.seeray.lens.application;

import java.util.*;

/** Shared channel rules for cached and live acquisition reports. */
final class AcquisitionClassifier {
    private static final List<String> AI_DOMAINS = List.of(
            "chatgpt.com",
            "openai.com",
            "claude.ai",
            "perplexity.ai",
            "gemini.google.com",
            "copilot.microsoft.com",
            "you.com",
            "poe.com",
            "phind.com",
            "mistral.ai");
    private static final List<String> SEARCH_DOMAINS = List.of(
            "google.com",
            "google.co.uk",
            "google.ca",
            "google.com.au",
            "google.de",
            "google.fr",
            "google.co.in",
            "google.co.jp",
            "google.com.br",
            "google.es",
            "google.it",
            "google.nl",
            "bing.com",
            "search.yahoo.com",
            "duckduckgo.com",
            "baidu.com",
            "yandex.ru",
            "yandex.com",
            "yandex.com.tr",
            "ecosia.org",
            "search.brave.com",
            "qwant.com",
            "naver.com");
    private static final List<String> SOCIAL_DOMAINS = List.of(
            "facebook.com",
            "instagram.com",
            "threads.net",
            "t.co",
            "twitter.com",
            "x.com",
            "linkedin.com",
            "reddit.com",
            "pinterest.com",
            "tiktok.com",
            "youtube.com",
            "youtu.be",
            "snapchat.com",
            "mastodon.social");

    private AcquisitionClassifier() {}

    static String channel(
            String referrer,
            String pageHost,
            String source,
            String medium,
            String campaign,
            String term,
            String content,
            Set<String> internalHosts) {
        if (hasText(source) || hasText(medium) || hasText(campaign) || hasText(term) || hasText(content))
            return "campaign";
        String host = normalize(referrer);
        if (host == null || host.equalsIgnoreCase(normalize(pageHost)) || containsHost(internalHosts, host))
            return "direct";
        if (matches(host, AI_DOMAINS)) return "ai_assistant";
        if (matches(host, SEARCH_DOMAINS)) return "search_engine";
        if (matches(host, SOCIAL_DOMAINS)) return "social";
        return "referral";
    }

    static String source(String channel, String referrer, String utmSource) {
        return "campaign".equals(channel)
                ? emptyToNull(utmSource)
                : "direct".equals(channel) ? null : emptyToNull(referrer);
    }

    static String channelSql(String alias) {
        String referrer = alias + ".initial_referrer_host";
        String pageHost = alias + ".initial_page_host";
        String utm = String.join(
                " or ",
                "nullif(btrim(" + alias + ".initial_utm_source),'') is not null",
                "nullif(btrim(" + alias + ".initial_utm_medium),'') is not null",
                "nullif(btrim(" + alias + ".initial_utm_campaign),'') is not null",
                "nullif(btrim(" + alias + ".initial_utm_term),'') is not null",
                "nullif(btrim(" + alias + ".initial_utm_content),'') is not null");
        String blankReferrer = "nullif(btrim(" + referrer + "),'') is null";
        String internal = "exists(select 1 from site_allowed_domain d where d.site_id=" + alias
                + ".site_id and d.enabled and lower(d.host)=lower(" + referrer + "))";
        return "case when (" + utm + ") then 'campaign' "
                + "when (" + blankReferrer + " or lower(" + referrer + ")=lower(coalesce(" + pageHost
                + ",'')) or " + internal + ") then 'direct' "
                + "when " + matchesSql(referrer, AI_DOMAINS) + " then 'ai_assistant' "
                + "when " + matchesSql(referrer, SEARCH_DOMAINS) + " then 'search_engine' "
                + "when " + matchesSql(referrer, SOCIAL_DOMAINS) + " then 'social' else 'referral' end";
    }

    private static String matchesSql(String host, List<String> domains) {
        String lower = "lower(" + host + ")";
        return "("
                + String.join(
                        " or ",
                        domains.stream()
                                .map(domain ->
                                        "(" + lower + "='" + domain + "' or " + lower + " like '%." + domain + "')")
                                .toList())
                + ")";
    }

    private static boolean matches(String host, List<String> domains) {
        return domains.stream().anyMatch(domain -> host.equals(domain) || host.endsWith("." + domain));
    }

    private static boolean containsHost(Set<String> hosts, String host) {
        return hosts != null && hosts.stream().anyMatch(item -> item.equalsIgnoreCase(host));
    }

    private static String normalize(String value) {
        return emptyToNull(value) == null ? null : value.trim().toLowerCase(Locale.ROOT);
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private static String emptyToNull(String value) {
        return hasText(value) ? value.trim() : null;
    }
}
