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
        String fingerprint = fingerprint(errorName, message, sourcePath, line);
        Map<String, Object> clean = new LinkedHashMap<>();
        clean.put("errorName", errorName);
        clean.put("message", message);
        clean.put("sourcePath", sourcePath);
        if (line != null) clean.put("line", line);
        if (column != null) clean.put("column", column);
        clean.put("fingerprint", fingerprint);
        return clean;
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

    private static String fingerprint(String errorName, String message, String sourcePath, Integer line) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest((errorName + "\n" + message + "\n" + sourcePath + "\n" + (line == null ? "" : line))
                            .getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest, 0, 8).toLowerCase(Locale.ROOT);
        } catch (Exception error) {
            throw new IllegalStateException("Could not fingerprint browser error", error);
        }
    }
}
