package io.seeray.lens.application;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import org.junit.jupiter.api.Test;

class SourceMapV3Test {
    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void mapsGeneratedPositionAndDropsEmbeddedSourceText() throws Exception {
        var input = mapper.readTree(
                """
                {"version":3,"file":"app.js","sources":["../src/app.ts"],
                 "sourcesContent":["private application source"],"names":["render"],"mappings":"AAAAA"}
                """);

        SourceMapV3.Prepared prepared = SourceMapV3.prepare(input, mapper);
        SourceMapV3.Mapping mapping = prepared.decoder().originalPosition(1, 0);

        assertNotNull(mapping);
        assertEquals("/src/app.ts", mapping.source());
        assertEquals(1, mapping.line());
        assertEquals(0, mapping.column());
        assertEquals("render", mapping.name());
        assertFalse(prepared.json().has("sourcesContent"));
    }

    @Test
    void usesNearestPriorGeneratedColumnAndRejectsIndexedMaps() throws Exception {
        var input = mapper.readTree(
                """
                {"version":3,"sources":["src/app.ts"],"names":[],"mappings":"AAAA,EACA"}
                """);
        SourceMapV3.Mapping mapping =
                SourceMapV3.prepare(input, mapper).decoder().originalPosition(1, 3);
        assertNotNull(mapping);
        assertEquals(2, mapping.line());

        var indexed = mapper.readTree("{\"version\":3,\"sections\":[]}");
        assertEquals(
                "INVALID_SOURCE_MAP",
                assertThrows(ControlPlaneException.class, () -> SourceMapV3.prepare(indexed, mapper)).code);
    }
}
