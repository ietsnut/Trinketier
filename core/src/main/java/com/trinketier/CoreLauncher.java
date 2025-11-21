package com.trinketier;

import com.badlogic.gdx.Application;
import com.badlogic.gdx.ApplicationAdapter;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Input;
import com.badlogic.gdx.InputAdapter;
import com.badlogic.gdx.graphics.Color;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.VertexAttributes;
import com.badlogic.gdx.graphics.g2d.TextureRegion;
import com.badlogic.gdx.graphics.g3d.Material;
import com.badlogic.gdx.graphics.g3d.Model;
import com.badlogic.gdx.graphics.g3d.ModelBatch;
import com.badlogic.gdx.graphics.g3d.ModelInstance;
import com.badlogic.gdx.graphics.g3d.attributes.ColorAttribute;
import com.badlogic.gdx.graphics.g3d.decals.CameraGroupStrategy;
import com.badlogic.gdx.graphics.g3d.decals.DecalBatch;
import com.badlogic.gdx.graphics.g3d.utils.ModelBuilder;
import com.badlogic.gdx.math.Intersector;
import com.badlogic.gdx.math.Plane;
import com.badlogic.gdx.math.Vector3;
import com.badlogic.gdx.math.collision.Ray;

public class CoreLauncher extends ApplicationAdapter {
    // Graphics
    private Camera camera;
    private ModelBatch modelBatch;
    private DecalBatch decalBatch;
    private Model floorModel;
    private ModelInstance floorInstance;
    private Texture image;
    private Billboard billboard;

    // Movement & Interaction
    private final Vector3 targetPosition = new Vector3();
    private boolean isMovingToTarget = false;
    private final Plane floorPlane = new Plane(Vector3.Y, 0); // Plane at Y=0
    private final Vector3 intersection = new Vector3();

    @Override
    public void create() {
        // 1. Setup Camera
        camera = new Camera(67, Gdx.graphics.getWidth(), Gdx.graphics.getHeight());

        // 2. Setup 3D Models (The Floor)
        modelBatch = new ModelBatch();
        ModelBuilder modelBuilder = new ModelBuilder();
        Material floorMaterial = new Material(ColorAttribute.createDiffuse(Color.DARK_GRAY));

        // Create a large flat box to act as the floor
        floorModel = modelBuilder.createBox(50f, 0.1f, 50f,
            floorMaterial,
            VertexAttributes.Usage.Position | VertexAttributes.Usage.Normal);
        floorInstance = new ModelInstance(floorModel);
        floorInstance.transform.translate(0, -0.05f, 0); // Move down slightly so feet are on 0

        // 3. Setup Billboard (Decals)
        image = new Texture("tree.png"); // Using your existing asset
        decalBatch = new DecalBatch(new CameraGroupStrategy(camera.getPerspective()));
        billboard = new Billboard(new TextureRegion(image), 0, 1.5f, -5f, 2f, 2f);

        // 4. Setup Input
        setupInput();
    }

    private void setupInput() {
        Gdx.input.setInputProcessor(new InputAdapter() {
            private int dragX, dragY;

            @Override
            public boolean touchDown(int screenX, int screenY, int pointer, int button) {
                dragX = screenX;
                dragY = screenY;

                // Mobile Tap-to-Move Logic
                if (Gdx.app.getType() == Application.ApplicationType.Android ||
                    Gdx.app.getType() == Application.ApplicationType.iOS) {

                    Ray ray = camera.getPerspective().getPickRay(screenX, screenY);
                    if (Intersector.intersectRayPlane(ray, floorPlane, intersection)) {
                        targetPosition.set(intersection);
                        targetPosition.y = 1.7f; // Keep eye level
                        isMovingToTarget = true;
                    }
                }
                return true;
            }

            @Override
            public boolean touchDragged(int screenX, int screenY, int pointer) {
                float deltaX = (screenX - dragX) * 0.1f;
                float deltaY = (screenY - dragY) * 0.1f;

                camera.look(deltaX, deltaY);

                dragX = screenX;
                dragY = screenY;

                // Cancel auto-walk if dragging to look around
                isMovingToTarget = false;
                return true;
            }
        });

        // Lock cursor on Desktop
        if (Gdx.app.getType() == Application.ApplicationType.Desktop) {
            Gdx.input.setCursorCatched(true);
        }
    }

    @Override
    public void render() {
        float deltaTime = Gdx.graphics.getDeltaTime();

        // --- Input Processing ---
        if (Gdx.app.getType() == Application.ApplicationType.Desktop) {
            handleDesktopInput(deltaTime);
        } else {
            handleMobileMovement(deltaTime);
        }

        camera.update();
        billboard.update(camera);

        // --- Rendering ---
        Gdx.gl.glViewport(0, 0, Gdx.graphics.getWidth(), Gdx.graphics.getHeight());
        Gdx.gl.glClearColor(0.1f, 0.1f, 0.15f, 1f);
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT | GL20.GL_DEPTH_BUFFER_BIT | (Gdx.graphics.getBufferFormat().coverageSampling?GL20.GL_COVERAGE_BUFFER_BIT_NV:0));

        // Draw 3D Models
        modelBatch.begin(camera.getPerspective());
        modelBatch.render(floorInstance);
        modelBatch.end();

        // Draw Billboards (Decals) - Must be done after ModelBatch usually
        decalBatch.add(billboard.decal); // Direct access or add getter in Billboard class
        decalBatch.flush();
    }

    private void handleDesktopInput(float delta) {
        float speed = 5.0f * delta;

        if (Gdx.input.isKeyPressed(Input.Keys.W)) camera.moveRelative(speed, 0);
        if (Gdx.input.isKeyPressed(Input.Keys.S)) camera.moveRelative(-speed, 0);
        if (Gdx.input.isKeyPressed(Input.Keys.A)) camera.moveRelative(0, -speed);
        if (Gdx.input.isKeyPressed(Input.Keys.D)) camera.moveRelative(0, speed);

        // Mouse Look (Continuous)
        float mouseX = Gdx.input.getDeltaX() * 0.2f;
        float mouseY = Gdx.input.getDeltaY() * 0.2f;
        camera.look(mouseX, mouseY);

        if (Gdx.input.isKeyJustPressed(Input.Keys.ESCAPE)) Gdx.app.exit();
    }

    private void handleMobileMovement(float delta) {
        if (isMovingToTarget) {
            Vector3 currentPos = camera.getPosition();
            float distance = currentPos.dst(targetPosition);
            float speed = 5.0f * delta;

            if (distance > 0.2f) {
                Vector3 direction = new Vector3(targetPosition).sub(currentPos).nor();
                currentPos.mulAdd(direction, speed);
            } else {
                isMovingToTarget = false; // Arrived
            }
        }
    }

    @Override
    public void resize(int width, int height) {
        camera.resize(width, height);
    }

    @Override
    public void dispose() {
        modelBatch.dispose();
        decalBatch.dispose();
        floorModel.dispose();
        image.dispose();
    }
}
