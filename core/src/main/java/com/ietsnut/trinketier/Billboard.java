package com.ietsnut.trinketier;

import com.badlogic.gdx.graphics.g2d.TextureRegion;
import com.badlogic.gdx.graphics.g3d.decals.Decal;
import com.badlogic.gdx.graphics.g3d.decals.DecalBatch;
import com.badlogic.gdx.math.Vector3;

public class Billboard {

    public Decal decal;

    private final Vector3 targetPos = new Vector3(); // Reusable vector to prevent Garbage Collection

    public Billboard(TextureRegion textureRegion, float x, float y, float z, float width, float height) {
        // Create a decal (a sprite in 3D space)
        decal = Decal.newDecal(width, height, textureRegion, true);
        decal.setPosition(x, y, z);
    }

    public void update(Camera camera) {
        // Get the camera's current position
        Vector3 camPos = camera.getPosition();

        // Set target to Camera X & Z, but keep the Billboard's own Y.
        // This creates a "flat" look vector, ensuring no vertical tilt.
        targetPos.set(camPos.x, decal.getY(), camPos.z);

        // Look at the calculated target, using World Up (Vector3.Y) to stay upright
        decal.lookAt(targetPos, Vector3.Y);
    }

    public void draw(DecalBatch decalBatch) {
        decalBatch.add(decal);
    }

    public void dispose() {
        // Decals don't strictly need disposal, but their textures do (handled in main)
    }
}
