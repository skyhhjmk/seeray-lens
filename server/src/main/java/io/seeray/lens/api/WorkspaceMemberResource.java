package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceMemberService;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/members")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceMemberResource {
    private final WorkspaceMemberService members;

    public WorkspaceMemberResource(WorkspaceMemberService members) {
        this.members = members;
    }

    @GET
    public List<WorkspaceMemberService.MemberDto> list(@PathParam("workspaceId") UUID workspaceId) {
        return members.list(workspaceId);
    }

    @POST
    public Response add(@PathParam("workspaceId") UUID workspaceId, AddMemberRequest request) {
        return Response.status(Response.Status.CREATED)
                .entity(members.add(workspaceId, request.email(), request.role()))
                .build();
    }

    @PATCH
    @Path("/{userId}")
    public WorkspaceMemberService.MemberDto changeRole(
            @PathParam("workspaceId") UUID workspaceId, @PathParam("userId") UUID userId, ChangeRoleRequest request) {
        return members.changeRole(workspaceId, userId, request.role());
    }

    @POST
    @Path("/{userId}/transfer-ownership")
    public WorkspaceMemberService.MemberDto transferOwnership(
            @PathParam("workspaceId") UUID workspaceId, @PathParam("userId") UUID userId) {
        return members.transferOwnership(workspaceId, userId);
    }

    @DELETE
    @Path("/{userId}")
    public Response remove(@PathParam("workspaceId") UUID workspaceId, @PathParam("userId") UUID userId) {
        members.remove(workspaceId, userId);
        return Response.noContent().build();
    }

    public record AddMemberRequest(@NotBlank @Email @Size(max = 320) String email, @NotBlank String role) {}

    public record ChangeRoleRequest(@NotBlank String role) {}
}
