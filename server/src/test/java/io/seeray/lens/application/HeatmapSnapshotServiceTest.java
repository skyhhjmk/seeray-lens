package io.seeray.lens.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.seeray.lens.domain.common.ControlPlaneException;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

class HeatmapSnapshotServiceTest {

    @Test
    void readsSupportedPngFromItsActualBytes() throws Exception {
        BufferedImage image = new BufferedImage(2, 3, BufferedImage.TYPE_INT_ARGB);
        BufferedImage decoded = HeatmapSnapshotService.decodeSupportedImage(encoded(image, "png"));
        assertEquals(2, decoded.getWidth());
        assertEquals(3, decoded.getHeight());
    }

    @Test
    void rejectsGifEvenWhenTheCallerClaimsItIsAnImageSnapshot() throws Exception {
        BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_RGB);
        ControlPlaneException error = assertThrows(
                ControlPlaneException.class, () -> HeatmapSnapshotService.decodeSupportedImage(encoded(image, "gif")));
        assertEquals("UNSUPPORTED_SNAPSHOT", error.code);
    }

    private static byte[] encoded(BufferedImage image, String format) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        assertTrue(ImageIO.write(image, format, output));
        return output.toByteArray();
    }
}
