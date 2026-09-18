package io.seeray.lens.application;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.seeray.lens.api.ScheduledReportResource.ReportInput;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
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
public class ScheduledReportService {
    private static final String GROUP = "scheduled-analytics-report";
    private static final Set<String> SECTIONS = Set.of("overview", "pages", "acquisition");
    private static final Set<String> WEEKDAYS = Set.of("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN");
    private static final Pattern EMAIL = Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");

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

    public ListResponse list(UUID siteId) {
        Site site = sites.site(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        List<ReportView> result = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select id,name,frequency,weekday,month_day,local_time,timezone,recipients,sections,enabled,last_run_at,last_run_status,last_run_period,last_run_message "
                                + "from scheduled_analytics_report where site_id=? order by created_at,id")) {
            statement.setObject(1, siteId);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) result.add(view(rows));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list scheduled reports", error);
        }
        return new ListResponse(emailEnabled, canManage, site.timezone, List.copyOf(result));
    }

    @Transactional
    public ReportView create(UUID siteId, ReportInput input) {
        Site site = requireAdmin(siteId);
        Normalized normalized = normalize(input, site.timezone);
        if (normalized.enabled() && !emailEnabled) throw emailDisabled();
        if (count(siteId) >= 20)
            throw new ControlPlaneException(409, "REPORT_LIMIT", "A site can have at most 20 scheduled reports");
        UUID id = UuidV7.next();
        Instant now = Instant.now();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into scheduled_analytics_report(id,site_id,name,frequency,weekday,month_day,local_time,timezone,recipients,sections,enabled,created_at,updated_at) "
                                + "values(?,?,?,?,?,?,?,?,?,?,?,?,?)")) {
            statement.setObject(1, id);
            statement.setObject(2, siteId);
            statement.setString(3, normalized.name());
            statement.setString(4, normalized.frequency());
            statement.setString(5, normalized.weekday());
            if (normalized.monthDay() == null) statement.setNull(6, Types.SMALLINT);
            else statement.setInt(6, normalized.monthDay());
            statement.setObject(7, normalized.localTime());
            statement.setString(8, site.timezone);
            statement.setArray(
                    9, connection.createArrayOf("text", normalized.recipients().toArray()));
            statement.setArray(
                    10, connection.createArrayOf("text", normalized.sections().toArray()));
            statement.setBoolean(11, normalized.enabled());
            statement.setTimestamp(12, Timestamp.from(now));
            statement.setTimestamp(13, Timestamp.from(now));
            statement.executeUpdate();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save scheduled report", error);
        }
        synchronizeSchedule(id, site, normalized);
        return find(siteId, id);
    }

    @Transactional
    public ReportView update(UUID siteId, UUID reportId, ReportInput input) {
        Site site = requireAdmin(siteId);
        Normalized normalized = normalize(input, site.timezone);
        if (normalized.enabled() && !emailEnabled) throw emailDisabled();
        if (!exists(siteId, reportId)) throw notFound();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "update scheduled_analytics_report set name=?,frequency=?,weekday=?,month_day=?,local_time=?,timezone=?,recipients=?,sections=?,enabled=?,updated_at=now() where id=? and site_id=?")) {
            statement.setString(1, normalized.name());
            statement.setString(2, normalized.frequency());
            statement.setString(3, normalized.weekday());
            if (normalized.monthDay() == null) statement.setNull(4, Types.SMALLINT);
            else statement.setInt(4, normalized.monthDay());
            statement.setObject(5, normalized.localTime());
            statement.setString(6, site.timezone);
            statement.setArray(
                    7, connection.createArrayOf("text", normalized.recipients().toArray()));
            statement.setArray(
                    8, connection.createArrayOf("text", normalized.sections().toArray()));
            statement.setBoolean(9, normalized.enabled());
            statement.setObject(10, reportId);
            statement.setObject(11, siteId);
            statement.executeUpdate();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not update scheduled report", error);
        }
        synchronizeSchedule(reportId, site, normalized);
        return find(siteId, reportId);
    }

    @Transactional
    public void delete(UUID siteId, UUID reportId) {
        requireAdmin(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from scheduled_analytics_report where id=? and site_id=?")) {
            statement.setObject(1, reportId);
            statement.setObject(2, siteId);
            if (statement.executeUpdate() == 0) throw notFound();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not delete scheduled report", error);
        }
        try {
            scheduler.deleteJob(jobKey(reportId));
        } catch (SchedulerException error) {
            throw new IllegalStateException("Could not remove scheduled delivery", error);
        }
    }

    public ReportView sendNow(UUID siteId, UUID reportId) {
        requireAdmin(siteId);
        ReportView report = find(siteId, reportId);
        if (!emailEnabled) throw emailDisabled();
        deliver(reportId, true);
        return find(siteId, reportId);
    }

    public void run(UUID reportId) {
        if (!deliver(reportId, false)) {
            try {
                scheduler.deleteJob(jobKey(reportId));
            } catch (SchedulerException error) {
                throw new IllegalStateException("Could not remove orphaned scheduled report", error);
            }
        }
    }

    private boolean deliver(UUID reportId, boolean force) {
        ReportView report;
        UUID siteId;
        String timezone;
        List<String> recipients;
        List<String> sections;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select r.site_id,r.timezone,r.name,r.frequency,r.recipients,r.sections from scheduled_analytics_report r where r.id=? and (?=true or r.enabled=true)")) {
            statement.setObject(1, reportId);
            statement.setBoolean(2, force);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return false;
                siteId = row.getObject(1, UUID.class);
                timezone = row.getString(2);
                recipients = stringArray(row.getArray(5));
                sections = stringArray(row.getArray(6));
                report = new ReportView(
                        reportId,
                        row.getString(3),
                        row.getString(4),
                        null,
                        null,
                        null,
                        timezone,
                        List.of(),
                        List.of(),
                        true,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load scheduled report", error);
        }

        try {
            if (!emailEnabled) throw emailDisabled();
            ZoneId zone = ZoneId.of(timezone);
            PeriodRange period = PeriodRange.previous(report.frequency(), LocalDate.now(zone));
            Digest digest = loadDigest(siteId, period, sections);
            String csv = digest.csv();
            String subject = report.name() + " — " + period.from() + " to " + period.to();
            String body = "Analytics report for " + report.name() + "\n"
                    + "Site timezone: " + zone.getId() + "\n"
                    + "Period: " + period.from() + " to " + period.to() + " (completed site-local days)\n\n"
                    + digest.summary();
            for (String recipient : recipients) {
                Mail mail = Mail.withText(recipient, subject, body)
                        .addAttachment(
                                "analytics-report.csv",
                                csv.getBytes(StandardCharsets.UTF_8),
                                "text/csv; charset=UTF-8");
                mailer.send(mail);
            }
            setRunStatus(reportId, "sent", period.label(), null);
        } catch (Exception error) {
            setRunStatus(
                    reportId, "failed", null, "Delivery failed. Verify server SMTP connectivity and sender settings.");
        }
        return true;
    }

    private Digest loadDigest(UUID siteId, PeriodRange period, List<String> sections) throws SQLException {
        List<String[]> rows = new ArrayList<>();
        StringBuilder summary = new StringBuilder();
        if (sections.contains("overview")) {
            try (Connection connection = dataSource.getConnection();
                    PreparedStatement statement = connection.prepareStatement(
                            "select coalesce(sum(page_view_count),0),coalesce(sum(session_count),0) from analytics_site_daily where site_id=? and business_date between ? and ?")) {
                statement.setObject(1, siteId);
                statement.setObject(2, period.from());
                statement.setObject(3, period.to());
                try (ResultSet result = statement.executeQuery()) {
                    result.next();
                    long views = result.getLong(1), sessions = result.getLong(2);
                    rows.add(new String[] {"Overview", "Page views", Long.toString(views)});
                    rows.add(new String[] {"Overview", "Sessions", Long.toString(sessions)});
                    summary.append("Page views: ")
                            .append(views)
                            .append("\nSessions: ")
                            .append(sessions)
                            .append("\n");
                }
            }
            try (Connection connection = dataSource.getConnection();
                    PreparedStatement statement = connection.prepareStatement(
                            "select count(distinct visitor_id) from visitor_day_fact where site_id=? and business_date between ? and ?")) {
                statement.setObject(1, siteId);
                statement.setObject(2, period.from());
                statement.setObject(3, period.to());
                try (ResultSet result = statement.executeQuery()) {
                    result.next();
                    long visitors = result.getLong(1);
                    rows.add(new String[] {"Overview", "Unique visitors", Long.toString(visitors)});
                    summary.append("Unique visitors: ").append(visitors).append("\n");
                }
            }
        }
        if (sections.contains("pages")) {
            try (Connection connection = dataSource.getConnection();
                    PreparedStatement statement = connection.prepareStatement(
                            "select path,sum(page_view_count) as views from analytics_page_daily where site_id=? and business_date between ? and ? group by path order by views desc,path limit 20")) {
                statement.setObject(1, siteId);
                statement.setObject(2, period.from());
                statement.setObject(3, period.to());
                try (ResultSet result = statement.executeQuery()) {
                    summary.append("\nTop pages (up to 20):\n");
                    while (result.next()) {
                        String path = result.getString(1);
                        long views = result.getLong(2);
                        rows.add(new String[] {"Top pages", path, Long.toString(views)});
                        summary.append(path).append(" — ").append(views).append(" views\n");
                    }
                }
            }
        }
        if (sections.contains("acquisition")) {
            try (Connection connection = dataSource.getConnection();
                    PreparedStatement statement = connection.prepareStatement(
                            "select channel,coalesce(source,''),coalesce(medium,''),sum(session_count) as sessions from analytics_traffic_daily where site_id=? and business_date between ? and ? group by channel,source,medium order by sessions desc,channel limit 30")) {
                statement.setObject(1, siteId);
                statement.setObject(2, period.from());
                statement.setObject(3, period.to());
                try (ResultSet result = statement.executeQuery()) {
                    summary.append("\nTraffic sources (up to 30):\n");
                    while (result.next()) {
                        String label = result.getString(1) + " / " + result.getString(2) + " / " + result.getString(3);
                        long sessions = result.getLong(4);
                        rows.add(new String[] {"Acquisition", label, Long.toString(sessions)});
                        summary.append(label).append(" — ").append(sessions).append(" sessions\n");
                    }
                }
            }
        }
        return new Digest(rows, summary.toString());
    }

    private void setRunStatus(UUID id, String status, String period, String message) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "update scheduled_analytics_report set last_run_at=now(),last_run_status=?,last_run_period=?,last_run_message=?,updated_at=now() where id=?")) {
            statement.setString(1, status);
            statement.setString(2, period);
            statement.setString(3, message);
            statement.setObject(4, id);
            statement.executeUpdate();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not persist scheduled report delivery status", error);
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
                job = JobBuilder.newJob(ScheduledReportJob.class)
                        .withIdentity(jobKey(id))
                        .usingJobData("scheduleId", id.toString())
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
            throw new IllegalStateException("Could not update scheduled report delivery", error);
        }
    }

    private Normalized normalize(ReportInput input, String timezone) {
        if (input == null) throw new ControlPlaneException(400, "INVALID_REPORT", "Report details are required");
        String name = input.name() == null ? "" : input.name().trim();
        if (name.isBlank() || name.length() > 120 || name.chars().anyMatch(Character::isISOControl))
            throw invalid("A report name of 1 to 120 printable characters is required");
        String frequency = input.frequency() == null ? "" : input.frequency().toLowerCase(Locale.ROOT);
        String weekday = input.weekday() == null ? null : input.weekday().toUpperCase(Locale.ROOT);
        Integer monthDay = input.monthDay();
        if ("weekly".equals(frequency)) {
            if (weekday == null || !WEEKDAYS.contains(weekday) || monthDay != null)
                throw invalid("Choose one weekday for a weekly report");
        } else if ("monthly".equals(frequency)) {
            if (monthDay == null || monthDay < 1 || monthDay > 28 || weekday != null)
                throw invalid("Choose a monthly day between 1 and 28");
        } else throw invalid("Frequency must be weekly or monthly");
        LocalTime time;
        try {
            time = LocalTime.parse(input.localTime());
        } catch (RuntimeException error) {
            throw invalid("Choose a valid local delivery time");
        }
        List<String> recipients = input.recipients() == null
                ? List.of()
                : input.recipients().stream()
                        .filter(Objects::nonNull)
                        .map(value -> value.trim().toLowerCase(Locale.ROOT))
                        .distinct()
                        .toList();
        if (recipients.isEmpty()
                || recipients.size() > 10
                || recipients.stream().anyMatch(value -> !EMAIL.matcher(value).matches()))
            throw invalid("Add between 1 and 10 valid email recipients");
        List<String> sections = input.sections() == null
                ? List.of()
                : input.sections().stream()
                        .filter(Objects::nonNull)
                        .map(value -> value.toLowerCase(Locale.ROOT))
                        .distinct()
                        .sorted()
                        .toList();
        if (sections.isEmpty() || sections.size() > 3 || !SECTIONS.containsAll(sections))
            throw invalid("Choose at least one available report section");
        try {
            ZoneId.of(timezone);
        } catch (RuntimeException error) {
            throw invalid("The site timezone is invalid");
        }
        boolean enabled = Boolean.TRUE.equals(input.enabled());
        String cron = "weekly".equals(frequency)
                ? "0 " + time.getMinute() + " " + time.getHour() + " ? * " + weekday
                : "0 " + time.getMinute() + " " + time.getHour() + " " + monthDay + " * ?";
        return new Normalized(name, frequency, weekday, monthDay, time, recipients, sections, enabled, cron);
    }

    private Site requireAdmin(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private long count(UUID siteId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select count(*) from scheduled_analytics_report where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet result = statement.executeQuery()) {
                result.next();
                return result.getLong(1);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not count scheduled reports", error);
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

    private ReportView find(UUID siteId, UUID id) {
        Site site = sites.site(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select id,name,frequency,weekday,month_day,local_time,timezone,recipients,sections,enabled,last_run_at,last_run_status,last_run_period,last_run_message from scheduled_analytics_report where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, id);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) throw notFound();
                return view(rows);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load scheduled report", error);
        }
    }

    private ReportView view(ResultSet row) throws SQLException {
        UUID id = row.getObject(1, UUID.class);
        Instant lastRunAt =
                row.getTimestamp(11) == null ? null : row.getTimestamp(11).toInstant();
        String lastRunLocal = lastRunAt == null
                ? null
                : DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm").format(lastRunAt.atZone(ZoneId.of(row.getString(7))));
        Instant next = null;
        String nextLocal = null;
        try {
            Trigger trigger = scheduler.getTrigger(triggerKey(id));
            if (trigger != null && trigger.getNextFireTime() != null) {
                next = trigger.getNextFireTime().toInstant();
                nextLocal = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
                        .format(next.atZone(ZoneId.of(row.getString(7))));
            }
        } catch (SchedulerException ignored) {
        }
        return new ReportView(
                id,
                row.getString(2),
                row.getString(3),
                row.getString(4),
                row.getObject(5) == null ? null : ((Number) row.getObject(5)).intValue(),
                row.getObject(6, LocalTime.class),
                row.getString(7),
                stringArray(row.getArray(8)),
                stringArray(row.getArray(9)),
                row.getBoolean(10),
                lastRunAt,
                lastRunLocal,
                row.getString(12),
                row.getString(13),
                row.getString(14),
                nextLocal,
                next);
    }

    private static List<String> stringArray(Array value) throws SQLException {
        if (value == null) return List.of();
        return List.of((String[]) value.getArray());
    }

    private static JobKey jobKey(UUID id) {
        return JobKey.jobKey(id.toString(), GROUP);
    }

    private static TriggerKey triggerKey(UUID id) {
        return TriggerKey.triggerKey(id.toString(), GROUP);
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "INVALID_REPORT", message);
    }

    private static ControlPlaneException notFound() {
        return new ControlPlaneException(404, "REPORT_NOT_FOUND", "Scheduled report not found");
    }

    private static ControlPlaneException emailDisabled() {
        return new ControlPlaneException(
                409, "REPORT_EMAIL_DISABLED", "Email delivery is disabled by the server administrator");
    }

    private record Normalized(
            String name,
            String frequency,
            String weekday,
            Integer monthDay,
            LocalTime localTime,
            List<String> recipients,
            List<String> sections,
            boolean enabled,
            String cron) {}

    private record PeriodRange(LocalDate from, LocalDate to) {
        static PeriodRange previous(String frequency, LocalDate today) {
            if ("weekly".equals(frequency)) return new PeriodRange(today.minusDays(7), today.minusDays(1));
            LocalDate start = today.withDayOfMonth(1).minusMonths(1);
            return new PeriodRange(start, start.plusMonths(1).minusDays(1));
        }

        String label() {
            return from + " to " + to;
        }
    }

    private record Digest(List<String[]> rows, String summary) {
        String csv() {
            StringBuilder result = new StringBuilder("section,metric,value\r\n");
            for (String[] row : rows)
                result.append(csvCell(row[0]))
                        .append(',')
                        .append(csvCell(row[1]))
                        .append(',')
                        .append(csvCell(row[2]))
                        .append("\r\n");
            return result.toString();
        }

        private static String csvCell(String value) {
            String safe = value.matches("^[\\s]*[=+@\\-\\t\\r].*") ? "'" + value : value;
            return "\"" + safe.replace("\"", "\"\"") + "\"";
        }
    }

    public record ReportView(
            UUID id,
            String name,
            String frequency,
            String weekday,
            Integer monthDay,
            LocalTime localTime,
            String timezone,
            List<String> recipients,
            List<String> sections,
            boolean enabled,
            Instant lastRunAt,
            String lastRunLocal,
            String lastRunStatus,
            String lastRunPeriod,
            String lastRunMessage,
            String nextRunLocal,
            Instant nextRunAt) {}

    public record ListResponse(boolean emailEnabled, boolean canManage, String timezone, List<ReportView> reports) {}
}
