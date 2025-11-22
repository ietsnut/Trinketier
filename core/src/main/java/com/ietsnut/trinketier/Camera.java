package com.ietsnut.trinketier;

import com.badlogic.gdx.Application;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Input;
import com.badlogic.gdx.InputProcessor;
import com.badlogic.gdx.graphics.PerspectiveCamera;
import com.badlogic.gdx.math.Intersector;
import com.badlogic.gdx.math.MathUtils;
import com.badlogic.gdx.math.Plane;
import com.badlogic.gdx.math.Vector3;
import com.badlogic.gdx.math.collision.Ray;

public class Camera implements InputProcessor {
    public PerspectiveCamera innerCam;
    private final boolean isDesktop;

    private float pitch = 0;
    private float yaw = 0;

    private boolean moveW, moveS, moveA, moveD;

    // Logic for Click-to-Walk
    private boolean isWalkingToTarget = false;
    private final Vector3 targetPosition = new Vector3();
    private final Plane floorPlane = new Plane(Vector3.Y, 0);
    private final Vector3 intersection = new Vector3();

    // Logic for separating Drag vs Tap
    private boolean isDragging = false;

    private final Vector3 tmp = new Vector3();
    private final Vector3 movement = new Vector3();
    private final Vector3 directionTmp = new Vector3();

    private final static float mouseSensitivity = 0.2f;

    public Camera(float fov, float width, float height) {
        innerCam = new PerspectiveCamera(fov, width, height);
        innerCam.position.set(0f, 1.7f, 5f);
        innerCam.near = 0.1f;
        innerCam.far = 300f;
        innerCam.update();

        isDesktop = Gdx.app.getType() == Application.ApplicationType.Desktop;
    }

    public void update(float deltaTime) {
        // 1. Rotation Logic
        float yawRad = yaw * MathUtils.degreesToRadians;
        float pitchRad = pitch * MathUtils.degreesToRadians;

        directionTmp.set(
            MathUtils.sin(yawRad) * MathUtils.cos(pitchRad),
            MathUtils.sin(pitchRad),
            MathUtils.cos(yawRad) * MathUtils.cos(pitchRad)
        ).nor();

        innerCam.direction.set(directionTmp);
        innerCam.up.set(Vector3.Y);

        // 2. Movement Logic
        float moveSpeed = 5.0f * deltaTime;
        movement.setZero();

        // WASD Movement
        if (moveW || moveS || moveA || moveD) {
            isWalkingToTarget = false;
            if (moveW) {
                tmp.set(innerCam.direction).y = 0;
                movement.add(tmp.nor().scl(moveSpeed));
            }
            if (moveS) {
                tmp.set(innerCam.direction).y = 0;
                movement.add(tmp.nor().scl(-moveSpeed));
            }
            if (moveA) {
                tmp.set(innerCam.direction).crs(innerCam.up).y = 0;
                movement.add(tmp.nor().scl(-moveSpeed));
            }
            if (moveD) {
                tmp.set(innerCam.direction).crs(innerCam.up).y = 0;
                movement.add(tmp.nor().scl(moveSpeed));
            }
        } else if (isWalkingToTarget) {
            // Auto-walk to tap target
            tmp.set(targetPosition).sub(innerCam.position).y = 0;

            float distance = tmp.len();
            if (distance < 0.1f) {
                isWalkingToTarget = false;
            } else {
                float step = Math.min(moveSpeed, distance);
                movement.add(tmp.nor().scl(step));
            }
        }

        innerCam.position.add(movement);
        innerCam.update();
    }

    private void rotateCamera(float deltaX, float deltaY) {
        yaw += deltaX;
        pitch += deltaY;
        yaw = yaw % 360;
        pitch = MathUtils.clamp(pitch, -89f, 89f);
    }

    @Override
    public boolean mouseMoved(int screenX, int screenY) {
        // Desktop: Look around when moving mouse (hover)
        if (isDesktop) {
            float deltaX = -Gdx.input.getDeltaX() * mouseSensitivity;
            float deltaY = -Gdx.input.getDeltaY() * mouseSensitivity;
            rotateCamera(deltaX, deltaY);
        }
        return true;
    }

    @Override
    public boolean touchDragged(int screenX, int screenY, int pointer) {
        // Mobile: Drag to look
        // Desktop: Drag to look (if holding button)
        isDragging = true;

        float deltaX = -Gdx.input.getDeltaX() * mouseSensitivity;
        float deltaY = -Gdx.input.getDeltaY() * mouseSensitivity;
        rotateCamera(deltaX, deltaY);

        return true;
    }

    @Override
    public boolean touchDown(int screenX, int screenY, int pointer, int button) {
        isDragging = false;
        return true;
    }

    @Override
    public boolean touchUp(int screenX, int screenY, int pointer, int button) {
        // If Desktop, ignore "Tap to Walk" so you can shoot/click freely
        if (isDesktop) {
            return false;
        }

        // Mobile: If it was a Tap (not a drag), Walk
        if (!isDragging) {
            Ray ray = innerCam.getPickRay(screenX, screenY);
            if (Intersector.intersectRayPlane(ray, floorPlane, intersection)) {
                targetPosition.set(intersection.x, 1.7f, intersection.z);
                isWalkingToTarget = true;
            }
        }
        return true;
    }

    @Override
    public boolean keyDown(int keycode) {
        switch (keycode) {
            case Input.Keys.W: moveW = true; break;
            case Input.Keys.S: moveS = true; break;
            case Input.Keys.A: moveA = true; break;
            case Input.Keys.D: moveD = true; break;
            case Input.Keys.ESCAPE: Gdx.app.exit(); break;
            case Input.Keys.TAB: Gdx.input.setCursorCatched(false); break;
        }
        return true;
    }

    @Override
    public boolean keyUp(int keycode) {
        switch (keycode) {
            case Input.Keys.W: moveW = false; break;
            case Input.Keys.S: moveS = false; break;
            case Input.Keys.A: moveA = false; break;
            case Input.Keys.D: moveD = false; break;
        }
        return true;
    }

    @Override public boolean keyTyped(char character) { return false; }
    @Override public boolean touchCancelled(int screenX, int screenY, int pointer, int button) { return false; }
    @Override public boolean scrolled(float amountX, float amountY) { return false; }

    public PerspectiveCamera getPerspective() { return innerCam; }
    public Vector3 getPosition() { return innerCam.position; }

    public void resize(int width, int height) {
        innerCam.viewportWidth = width;
        innerCam.viewportHeight = height;
        innerCam.update();
    }
}
