package io.seeray.lens.api;

import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.validation.ConstraintViolationException;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import java.util.Map;

@Provider
public class ErrorMapper implements ExceptionMapper<ControlPlaneException> {
    @Override
    public Response toResponse(ControlPlaneException e) {
        return Response.status(e.status)
                .entity(Map.of("code", e.code, "message", e.getMessage()))
                .build();
    }
}

@Provider
class ValidationErrorMapper implements ExceptionMapper<ConstraintViolationException> {
    @Override
    public Response toResponse(ConstraintViolationException e) {
        return Response.status(400)
                .entity(Map.of("code", "VALIDATION_ERROR", "message", e.getMessage()))
                .build();
    }
}

@Provider
class IllegalArgumentErrorMapper implements ExceptionMapper<IllegalArgumentException> {
    @Override
    public Response toResponse(IllegalArgumentException e) {
        return Response.status(400)
                .entity(Map.of("code", "INVALID_ANALYTICS_RANGE", "message", e.getMessage()))
                .build();
    }
}
