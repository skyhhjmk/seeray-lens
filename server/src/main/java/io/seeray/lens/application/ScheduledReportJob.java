package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;

@ApplicationScoped
@DisallowConcurrentExecution
public class ScheduledReportJob implements Job {
    @Inject
    ScheduledReportService reports;

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        try {
            reports.run(java.util.UUID.fromString(context.getMergedJobDataMap().getString("scheduleId")));
        } catch (RuntimeException error) {
            throw new JobExecutionException(error, false);
        }
    }
}
