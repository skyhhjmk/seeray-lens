package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.seeray.lens.domain.common.ControlPlaneException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Bounded reader for the flat version-3 source map format used by browser bundles. */
final class SourceMapV3 {
    static final int MAX_BYTES = 5 * 1024 * 1024;
    private static final int MAX_SOURCES = 10_000;
    private static final int MAX_NAMES = 20_000;
    private static final int MAX_MAPPINGS = 500_000;
    private static final String BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    private final List<String> sources;
    private final List<String> names;
    private final List<List<Segment>> lines;

    private SourceMapV3(List<String> sources, List<String> names, List<List<Segment>> lines) {
        this.sources = sources;
        this.names = names;
        this.lines = lines;
    }

    static Prepared prepare(JsonNode input, ObjectMapper mapper) {
        if (input == null || !input.isObject()) throw invalid("The uploaded file is not a source map object");
        if (input.toString().getBytes(StandardCharsets.UTF_8).length > MAX_BYTES)
            throw invalid("Source maps must be 5 MiB or smaller");
        if (input.path("version").asInt(-1) != 3) throw invalid("Only source map version 3 is supported");
        if (input.has("sections")) throw invalid("Indexed source maps with sections are not supported yet");
        JsonNode sourcesNode = input.path("sources");
        JsonNode namesNode = input.path("names");
        JsonNode mappingsNode = input.path("mappings");
        if (!sourcesNode.isArray() || sourcesNode.isEmpty() || sourcesNode.size() > MAX_SOURCES)
            throw invalid("The source map must contain between 1 and 10,000 source files");
        if (!namesNode.isArray() || namesNode.size() > MAX_NAMES)
            throw invalid("The source map names table is invalid or too large");
        if (!mappingsNode.isTextual() || mappingsNode.textValue().length() > MAX_BYTES)
            throw invalid("The source map mappings field is invalid or too large");

        List<String> sources = strings(sourcesNode, 2048, "source file");
        List<String> names = strings(namesNode, 256, "symbol name");
        String sourceRoot = input.path("sourceRoot").asText("");
        if (sourceRoot.length() > 2048) throw invalid("The sourceRoot field is too long");
        List<String> resolvedSources =
                sources.stream().map(source -> safeSource(sourceRoot, source)).toList();
        List<List<Segment>> lines = decode(mappingsNode.textValue(), sources.size(), names.size());

        ObjectNode clean = mapper.createObjectNode();
        clean.put("version", 3);
        clean.set("sources", mapper.valueToTree(resolvedSources));
        clean.set("names", mapper.valueToTree(names));
        clean.put("mappings", mappingsNode.textValue());
        return new Prepared(clean, new SourceMapV3(resolvedSources, names, lines), sources.size());
    }

    Mapping originalPosition(int generatedLine, int generatedColumn) {
        if (generatedLine < 1 || generatedLine > lines.size() || generatedColumn < 0) return null;
        List<Segment> line = lines.get(generatedLine - 1);
        Segment match = null;
        for (Segment segment : line) {
            if (segment.generatedColumn > generatedColumn) break;
            match = segment;
        }
        if (match == null || match.sourceIndex < 0) return null;
        String name = match.nameIndex < 0 ? null : names.get(match.nameIndex);
        return new Mapping(sources.get(match.sourceIndex), match.originalLine + 1, match.originalColumn, name);
    }

    private static List<List<Segment>> decode(String mappings, int sourceCount, int nameCount) {
        List<List<Segment>> lines = new ArrayList<>();
        int source = 0, originalLine = 0, originalColumn = 0, name = 0;
        int totalMappings = 0;
        int lineStart = 0;
        while (lineStart <= mappings.length()) {
            int lineEnd = mappings.indexOf(';', lineStart);
            if (lineEnd < 0) lineEnd = mappings.length();
            if (lines.size() >= 1_000_000) throw invalid("The source map contains too many generated lines");
            List<Segment> line = new ArrayList<>();
            int generatedColumn = 0;
            int segmentStart = lineStart;
            while (segmentStart < lineEnd) {
                int segmentEnd = mappings.indexOf(',', segmentStart);
                if (segmentEnd < 0 || segmentEnd > lineEnd) segmentEnd = lineEnd;
                if (segmentEnd == segmentStart) throw invalid("The source map contains an empty mapping segment");
                String encodedSegment = mappings.substring(segmentStart, segmentEnd);
                if (encodedSegment.isEmpty()) throw invalid("The source map contains an empty mapping segment");
                int[] cursor = {0};
                generatedColumn = add(generatedColumn, vlq(encodedSegment, cursor));
                if (generatedColumn < 0) throw invalid("The source map contains an invalid generated column");
                if (!line.isEmpty() && generatedColumn < line.get(line.size() - 1).generatedColumn)
                    throw invalid("The source map mappings are not ordered by generated column");
                if (cursor[0] == encodedSegment.length()) {
                    line.add(new Segment(generatedColumn, -1, -1, -1, -1));
                } else {
                    source = add(source, vlq(encodedSegment, cursor));
                    originalLine = add(originalLine, vlq(encodedSegment, cursor));
                    originalColumn = add(originalColumn, vlq(encodedSegment, cursor));
                    if (source < 0 || source >= sourceCount || originalLine < 0 || originalColumn < 0)
                        throw invalid("The source map contains an out-of-range source position");
                    int nameIndex = -1;
                    if (cursor[0] < encodedSegment.length()) {
                        name = add(name, vlq(encodedSegment, cursor));
                        if (name < 0 || name >= nameCount)
                            throw invalid("The source map contains an invalid symbol name");
                        nameIndex = name;
                    }
                    if (cursor[0] != encodedSegment.length())
                        throw invalid("The source map contains a malformed mapping segment");
                    line.add(new Segment(generatedColumn, source, originalLine, originalColumn, nameIndex));
                }
                if (++totalMappings > MAX_MAPPINGS) throw invalid("The source map contains too many mappings");
                if (segmentEnd == lineEnd) break;
                segmentStart = segmentEnd + 1;
                if (segmentStart == lineEnd) throw invalid("The source map contains an empty mapping segment");
            }
            lines.add(List.copyOf(line));
            if (lineEnd == mappings.length()) break;
            lineStart = lineEnd + 1;
        }
        return List.copyOf(lines);
    }

    private static int vlq(String value, int[] cursor) {
        long result = 0;
        int shift = 0;
        boolean continued;
        do {
            if (cursor[0] >= value.length() || shift > 30)
                throw invalid("The source map contains an invalid VLQ value");
            int digit = BASE64.indexOf(value.charAt(cursor[0]++));
            if (digit < 0) throw invalid("The source map contains an invalid base64 character");
            continued = (digit & 32) != 0;
            if (shift == 30 && (digit & 31) > 3) throw invalid("The source map VLQ value is too large");
            result |= (long) (digit & 31) << shift;
            shift += 5;
        } while (continued);
        long decoded = result >>> 1;
        if (decoded > Integer.MAX_VALUE) throw invalid("The source map VLQ value is too large");
        return (result & 1) == 1 ? (int) -decoded : (int) decoded;
    }

    private static int add(int current, int delta) {
        long value = (long) current + delta;
        if (value < Integer.MIN_VALUE || value > Integer.MAX_VALUE)
            throw invalid("The source map contains an invalid offset");
        return (int) value;
    }

    private static List<String> strings(JsonNode array, int max, String label) {
        List<String> values = new ArrayList<>(array.size());
        for (JsonNode node : array) {
            if (!node.isTextual()
                    || node.textValue().isBlank()
                    || node.textValue().length() > max) throw invalid("The source map contains an invalid " + label);
            values.add(node.textValue());
        }
        return List.copyOf(values);
    }

    private static String safeSource(String root, String source) {
        String value = source.replace('\\', '/');
        if (!root.isBlank() && !value.matches("(?i)^[a-z][a-z0-9+.-]*://.*") && !value.startsWith("/"))
            value = root.replace('\\', '/') + "/" + value;
        value = value.replaceFirst("(?i)^webpack://(?:[^/]*/)?", "");
        value = value.replaceFirst("(?i)^file://", "");
        if (value.matches("(?i)^https?://.*")) {
            try {
                value = java.net.URI.create(value).getPath();
            } catch (Exception ignored) {
                value = "";
            }
        }
        while (value.startsWith("./")) value = value.substring(2);
        while (value.startsWith("../")) value = value.substring(3);
        // Never persist a developer's absolute checkout path; retain a useful source-relative suffix.
        if (value.startsWith("/")) {
            int rootIndex = Math.max(
                    value.lastIndexOf("/src/"), Math.max(value.lastIndexOf("/app/"), value.lastIndexOf("/packages/")));
            value = rootIndex >= 0 ? value.substring(rootIndex + 1) : value.substring(value.lastIndexOf('/') + 1);
        }
        if (value.matches("^[A-Za-z]:/.*")) value = value.substring(value.lastIndexOf('/') + 1);
        return TrackingSanitizer.safeCrashPath(value);
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "INVALID_SOURCE_MAP", message);
    }

    record Prepared(ObjectNode json, SourceMapV3 decoder, int sourceCount) {}

    record Mapping(String source, int line, int column, String name) {}

    private record Segment(int generatedColumn, int sourceIndex, int originalLine, int originalColumn, int nameIndex) {}
}
