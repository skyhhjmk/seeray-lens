package io.seeray.lens.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import java.net.IDN;
import java.net.URI;
import java.util.*;

public final class TrackingSanitizer {
    private static final Set<String> UTM =
            Set.of("utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content");

    private TrackingSanitizer() {}

    public static CleanUrl url(String value, ObjectMapper mapper) {
        return url(value, mapper, null);
    }

    public static CleanUrl url(String value, ObjectMapper mapper, String title) {
        String cleanTitle = cleanTitle(title);
        if (value == null || value.isBlank())
            return new CleanUrl(null, null, null, null, null, null, null, null, cleanTitle, null, null);
        try {
            URI uri = URI.create(value.trim());
            if (uri.getScheme() == null || uri.getHost() == null || uri.getUserInfo() != null)
                throw new IllegalArgumentException();
            String host = IDN.toASCII(uri.getHost(), IDN.USE_STD3_ASCII_RULES).toLowerCase(Locale.ROOT);
            String path = uri.getPath() == null || uri.getPath().isBlank() ? "/" : limit(uri.getPath(), 2048);
            Map<String, String> utm = new HashMap<>();
            if (uri.getRawQuery() != null) {
                for (String part : uri.getRawQuery().split("&")) {
                    String[] pair = part.split("=", 2);
                    if (pair.length == 2 && UTM.contains(pair[0])) utm.put(pair[0], limit(pair[1], 256));
                }
            }
            return new CleanUrl(
                    uri.getScheme().toLowerCase(Locale.ROOT),
                    host,
                    path,
                    utm.get("utm_source"),
                    utm.get("utm_medium"),
                    utm.get("utm_campaign"),
                    utm.get("utm_term"),
                    utm.get("utm_content"),
                    cleanTitle,
                    null,
                    null);
        } catch (Exception e) {
            throw new ControlPlaneException(400, "INVALID_EVENT_URL", "Event URL is invalid");
        }
    }

    /** Crash reports intentionally discard query parameters, titles, and UTM values. */
    public static CleanUrl crashUrl(String value, ObjectMapper mapper) {
        CleanUrl clean = url(value, mapper);
        return new CleanUrl(
                clean.scheme(),
                clean.host(),
                safeCrashPath(clean.path()),
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null);
    }

    /** Removes common identifiers from route and script paths before storing crash diagnostics. */
    public static String safeCrashPath(String value) {
        if (value == null || value.isBlank()) return "/";
        String path = value.replaceAll("[\\p{Cc}]", "").replace('\\', '/').split("[?#]", 2)[0];
        if (path.matches("(?i)^[a-z][a-z0-9+.-]*://.*")) {
            try {
                path = URI.create(path).getPath();
            } catch (Exception ignored) {
                return "/";
            }
        }
        if (path == null || path.isBlank()) return "/";
        if (!path.startsWith("/")) path = "/" + path;
        path = path.replaceAll("(?i)[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}", "<email>");
        path = path.replaceAll("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\b", "<id>");
        path = path.replaceAll("(^|/)\\d{4,}(?=/|$)", "$1<id>");
        path = path.replaceAll("(^|/)[A-Za-z0-9_-]{32,}(?=/|$)", "$1<id>");
        return path.length() > 1024 ? path.substring(0, 1024) : path;
    }

    private static String cleanTitle(String value) {
        if (value == null || value.isBlank()) return null;
        String cleaned = value.strip().replaceAll("[\\p{Cc}]", "");
        return cleaned.isBlank() ? null : limit(cleaned, 512);
    }

    public static String json(Object value, ObjectMapper mapper) {
        try {
            if (value == null) return "{}";
            if (value instanceof com.fasterxml.jackson.databind.JsonNode node) {
                if (depth(node, 0) > 5 || node.isObject() && node.size() > 50) throw new IllegalArgumentException();
                return mapper.writeValueAsString(node);
            }
            com.fasterxml.jackson.databind.JsonNode node = mapper.valueToTree(value);
            if (depth(node, 0) > 5 || hasTooManyKeys(node)) throw new IllegalArgumentException();
            String json = mapper.writeValueAsString(node);
            if (json.length() > 16_384) throw new IllegalArgumentException();
            return json;
        } catch (JsonProcessingException | IllegalArgumentException e) {
            throw new ControlPlaneException(400, "INVALID_EVENT_DATA", "Event data is invalid");
        }
    }

    private static String limit(String s, int max) {
        if (s.length() > max) throw new IllegalArgumentException();
        return s;
    }

    private static int depth(com.fasterxml.jackson.databind.JsonNode n, int level) {
        int max = level;
        if (n.isContainerNode()) for (var child : n) max = Math.max(max, depth(child, level + 1));
        return max;
    }

    private static boolean hasTooManyKeys(com.fasterxml.jackson.databind.JsonNode n) {
        if (n.isObject() && n.size() > 50) return true;
        if (n.isContainerNode()) for (var child : n) if (hasTooManyKeys(child)) return true;
        return false;
    }

    public record CleanUrl(
            String scheme,
            String host,
            String path,
            String source,
            String medium,
            String campaign,
            String term,
            String content,
            String title,
            String referrerScheme,
            String referrerHost) {}
}
