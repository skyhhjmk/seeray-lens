package io.seeray.lens.application;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/** Server-side allowlist and redaction for opt-in browser crash events. */
public final class CrashDataSanitizer {
    private CrashDataSanitizer() {}

    public static Map<String, Object> sanitize(Map<String, ?> input) {
        Map<String, ?> source = input == null ? Map.of() : input;
        String errorName = safeName(source.get("errorName"));
        String message = safeMessage(source.get("message"));
        String sourcePath = TrackingSanitizer.safeCrashPath(text(source.get("sourcePath"), 1024));
        Integer line = position(source.get("line"));
        Integer column = position(source.get("column"));
        String releaseId = safeRelease(source.get("releaseId"));
        String functionName = safeFunctionName(source.get("functionName"));
        String platform = safePlatform(source.get("platform"));
        String fingerprint = fingerprint(platform, errorName, message, sourcePath, line, column);
        Map<String, Object> clean = new LinkedHashMap<>();
        clean.put("platform", platform);
        clean.put("errorName", errorName);
        clean.put("message", message);
        clean.put("sourcePath", sourcePath);
        if (line != null) clean.put("line", line);
        if (column != null) clean.put("column", column);
        if (releaseId != null) clean.put("releaseId", releaseId);
        if (functionName != null) clean.put("functionName", functionName);
        clean.put("fingerprint", fingerprint);
        return clean;
    }

    public static void refreshFingerprint(Map<String, Object> clean) {
        clean.put(
                "fingerprint",
                fingerprint(
                        String.valueOf(clean.getOrDefault("platform", "web")),
                        String.valueOf(clean.getOrDefault("errorName", "Error")),
                        String.valueOf(clean.getOrDefault("message", "No error message")),
                        String.valueOf(clean.getOrDefault("sourcePath", "/")),
                        clean.get("line") instanceof Integer line ? line : null,
                        clean.get("column") instanceof Integer column ? column : null));
    }

    private static String safePlatform(Object value) {
        if (!(value instanceof String platform)) return "web";
        return switch (platform) {
            case "web", "android", "ios" -> platform;
            default -> "web";
        };
    }

    private static String safeRelease(Object value) {
        if (!(value instanceof String release)) return null;
        String clean = release.strip();
        return clean.matches("[A-Za-z0-9][A-Za-z0-9._+-]{0,99}") ? clean : null;
    }

    static String safeFunctionName(Object value) {
        if (!(value instanceof String name)) return null;
        String clean = name.replaceAll("[\\p{Cc}]", "")
                .replaceAll("(?i)bearer\\s+[^\\s,;]+", "Bearer <redacted>")
                .replaceAll("(?i)(api[_-]?key|token|secret|password)\\s*[:=]\\s*[^\\s,;]+", "$1=<redacted>")
                .replaceAll("https?://\\S+", "<url>")
                .replaceAll("[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}", "<email>")
                .replaceAll("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\b", "<id>")
                .replaceAll("\\b(?:[A-Za-z0-9_-]{32,}|\\d{4,})\\b", "<value>")
                .strip();
        if (clean.isBlank()) return null;
        return clean.length() > 120 ? clean.substring(0, 120) : clean;
    }

    private static String safeName(Object value) {
        String name = text(value, 80).replaceAll("[^A-Za-z0-9_.$-]", "");
        return name.isBlank() ? "Error" : name;
    }

    private static String safeMessage(Object value) {
        String message = text(value, 4096)
                .replaceAll("(?i)bearer\\s+[^\\s,;]+", "Bearer <redacted>")
                .replaceAll("(?i)(api[_-]?key|token|secret|password)\\s*[:=]\\s*[^\\s,;]+", "$1=<redacted>")
                .replaceAll("https?://\\S+", "<url>")
                .replaceAll("[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}", "<email>")
                .replaceAll("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\b", "<id>")
                .replaceAll("(?:[A-Za-z]:\\\\|/(?:home|Users|tmp|var|opt)/)[^\\s:]+", "<path>")
                .replaceAll("\\b(?:[A-Za-z0-9_-]{32,}|\\d{4,})\\b", "<value>")
                .replaceAll("[\\p{Cc}]", "")
                .replaceAll("\\s+", " ")
                .trim();
        if (message.isBlank()) return "No error message";
        return message.length() > 240 ? message.substring(0, 240) : message;
    }

    private static String text(Object value, int max) {
        if (!(value instanceof String string)) return "";
        String clean = string.replaceAll("[\\p{Cc}]", "").trim();
        return clean.length() > max ? clean.substring(0, max) : clean;
    }

    private static Integer position(Object value) {
        if (!(value instanceof Number number)) return null;
        long position = number.longValue();
        if (position < 1 || position > 10_000_000 || number.doubleValue() != position) return null;
        return (int) position;
    }

    private static String fingerprint(
            String platform, String errorName, String message, String sourcePath, Integer line, Integer column) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest((("web".equals(platform) ? "" : platform + "\n") + errorName + "\n" + message + "\n"
                                    + sourcePath + "\n" + (line == null ? "" : line) + "\n"
                                    + (column == null ? "" : column))
                            .getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest, 0, 8).toLowerCase(Locale.ROOT);
        } catch (Exception error) {
            throw new IllegalStateException("Could not fingerprint browser error", error);
        }
    }
}
