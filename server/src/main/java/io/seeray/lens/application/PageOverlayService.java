package io.seeray.lens.application;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.analytics.PageOverlaySession;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.*;

@ApplicationScoped
public class PageOverlayService {
    private static final Duration TTL = Duration.ofMinutes(15);
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final TypeReference<List<OverlayTarget>> TARGETS = new TypeReference<>() {};

    private final SiteService sites;
    private final AnalyticsQueryService analytics;
    private final SegmentedAnalyticsQueryService segmented;
    private final ObjectMapper mapper;

    @Inject
    public PageOverlayService(
            SiteService sites,
            AnalyticsQueryService analytics,
            SegmentedAnalyticsQueryService segmented,
            ObjectMapper mapper) {
        this.sites = sites;
        this.analytics = analytics;
        this.segmented = segmented;
        this.mapper = mapper;
    }

    @Transactional
    public Created create(UUID siteId, String sourcePath, String fromValue, String toValue, UUID segmentId) {
        Site site = sites.site(siteId);
        AnalyticsQueryService.Range range = analytics.range(siteId, fromValue, toValue);
        String path = normalizePath(sourcePath);
        Map<String, Map<String, Long>> counts = new TreeMap<>();
        for (AnalyticsQueryService.PageTransition transition : segmented.userFlow(siteId, range, segmentId)) {
            if (transition.sourcePath() != null && transition.targetPath() != null) {
                counts.computeIfAbsent(transition.sourcePath(), ignored -> new TreeMap<>())
                        .merge(transition.targetPath(), transition.sessions(), Long::sum);
            }
        }
        List<OverlayTarget> targets = counts.entrySet().stream()
                .flatMap(source -> source.getValue().entrySet().stream()
                        .map(target -> new OverlayTarget(source.getKey(), target.getKey(), target.getValue())))
                .toList();

        Instant now = Instant.now();
        PageOverlaySession.delete("expiresAt <= ?1", now);
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        PageOverlaySession session = new PageOverlaySession();
        session.id = UuidV7.next();
        session.site = site;
        session.tokenHash = tokenHash(token);
        session.sourcePath = path;
        session.fromDate = range.from();
        session.toDate = range.to();
        try {
            session.targetsJson = mapper.writeValueAsString(targets);
        } catch (Exception error) {
            throw new IllegalStateException("Could not prepare page overlay data", error);
        }
        session.createdAt = now;
        session.expiresAt = now.plus(TTL);
        session.persist();
        return new Created(session.id, token, session.expiresAt, path, targets.size());
    }

    public OverlayData read(String trackingId, UUID sessionId, String token) {
        PageOverlaySession session = PageOverlaySession.find("id = ?1 and site.trackingId = ?2", sessionId, trackingId)
                .firstResult();
        if (session == null) throw missing();
        if (!session.expiresAt.isAfter(Instant.now()))
            throw new ControlPlaneException(410, "PAGE_OVERLAY_EXPIRED", "Page overlay session has expired");
        if (token == null
                || token.isBlank()
                || !MessageDigest.isEqual(
                        session.tokenHash.getBytes(StandardCharsets.US_ASCII),
                        tokenHash(token).getBytes(StandardCharsets.US_ASCII)))
            throw new ControlPlaneException(403, "INVALID_PAGE_OVERLAY_TOKEN", "Page overlay token is invalid");
        try {
            return new OverlayData(
                    session.sourcePath,
                    session.fromDate,
                    session.toDate,
                    session.expiresAt,
                    mapper.readValue(session.targetsJson, TARGETS));
        } catch (Exception error) {
            throw new IllegalStateException("Could not read page overlay data", error);
        }
    }

    private static String normalizePath(String value) {
        if (value == null || value.isBlank() || value.length() > 2048 || !value.startsWith("/")) throw invalidPath();
        if (value.startsWith("//")
                || value.indexOf('?') >= 0
                || value.indexOf('#') >= 0
                || value.chars().anyMatch(Character::isISOControl)) throw invalidPath();
        return value;
    }

    private static String tokenHash(String token) {
        try {
            return HexFormat.of()
                    .formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    private static ControlPlaneException invalidPath() {
        return new ControlPlaneException(
                400, "INVALID_PAGE_PATH", "Page path must be a local path without a query or fragment");
    }

    private static ControlPlaneException missing() {
        return new ControlPlaneException(404, "PAGE_OVERLAY_NOT_FOUND", "Page overlay session was not found");
    }

    public record OverlayTarget(String sourcePath, String path, long sessions) {}

    public record Created(UUID sessionId, String token, Instant expiresAt, String sourcePath, int targetCount) {}

    public record OverlayData(
            String sourcePath, LocalDate from, LocalDate to, Instant expiresAt, List<OverlayTarget> targets) {}
}
