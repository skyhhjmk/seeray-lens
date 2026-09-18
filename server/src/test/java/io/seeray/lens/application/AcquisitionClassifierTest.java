package io.seeray.lens.application;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Set;
import org.junit.jupiter.api.Test;

class AcquisitionClassifierTest {
    @Test
    void classifiesCommonSearchSocialAndAiReferrers() {
        Set<String> internal = Set.of("shop.example.test");

        assertEquals(
                "search_engine",
                AcquisitionClassifier.channel(
                        "www.google.com", "shop.example.test", null, null, null, null, null, internal));
        assertEquals(
                "social",
                AcquisitionClassifier.channel(
                        "l.instagram.com", "shop.example.test", null, null, null, null, null, internal));
        assertEquals(
                "ai_assistant",
                AcquisitionClassifier.channel(
                        "chatgpt.com", "shop.example.test", null, null, null, null, null, internal));
        assertEquals(
                "direct",
                AcquisitionClassifier.channel(
                        "shop.example.test", "shop.example.test", null, null, null, null, null, internal));
    }

    @Test
    void campaignParametersTakePrecedenceAndPreserveSourceSemantics() {
        String channel = AcquisitionClassifier.channel(
                "www.google.com", "shop.example.test", null, null, null, "shoes", null, Set.of());

        assertEquals("campaign", channel);
        assertEquals("newsletter", AcquisitionClassifier.source("campaign", "www.google.com", "newsletter"));
        assertEquals("chatgpt.com", AcquisitionClassifier.source("ai_assistant", "chatgpt.com", null));
        assertEquals(null, AcquisitionClassifier.source("direct", null, null));
    }
}
