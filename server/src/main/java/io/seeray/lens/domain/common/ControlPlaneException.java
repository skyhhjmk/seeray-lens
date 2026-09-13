package io.seeray.lens.domain.common;

public class ControlPlaneException extends RuntimeException {
    public final int status;
    public final String code;

    public ControlPlaneException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }
}
