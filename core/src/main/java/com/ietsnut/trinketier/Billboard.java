package com.ietsnut.trinketier;

import com.badlogic.gdx.graphics.g2d.TextureRegion;
import com.badlogic.gdx.graphics.g3d.decals.Decal;

public class Billboard {

    public Decal decal;

    public Billboard(TextureRegion textureRegion, float x, float y, float z, float width, float height) {
        decal = Decal.newDecal(width, height, textureRegion, true);
        decal.setPosition(x, y, z);
    }

    public void update(Camera camera) {
        decal.setRotation(camera.innerCam.direction, camera.innerCam.up);
    }

}
