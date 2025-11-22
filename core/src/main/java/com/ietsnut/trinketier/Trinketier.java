package com.ietsnut.trinketier;

import com.badlogic.gdx.Application;
import com.badlogic.gdx.ApplicationAdapter;
import com.badlogic.gdx.Gdx;
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
import com.crashinvaders.basisu.gdx.Ktx2TextureData;
import com.badlogic.gdx.graphics.glutils.HdpiUtils;

import java.io.IOException;

public class Trinketier extends ApplicationAdapter {

    private Camera camera;
    private ModelBatch modelBatch;
    private DecalBatch decalBatch;
    private Model floorModel;
    private ModelInstance floorInstance;
    private Texture image;
    private Billboard billboard;

    @Override
    public void create() {
        if (Gdx.app.getType() == Application.ApplicationType.Desktop) {
            Gdx.input.setCursorCatched(true);
        }

        camera = new Camera(67, Gdx.graphics.getWidth(), Gdx.graphics.getHeight());
        Gdx.input.setInputProcessor(camera);

        modelBatch = new ModelBatch();
        ModelBuilder modelBuilder = new ModelBuilder();
        Material floorMaterial = new Material(ColorAttribute.createDiffuse(Color.DARK_GRAY));
        floorModel = modelBuilder.createBox(50f, 0.1f, 50f, floorMaterial, VertexAttributes.Usage.Position | VertexAttributes.Usage.Normal);
        floorInstance = new ModelInstance(floorModel);
        floorInstance.transform.translate(0, -0.05f, 0);

        image = new Texture(new Ktx2TextureData(Gdx.files.internal("sun.ktx2")));
        decalBatch = new DecalBatch(new CameraGroupStrategy(camera.getPerspective()));
        billboard = new Billboard(new TextureRegion(image), 0, 1.5f, -5f, 2f, 2f);
        try {
            new App();
        } catch (IOException ioe) {
            System.err.println("Couldn't start server:\n" + ioe);
        }
    }

    @Override
    public void render() {
        float delta = Gdx.graphics.getDeltaTime();

        camera.update(delta);
        billboard.update(camera);

        HdpiUtils.glViewport(0, 0, Gdx.graphics.getBackBufferWidth(), Gdx.graphics.getHeight());
        //Gdx.gl.glViewport(0, 0, Gdx.graphics.getBackBufferWidth(), Gdx.graphics.getHeight());
        Gdx.gl.glClearColor(0.1f, 0.1f, 0.15f, 1f);
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT | GL20.GL_DEPTH_BUFFER_BIT);

        modelBatch.begin(camera.getPerspective());
        modelBatch.render(floorInstance);
        modelBatch.end();

        decalBatch.add(billboard.decal);
        decalBatch.flush();
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
