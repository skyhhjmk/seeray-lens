package io.seeray.lens.application;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class AnalyticsAlertServiceTest {
    @Test
    void computesPercentChangeAgainstAbsoluteBaselineAndHandlesZeroBaseline() {
        assertEquals(50, AnalyticsAlertService.percentChange(150, 100), 0.0001);
        assertEquals(-25, AnalyticsAlertService.percentChange(75, 100), 0.0001);
        assertEquals(0, AnalyticsAlertService.percentChange(0, 0), 0.0001);
        assertTrue(AnalyticsAlertService.percentChange(1, 0) > 1000);
    }

    @Test
    void triggersOnlyTheConfiguredDirectionAtOrBeyondThreshold() {
        assertTrue(AnalyticsAlertService.shouldTrigger("increase", 20, 20));
        assertTrue(AnalyticsAlertService.shouldTrigger("increase", 30, 20));
        assertFalse(AnalyticsAlertService.shouldTrigger("increase", 19.99, 20));
        assertTrue(AnalyticsAlertService.shouldTrigger("decrease", -20, 20));
        assertFalse(AnalyticsAlertService.shouldTrigger("decrease", -19.99, 20));
        assertFalse(AnalyticsAlertService.shouldTrigger("decrease", 20, 20));
    }
}
