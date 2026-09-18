package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.UUID;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;

@ApplicationScoped
@DisallowConcurrentExecution
public class AnalyticsAlertJob implements Job {
    @Inject
    AnalyticsAlertService alerts;

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        try {
            alerts.run(UUID.fromString(context.getMergedJobDataMap().getString("alertId")));
        } catch (RuntimeException error) {
            throw new JobExecutionException(error, false);
        }
    }
}
