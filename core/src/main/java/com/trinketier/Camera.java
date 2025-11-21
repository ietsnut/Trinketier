package com.trinketier;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.graphics.PerspectiveCamera;
import com.badlogic.gdx.math.Vector3;

public class Camera {
    public PerspectiveCamera innerCam;

    private final Vector3 tmp = new Vector3();
    private final Vector3 movement = new Vector3();

    public Camera(float fov, float viewportWidth, float viewportHeight) {
        innerCam = new PerspectiveCamera(fov, viewportWidth, viewportHeight);
        innerCam.position.set(0f, 1.7f, 5f); // Eye level (approx 1.7 meters)
        innerCam.lookAt(0f, 1.7f, 0f);
        innerCam.near = 0.1f;
        innerCam.far = 300f;
        innerCam.update();
    }

    public void update() {
        innerCam.update();
    }

    // --- Movement Logic ---

    /**
     * Moves the camera relative to its current direction
     */
    public void moveRelative(float forwardSpeed, float strafeSpeed) {
        // Forward/Back
        tmp.set(innerCam.direction).y = 0; // Flatten direction so we don't fly up/down
        tmp.nor().scl(forwardSpeed);
        innerCam.position.add(tmp);

        // Left/Right
        tmp.set(innerCam.direction).crs(innerCam.up).y = 0;
        tmp.nor().scl(strafeSpeed);
        innerCam.position.add(tmp);
    }

    /**
     * Rotates the camera based on mouse/touch delta
     */
    public void look(float deltaX, float deltaY) {
        innerCam.direction.rotate(innerCam.up, -deltaX);

        tmp.set(innerCam.direction).crs(innerCam.up).nor();
        innerCam.direction.rotate(tmp, -deltaY);
    }

    // Getters for external usage (Billboard/Raycasting)
    public Vector3 getPosition() { return innerCam.position; }
    public Vector3 getUp() { return innerCam.up; }
    public PerspectiveCamera getPerspective() { return innerCam; }

    public void resize(int width, int height) {
        innerCam.viewportWidth = width;
        innerCam.viewportHeight = height;
        innerCam.update();
    }
}
