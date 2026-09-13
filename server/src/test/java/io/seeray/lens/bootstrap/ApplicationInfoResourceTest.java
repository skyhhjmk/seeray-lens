package io.seeray.lens.bootstrap;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

@QuarkusTest
class ApplicationInfoResourceTest {
    @Test
    void exposesBootstrapStatus() {
        given().when().get("/api/v1").then().statusCode(200).body("status", is("bootstrap"));
    }
}
