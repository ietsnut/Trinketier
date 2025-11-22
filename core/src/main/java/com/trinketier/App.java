package com.trinketier;

import fi.iki.elonen.NanoHTTPD;

import java.io.IOException;
import java.util.List;
import java.util.Map;

public class App extends NanoHTTPD {

    public App() throws IOException {
        super(8080);
        start(NanoHTTPD.SOCKET_READ_TIMEOUT, false);
        System.out.println("\nRunning! Point your browsers to http://localhost:8080/ \n");
    }

    @Override
    public Response serve(IHTTPSession session) {
        String msg = "<html><body><h1>Hello server</h1>\n";
        Map<String, List<String>> parms = session.getParameters();
        if (!parms.containsKey("username")) {
            msg += "<form action='?' method='get'>\n  <p>Your name: <input type='text' name='username'></p>\n" + "</form>\n";
        } else {
            msg += "<p>Hello, " + parms.get("username").get(0) + "!</p>";
            System.out.println(parms.get("username").get(0));
        }

        return newFixedLengthResponse(msg + "</body></html>\n");
    }
}
