package io.seeray.lens.application;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.seeray.lens.api.AnalyticsAlertResource.AlertInput;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.io.IOException;
import java.math.*;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Pattern;
import javax.sql.DataSource;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.quartz.*;

@ApplicationScoped
public class AnalyticsAlertService {
    private static final String GROUP = "analytics-alert";
    private static final Set<String> METRICS = Set.of("visitors", "sessions", "page_views", "bounce_rate");
    private static final Set<String> DIRECTIONS = Set.of("increase", "decrease");
    private static final Set<String> BASELINES = Set.of("previous_day", "same_weekday_last_week");
    private static final Set<String> CHANNELS = Set.of("email", "slack", "teams");
    private static final Set<String> SLACK_HOSTS = Set.of("hooks.slack.com", "hooks.slack-gov.com");
    private static final Set<String> TEAMS_HOST_SUFFIXES =
            Set.of("webhook.office.com", "webhook.office365.com", "logic.azure.com");
    private static final Pattern EMAIL = Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");
    private static final DateTimeFormatter LOCAL_STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    @Inject
    DataSource dataSource;

    @Inject
    SiteService sites;

    @Inject
    WorkspaceAccess access;

    @Inject
    Scheduler scheduler;

    @Inject
    Mailer mailer;

    @ConfigProperty(name = "seeray.reports.email-enabled", defaultValue = "false")
    boolean emailEnabled;

    @ConfigProperty(name = "seeray.alerts.slack-webhook-url", defaultValue = "")
    String slackWebhookUrl;

    @ConfigProperty(name = "seeray.alerts.teams-webhook-url", defaultValue = "")
    String teamsWebhookUrl;

    public ListResponse list(UUID siteId) {
        Site site = sites.site(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        List<AlertView> alerts = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select id,name,metric,direction,baseline,threshold_percent,local_time,timezone,channels,recipients,enabled,last_evaluated_date,last_evaluated_at,last_status,last_message,last_value,last_change_percent,last_baseline_date "
                                + "from analytics_alert where site_id=? order by created_at,id")) {
            statement.setObject(1, siteId);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) alerts.add(view(rows));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list analytics alerts", error);
        }
        return new ListResponse(
                emailEnabled, slackConfigured(), teamsConfigured(), canManage, site.timezone, List.copyOf(alerts));
    }

    @Transactional
    public AlertView create(UUID siteId, AlertInput input) {
        Site site = requireAdmin(siteId);
        Normalized normalized = normalize(input, site.timezone);
        if (count(siteId) >= 20)
            throw new ControlPlaneException(409, "ALERT_LIMIT", "A site can have at most 20 analytics alerts");
        UUID id = UuidV7.next();
        Instant now = Instant.now();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_alert(id,site_id,name,metric,direction,baseline,threshold_percent,local_time,timezone,channels,recipients,enabled,created_at,updated_at) "
                                + "values(?,?,?,?,?,?,?,?,?,?,?,?,?,?)")) {
            statement.setObject(1, id);
            statement.setObject(2, siteId);
            statement.setString(3, normalized.name());
            statement.setString(4, normalized.metric());
            statement.setString(5, normalized.direction());
            statement.setString(6, normalized.baseline());
            statement.setBigDecimal(7, normalized.thresholdPercent());
            statement.setObject(8, normalized.localTime());
            statement.setString(9, site.timezone);
            statement.setArray(
                    10, connection.createArrayOf("text", normalized.channels().toArray()));
            statement.setArray(
                    11, connection.createArrayOf("text", normalized.recipients().toArray()));
            statement.setBoolean(12, normalized.enabled());
            statement.setTimestamp(13, Timestamp.from(now));
            statement.setTimestamp(14, Timestamp.from(now));
            statement.executeUpdate();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save analytics alert", error);
        }
        synchronizeSchedule(id, site, normalized);
        return find(siteId, id);
    }

    @Transactional
    public AlertView update(UUID siteId, UUID alertId, AlertInput input) {
        Site site = requireAdmin(siteId);
        Normalized normalized = normalize(input, site.timezone);
        if (!exists(siteId, alertId)) throw notFound();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "update analytics_alert set name=?,metric=?,direction=?,baseline=?,threshold_percent=?,local_time=?,timezone=?,channels=?,recipients=?,enabled=?,updated_at=now() "
                                + "where id=? and site_id=?")) {
            statement.setString(1, normalized.name());
            statement.setString(2, normalized.metric());
            statement.setString(3, normalized.direction());
            statement.setString(4, normalized.baseline());
            statement.setBigDecimal(5, normalized.thresholdPercent());
            statement.setObject(6, normalized.localTime());
            statement.setString(7, site.timezone);
            statement.setArray(
                    8, connection.createArrayOf("text", normalized.channels().toArray()));
            statement.setArray(
                    9, connection.createArrayOf("text", normalized.recipients().toArray()));
            statement.setBoolean(10, normalized.enabled());
            statement.setObject(11, alertId);
            statement.setObject(12, siteId);
            statement.executeUpdate();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not update analytics alert", error);
        }
        synchronizeSchedule(alertId, site, normalized);
        return find(siteId, alertId);
    }

    @Transactional
    public void delete(UUID siteId, UUID alertId) {
        requireAdmin(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("delete from analytics_alert where id=? and site_id=?")) {
            statement.setObject(1, alertId);
            statement.setObject(2, siteId);
            if (statement.executeUpdate() == 0) throw notFound();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not delete analytics alert", error);
        }
        try {
            scheduler.deleteJob(jobKey(alertId));
        } catch (SchedulerException error) {
            throw new IllegalStateException("Could not remove analytics alert schedule", error);
        }
    }

    public void run(UUID alertId) {
        Evaluation evaluation = loadEvaluation(alertId);
        if (evaluation == null) {
            try {
                scheduler.deleteJob(jobKey(alertId));
            } catch (SchedulerException error) {
                throw new IllegalStateException("Could not remove orphaned analytics alert", error);
            }
            return;
        }
        LocalDate reportDate = LocalDate.now(ZoneId.of(evaluation.timezone())).minusDays(1);
        if (evaluation.lastEvaluatedDate() != null
                && !evaluation.lastEvaluatedDate().isBefore(reportDate)) return;
        LocalDate baselineDate = "same_weekday_last_week".equals(evaluation.baseline())
                ? reportDate.minusDays(7)
                : reportDate.minusDays(1);
        try {
            double current = metricValue(evaluation.siteId(), evaluation.metric(), reportDate);
            double baseline = metricValue(evaluation.siteId(), evaluation.metric(), baselineDate);
            double change = percentChange(current, baseline);
            boolean fired = shouldTrigger(
                    evaluation.direction(),
                    change,
                    evaluation.thresholdPercent().doubleValue());
            if (fired) deliver(evaluation, reportDate, baselineDate, current, baseline, change);
            String status = fired ? "triggered" : "unchanged";
            String message = fired
                    ? String.format(
                            Locale.ROOT,
                            "Threshold crossed: %s changed %s%% (limit %s%%).",
                            metricLabel(evaluation.metric()),
                            signed(change),
                            evaluation.thresholdPercent().stripTrailingZeros().toPlainString())
                    : "No threshold crossed for the last completed site-local day.";
            saveEvaluation(alertId, reportDate, baselineDate, status, message, current, change);
        } catch (Exception error) {
            saveEvaluation(
                    alertId,
                    reportDate,
                    baselineDate,
                    "failed",
                    "Evaluation or notification failed. Check aggregate availability and configured delivery channels.",
                    null,
                    null);
        }
    }

    static double percentChange(double current, double baseline) {
        if (baseline == 0) return current == 0 ? 0 : 100_000;
        return ((current - baseline) / Math.abs(baseline)) * 100;
    }

    static boolean shouldTrigger(String direction, double changePercent, double thresholdPercent) {
        return "increase".equals(direction)
                ? changePercent >= thresholdPercent
                : "decrease".equals(direction) && changePercent <= -thresholdPercent;
    }

    private void deliver(
            Evaluation alert,
            LocalDate reportDate,
            LocalDate baselineDate,
            double current,
            double baseline,
            double change)
            throws Exception {
        String message = "SeeRay Lens analytics alert — " + alert.siteName() + "\n"
                + alert.name() + "\n"
                + metricLabel(alert.metric()) + " on " + reportDate + ": " + value(alert.metric(), current)
                + " (" + alert.baselineLabel() + ", " + baselineDate + ": " + value(alert.metric(), baseline) + ")\n"
                + "Change: " + signed(change) + "% (threshold: " + alert.direction() + " by at least "
                + alert.thresholdPercent().stripTrailingZeros().toPlainString() + "%).";
        List<String> failed = new ArrayList<>();
        for (String channel : alert.channels()) {
            try {
                switch (channel) {
                    case "email" -> sendEmail(alert.recipients(), alert.name(), message);
                    case "slack" -> sendSlack(message);
                    case "teams" -> sendTeams(message);
                    default -> throw new IllegalStateException("Unsupported delivery channel");
                }
            } catch (Exception error) {
                failed.add(channel);
            }
        }
        if (!failed.isEmpty()) throw new IOException("One or more alert channels failed");
    }

    private void sendEmail(List<String> recipients, String alertName, String message) {
        if (!emailEnabled) throw new IllegalStateException("Email delivery is disabled");
        for (String recipient : recipients) {
            mailer.send(Mail.withText(recipient, "Analytics alert: " + alertName, message));
        }
    }

    private void sendSlack(String message) throws IOException, InterruptedException {
        postWebhook(slackWebhookUrl, true, message);
    }

    private void sendTeams(String message) throws IOException, InterruptedException {
        postWebhook(teamsWebhookUrl, false, message);
    }

    private static void postWebhook(String endpoint, boolean slack, String message)
            throws IOException, InterruptedException {
        if (!validWebhook(endpoint, slack)) throw new IllegalStateException("Notification endpoint is unavailable");
        String payload = slack
                ? "{\"text\":\"" + jsonEscape(message) + "\"}"
                : "{\"type\":\"message\",\"attachments\":[{\"contentType\":\"application/vnd.microsoft.card.adaptive\",\"content\":{\"$schema\":\"http://adaptivecards.io/schemas/adaptive-card.json\",\"type\":\"AdaptiveCard\",\"version\":\"1.2\",\"body\":[{\"type\":\"TextBlock\",\"text\":\""
                        + jsonEscape(message)
                        + "\",\"wrap\":true}]}}]}";
        HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint))
                .timeout(Duration.ofSeconds(8))
                .header("Content-Type", "application/json; charset=utf-8")
                .POST(HttpRequest.BodyPublishers.ofString(payload, StandardCharsets.UTF_8))
                .build();
        HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() < 200
                || response.statusCode() >= 300
                || (slack && !"ok".equals(response.body().trim()))) {
            throw new IOException("Notification endpoint rejected the alert");
        }
    }

    private static String jsonEscape(String value) {
        StringBuilder escaped = new StringBuilder(value.length() + 16);
        for (int index = 0; index < value.length(); index++) {
            char c = value.charAt(index);
            switch (c) {
                case '"' -> escaped.append("\\\"");
                case '\\' -> escaped.append("\\\\");
                case '\n' -> escaped.append("\\n");
                case '\r' -> escaped.append("\\r");
                case '\t' -> escaped.append("\\t");
                default -> {
                    if (c < 0x20) escaped.append(String.format(Locale.ROOT, "\\u%04x", (int) c));
                    else escaped.append(c);
                }
            }
        }
        return escaped.toString();
    }

    private double metricValue(UUID siteId, String metric, LocalDate date) throws SQLException {
        if ("visitors".equals(metric)) {
            try (Connection connection = dataSource.getConnection();
                    PreparedStatement statement = connection.prepareStatement(
                            "select count(distinct visitor_id) from visitor_day_fact where site_id=? and business_date=?")) {
                statement.setObject(1, siteId);
                statement.setObject(2, date);
                try (ResultSet result = statement.executeQuery()) {
                    result.next();
                    return result.getDouble(1);
                }
            }
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select coalesce(sum(page_view_count),0),coalesce(sum(session_count),0),coalesce(sum(bounced_session_count),0) "
                                + "from analytics_site_daily where site_id=? and business_date=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, date);
            try (ResultSet result = statement.executeQuery()) {
                result.next();
                double pageViews = result.getDouble(1);
                double sessions = result.getDouble(2);
                double bounced = result.getDouble(3);
                return switch (metric) {
                    case "sessions" -> sessions;
                    case "page_views" -> pageViews;
                    case "bounce_rate" -> sessions == 0 ? 0 : bounced * 100 / sessions;
                    default -> throw new IllegalArgumentException("Unsupported alert metric");
                };
            }
        }
    }

    private Evaluation loadEvaluation(UUID id) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select a.site_id,s.name,a.name,a.metric,a.direction,a.baseline,a.threshold_percent,a.channels,a.recipients,a.timezone,a.last_evaluated_date "
                                + "from analytics_alert a join site s on s.id=a.site_id where a.id=? and a.enabled=true")) {
            statement.setObject(1, id);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return null;
                return new Evaluation(
                        id,
                        row.getObject(1, UUID.class),
                        row.getString(2),
                        row.getString(3),
                        row.getString(4),
                        row.getString(5),
                        row.getString(6),
                        row.getBigDecimal(7),
                        stringArray(row.getArray(8)),
                        stringArray(row.getArray(9)),
                        row.getString(10),
                        row.getObject(11, LocalDate.class));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load analytics alert", error);
        }
    }

    private void saveEvaluation(
            UUID id,
            LocalDate reportDate,
            LocalDate baselineDate,
            String status,
            String message,
            Double value,
            Double change) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "update analytics_alert set last_evaluated_date=?,last_evaluated_at=now(),last_status=?,last_message=?,last_value=?,last_change_percent=?,last_baseline_date=?,updated_at=now() where id=?")) {
            statement.setObject(1, reportDate);
            statement.setString(2, status);
            statement.setString(3, message);
            if (value == null) statement.setNull(4, Types.NUMERIC);
            else statement.setBigDecimal(4, BigDecimal.valueOf(value).setScale(4, RoundingMode.HALF_UP));
            if (change == null) statement.setNull(5, Types.NUMERIC);
            else statement.setBigDecimal(5, BigDecimal.valueOf(change).setScale(2, RoundingMode.HALF_UP));
            statement.setObject(6, baselineDate);
            statement.setObject(7, id);
            statement.executeUpdate();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not persist analytics alert evaluation", error);
        }
    }

    private void synchronizeSchedule(UUID id, Site site, Normalized normalized) {
        try {
            if (!normalized.enabled()) {
                scheduler.deleteJob(jobKey(id));
                return;
            }
            JobDetail job = scheduler.getJobDetail(jobKey(id));
            boolean newJob = job == null;
            if (newJob)
                job = JobBuilder.newJob(AnalyticsAlertJob.class)
                        .withIdentity(jobKey(id))
                        .usingJobData("alertId", id.toString())
                        .build();
            CronScheduleBuilder cron = CronScheduleBuilder.cronSchedule(normalized.cron())
                    .inTimeZone(TimeZone.getTimeZone(ZoneId.of(site.timezone)))
                    .withMisfireHandlingInstructionDoNothing();
            Trigger trigger = TriggerBuilder.newTrigger()
                    .withIdentity(triggerKey(id))
                    .forJob(job)
                    .withSchedule(cron)
                    .startNow()
                    .build();
            if (newJob) scheduler.scheduleJob(job, trigger);
            else if (scheduler.rescheduleJob(triggerKey(id), trigger) == null) scheduler.scheduleJob(trigger);
        } catch (SchedulerException error) {
            throw new IllegalStateException("Could not update analytics alert schedule", error);
        }
    }

    private Normalized normalize(AlertInput input, String timezone) {
        if (input == null) throw invalid("Alert details are required");
        String name = input.name() == null ? "" : input.name().trim();
        if (name.isBlank() || name.length() > 120 || name.chars().anyMatch(Character::isISOControl))
            throw invalid("An alert name of 1 to 120 printable characters is required");
        String metric = normalizeChoice(input.metric(), METRICS, "metric");
        String direction = normalizeChoice(input.direction(), DIRECTIONS, "direction");
        String baseline = normalizeChoice(input.baseline(), BASELINES, "baseline");
        BigDecimal threshold;
        try {
            threshold = BigDecimal.valueOf(input.thresholdPercent()).setScale(2, RoundingMode.HALF_UP);
        } catch (RuntimeException error) {
            throw invalid("Enter a percentage threshold greater than 0 and no more than 1000");
        }
        if (threshold.signum() <= 0 || threshold.compareTo(BigDecimal.valueOf(1000)) > 0)
            throw invalid("Enter a percentage threshold greater than 0 and no more than 1000");
        LocalTime time;
        try {
            time = LocalTime.parse(input.localTime());
        } catch (RuntimeException error) {
            throw invalid("Choose a valid local evaluation time");
        }
        List<String> channels = input.channels() == null
                ? List.of()
                : input.channels().stream()
                        .filter(Objects::nonNull)
                        .map(value -> value.toLowerCase(Locale.ROOT))
                        .distinct()
                        .sorted()
                        .toList();
        if (channels.isEmpty() || !CHANNELS.containsAll(channels))
            throw invalid("Choose at least one available notification channel");
        if (channels.contains("email") && !emailEnabled) throw channelUnavailable("email");
        if (channels.contains("slack") && !slackConfigured()) throw channelUnavailable("Slack");
        if (channels.contains("teams") && !teamsConfigured()) throw channelUnavailable("Microsoft Teams");
        List<String> recipients = input.recipients() == null
                ? List.of()
                : input.recipients().stream()
                        .filter(Objects::nonNull)
                        .map(value -> value.trim().toLowerCase(Locale.ROOT))
                        .distinct()
                        .toList();
        if (channels.contains("email")) {
            if (recipients.isEmpty()
                    || recipients.size() > 10
                    || recipients.stream()
                            .anyMatch(value -> !EMAIL.matcher(value).matches()))
                throw invalid("Add between 1 and 10 valid alert email recipients");
        } else if (!recipients.isEmpty()) {
            throw invalid("Email recipients are only allowed when email delivery is selected");
        }
        try {
            ZoneId.of(timezone);
        } catch (RuntimeException error) {
            throw invalid("The site timezone is invalid");
        }
        boolean enabled = Boolean.TRUE.equals(input.enabled());
        String cron = "0 " + time.getMinute() + " " + time.getHour() + " * * ?";
        return new Normalized(name, metric, direction, baseline, threshold, time, channels, recipients, enabled, cron);
    }

    private static String normalizeChoice(String input, Set<String> allowed, String label) {
        String value = input == null ? "" : input.toLowerCase(Locale.ROOT);
        if (!allowed.contains(value)) throw invalid("Choose a supported alert " + label);
        return value;
    }

    private AlertView find(UUID siteId, UUID id) {
        sites.site(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select id,name,metric,direction,baseline,threshold_percent,local_time,timezone,channels,recipients,enabled,last_evaluated_date,last_evaluated_at,last_status,last_message,last_value,last_change_percent,last_baseline_date "
                                + "from analytics_alert where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, id);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) throw notFound();
                return view(rows);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load analytics alert", error);
        }
    }

    private AlertView view(ResultSet row) throws SQLException {
        UUID id = row.getObject(1, UUID.class);
        LocalDate lastDate = row.getObject(12, LocalDate.class);
        Timestamp evaluatedAt = row.getTimestamp(13);
        Instant next = null;
        String nextLocal = null;
        try {
            Trigger trigger = scheduler.getTrigger(triggerKey(id));
            if (trigger != null && trigger.getNextFireTime() != null) {
                next = trigger.getNextFireTime().toInstant();
                nextLocal = LOCAL_STAMP.format(next.atZone(ZoneId.of(row.getString(8))));
            }
        } catch (SchedulerException ignored) {
        }
        BigDecimal lastValue = row.getBigDecimal(16);
        BigDecimal change = row.getBigDecimal(17);
        return new AlertView(
                id,
                row.getString(2),
                row.getString(3),
                row.getString(4),
                row.getString(5),
                row.getBigDecimal(6),
                row.getObject(7, LocalTime.class),
                row.getString(8),
                stringArray(row.getArray(9)),
                stringArray(row.getArray(10)),
                row.getBoolean(11),
                lastDate,
                evaluatedAt == null ? null : evaluatedAt.toInstant(),
                row.getString(14),
                row.getString(15),
                lastValue,
                change,
                row.getObject(18, LocalDate.class),
                nextLocal,
                next);
    }

    private long count(UUID siteId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("select count(*) from analytics_alert where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet rows = statement.executeQuery()) {
                rows.next();
                return rows.getLong(1);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not count analytics alerts", error);
        }
    }

    private boolean exists(UUID siteId, UUID id) {
        try {
            find(siteId, id);
            return true;
        } catch (ControlPlaneException error) {
            if (error.status == 404) return false;
            throw error;
        }
    }

    private Site requireAdmin(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private boolean slackConfigured() {
        return validWebhook(slackWebhookUrl, true);
    }

    private boolean teamsConfigured() {
        return validWebhook(teamsWebhookUrl, false);
    }

    private static boolean validWebhook(String endpoint, boolean slack) {
        if (endpoint == null || endpoint.isBlank()) return false;
        try {
            URI uri = URI.create(endpoint);
            String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.ROOT);
            if (!"https".equalsIgnoreCase(uri.getScheme())
                    || uri.getUserInfo() != null
                    || uri.getFragment() != null
                    || uri.getPort() != -1 && uri.getPort() != 443) return false;
            if (slack) return SLACK_HOSTS.contains(host) && uri.getPath().startsWith("/services/");
            return TEAMS_HOST_SUFFIXES.stream().anyMatch(suffix -> host.equals(suffix) || host.endsWith("." + suffix));
        } catch (RuntimeException invalid) {
            return false;
        }
    }

    private static String metricLabel(String metric) {
        return switch (metric) {
            case "visitors" -> "Unique visitors";
            case "sessions" -> "Sessions";
            case "page_views" -> "Page views";
            case "bounce_rate" -> "Bounce rate";
            default -> metric;
        };
    }

    private static String value(String metric, double value) {
        return "bounce_rate".equals(metric)
                ? String.format(Locale.ROOT, "%.2f%%", value)
                : String.format(Locale.ROOT, "%.0f", value);
    }

    private static String signed(double value) {
        return String.format(Locale.ROOT, "%+.1f", value);
    }

    private static List<String> stringArray(Array value) throws SQLException {
        if (value == null) return List.of();
        Object raw = value.getArray();
        if (raw instanceof String[] values) return List.of(values);
        return List.of((Object[]) raw).stream().map(String.class::cast).toList();
    }

    private static JobKey jobKey(UUID id) {
        return JobKey.jobKey(id.toString(), GROUP);
    }

    private static TriggerKey triggerKey(UUID id) {
        return TriggerKey.triggerKey(id.toString(), GROUP);
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "INVALID_ANALYTICS_ALERT", message);
    }

    private static ControlPlaneException channelUnavailable(String channel) {
        return new ControlPlaneException(
                409, "ALERT_CHANNEL_UNAVAILABLE", channel + " delivery is not configured by the server administrator");
    }

    private static ControlPlaneException notFound() {
        return new ControlPlaneException(404, "ALERT_NOT_FOUND", "Analytics alert not found");
    }

    private record Normalized(
            String name,
            String metric,
            String direction,
            String baseline,
            BigDecimal thresholdPercent,
            LocalTime localTime,
            List<String> channels,
            List<String> recipients,
            boolean enabled,
            String cron) {}

    private record Evaluation(
            UUID id,
            UUID siteId,
            String siteName,
            String name,
            String metric,
            String direction,
            String baseline,
            BigDecimal thresholdPercent,
            List<String> channels,
            List<String> recipients,
            String timezone,
            LocalDate lastEvaluatedDate) {
        String baselineLabel() {
            return "same_weekday_last_week".equals(baseline) ? "same weekday last week" : "previous day";
        }
    }

    public record AlertView(
            UUID id,
            String name,
            String metric,
            String direction,
            String baseline,
            BigDecimal thresholdPercent,
            LocalTime localTime,
            String timezone,
            List<String> channels,
            List<String> recipients,
            boolean enabled,
            LocalDate lastEvaluatedDate,
            Instant lastEvaluatedAt,
            String lastStatus,
            String lastMessage,
            BigDecimal lastValue,
            BigDecimal lastChangePercent,
            LocalDate lastBaselineDate,
            String nextRunLocal,
            Instant nextRunAt) {}

    public record ListResponse(
            boolean emailEnabled,
            boolean slackEnabled,
            boolean teamsEnabled,
            boolean canManage,
            String timezone,
            List<AlertView> alerts) {}
}
