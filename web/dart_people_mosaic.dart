import 'dart:html';
import 'dart:async';
import "dart:js" as js;
import 'package:google_plus_v1_api/plus_v1_api_browser.dart';
import 'package:google_plus_v1_api/plus_v1_api_client.dart' as plus;
import 'package:google_oauth2_client/google_oauth2_browser.dart';

const String CLIENT_ID = "YOUR_CLIENT_ID_HERE";

// Make photo mosaic with RES * RES photos
const int RES = 100;

// Each "pixel" of the photo mosaic is SIZE * SIZE pixels large
const int SIZE = 20;

GoogleOAuth2 auth;
Plus client;
Map me = {};
List<Map> personData = [];
Map<String, Element> dom;
CanvasRenderingContext2D mainCtx;
int maxUses = 0;
int tolerance = 5000;

/**
 * Display a status message
 */
void updateState(String msg) {
  dom["state"].text = msg;
}

/**
 * Calculate a comparable "color distance"
 */
num colorDistance(r1, g1, b1, r2, g2, b2) {
  var dr = r1 - r2;
  var dg = g1 - g2;
  var db = b1 - b2;
  return dr * dr + dg * dg + db * db;
}

/**
 * Initialization
 */
void main() {
  // Store DOM elements for easier access
  dom = {
   "login": querySelector("#login"),
   "disconnect": querySelector("#disconnect"),
   "app": querySelector("#app"),
   "result": querySelector("#result"),
   "controls": querySelector("#controls"),
   "state": querySelector("#state"),
   "progress": querySelector("#progress"),
   "mosaic": querySelector("#mosaic"),
   "photo": querySelector("#photo"),
   "zoom": querySelector("#zoom"),
   "create": querySelector("#create"),
   "tolerance": querySelector("#tolerance")
  };

  mainCtx = (dom["mosaic"] as CanvasElement).getContext("2d");

  // Initialize OAuth2-Flow Object
  auth = new GoogleOAuth2(
    CLIENT_ID,
    [Plus.PLUS_LOGIN_SCOPE]
  );

  // Initialize Google+ API Client
  client = new Plus(auth);

  dom["login"].onClick.listen((_) => auth.login().then(checkAuth));
  dom["login"].onKeyUp.listen((e) {
    var keyEvent = new KeyEvent.wrap(e);
    if (keyEvent.keyCode == KeyCode.ENTER || keyEvent.keyCode == KeyCode.SPACE) {
      auth.login().then(checkAuth);
    }
  });

  dom["disconnect"].onClick.listen((_) => disconnect());
  dom["disconnect"].onKeyUp.listen((e) {
    var keyEvent = new KeyEvent.wrap(e);
    if (keyEvent.keyCode == KeyCode.ENTER || keyEvent.keyCode == KeyCode.SPACE) {
      disconnect();
    }
  });

  dom["create"].onClick.listen((_) {
    // Hide/disable UI elements and start Mosaic creation
    dom["create"].attributes["disabled"] = "disabled";
    dom["result"].style.display = "none";
    dom["controls"].style.display = "none";
    dom["zoom"].text = "Show Full Size";
    dom["disconnect"].style.display = "none";
    calculateMosaic();
  });

  dom["zoom"].onClick.listen((_) {
    CanvasElement canvas = dom["mosaic"];
    if (canvas.style.width == "48%") {
      canvas.style.width = "auto";
      dom["zoom"].text = "Show Small Size";
    } else {
      canvas.style.width = "48%";
      dom["zoom"].text = "Show Full Size";
    }
  });
}

/**
 * Called upon success/failure of user authentication
 */
void checkAuth(Token token) {
  if (token != null) {
    client.makeAuthRequests = true;

    dom["login"].style.display = "none";
    dom["app"].style.display = "block";

    updateState("Fetching profile...");

    // Fetch the profile of the authenticated user
    client.people.get("me")
      .then(loadProfilePic)
      .catchError((e) => updateState("Error $e"));

  } else {
    dom["login"].style.display = "inline-block";
    dom["app"].style.display = "none";
  }
}

/**
 * Extract the pixel data of the profile image using a CanvasElement
 */
void loadProfilePic(plus.Person p) {
  updateState("Analyzing profile pic...");
  me["url"] = p.image.url;
  ImageElement img = new ImageElement();
  img.onLoad.listen((_) {
    CanvasElement canvas = new CanvasElement(width: RES, height: RES);
    CanvasRenderingContext2D ctx = canvas.getContext("2d");
    ctx.fillStyle = "#FFFFFF";
    ctx.fillRect(0, 0, RES, RES);
    ctx.drawImageScaled(img, 0, 0, RES, RES);
    ImageData data = ctx.getImageData(0, 0, RES, RES);

    // Store image data for later use
    me["imageData"] = data.data;

    loadPeople();
  });

  // Enable CORS-loading of image so we can use it on canvas
  img.crossOrigin = "Anonymous";

  img.src = me["url"];
}

/**
 * Get a "page" of people from the Google+ API
 */
void loadPeople({String pageToken}) {
  updateState("Fetching people... ${personData.length}");
  client.people.list("me", "visible", pageToken: pageToken)
    .then((plus.PeopleFeed list) {
      if (list.items.length > 0 ) {
        list.items.forEach((plus.Person p) {
          var data = {};
          data["url"] = p.image.url;
          personData.add(data);
        });
      }
      if (list.nextPageToken != null) {
        // Load next page of people
        loadPeople(pageToken: list.nextPageToken);
      } else {
        // All done, proceed to next step
        createImageData();
      }
    })
    .catchError((e) => updateState("Error $e"));
}

/**
 * Preload all profile images and extract colour information
 */
void createImageData() {
  var count = 0;
  updateState("Analyzing photos...");
  Future.forEach(personData, (p) {
    var completer = new Completer();
    ImageElement img = new ImageElement();

    img.onLoad.listen((_) {
      p["img"] = img;
      dom["progress"].append(img);

      ImageElement small_img = new ImageElement();

      small_img.onLoad.listen((_) {
        count += 1;
        updateState("Analyzing photos... $count / ${personData.length}");
        CanvasElement canvas = new CanvasElement(width: 1, height: 1);
        CanvasRenderingContext2D ctx = canvas.getContext("2d");
        ctx.fillStyle = "#FFFFFF";
        ctx.fillRect(0, 0, 1, 1);
        ctx.drawImageScaled(small_img, 0, 0, 1, 1);
        ImageData data = ctx.getImageData(0, 0, 1, 1);
        p["imageData"] = data.data;
        completer.complete();
      });

      // Enable CORS-loading of image so we can use it on canvas
      small_img.crossOrigin = "Anonymous";

      // Let Google handle the resizing to 1x1 pixels to get an average color
      small_img.src = p["url"] + "&sz=1";
    });

    // Enable CORS-loading of image so we can use it on canvas
    img.crossOrigin = "Anonymous";

    // Load exact image size for drawing the mosaic with
    img.src = p["url"] + "&sz=$SIZE";

    return completer.future;
  }).then((_) {
    // All done, display main UI
    updateState("");
    dom["disconnect"].style.display = "inline-block";
    dom["controls"].style.display = "block";
  });
}

/**
 * Prepare the canvas and start calculation for all pixels
 */
void calculateMosaic() {
  updateState("Creating mosaic...");
  tolerance = int.parse((dom["tolerance"] as InputElement).value, onError: ((_) => 5));
  if (tolerance <= 1) { tolerance = 1; }
  if (tolerance >= 100) { tolerance = 100; }
  tolerance = 1000 * tolerance;
  maxUses = 0;
  var pixels = [];

  List<num> response = [];

  for (var j = 0; j < personData.length; j++) {
    personData[j]["uses"] = 0;
    personData[j]["index"] = j;
  }

  for (var i = 0; i < me["imageData"].length; i += 4) {
    var r1 = me["imageData"][i];
    var g1 = me["imageData"][i + 1];
    var b1 = me["imageData"][i + 2];
    pixels.add([i ~/ 4, r1, g1, b1]);
  }

  CanvasElement canvas = dom["mosaic"];
  canvas.width = RES * SIZE;
  canvas.height = RES * SIZE;
  canvas.style.width = "48%";
  dom["result"].style.display = "block";

  // Display the actual profile image as comparison
  ImageElement img = dom["photo"];
  img.src = me["url"] + "&sz=500";
  img.style.width = "48%";

  mainCtx.fillStyle = "#FFFFFF";
  mainCtx.fillRect(0, 0, RES * SIZE, RES * SIZE);

  Future.wait(pixels.map((pixel) {
    return new Future(() => handlePixel(pixel));
  })).then((_) => finish());
}

/**
 * Find best match for one pixel of the profile image
 * and paint it on the canvas
 */
void handlePixel(List<num> pixel) {
  var best = [];
  var distance = [];
  var bestPerson;

  for (var i = 0; i <= maxUses; i++) {
    best.add(-1);
    distance.add(200000);
  }

  personData.forEach((p) {
    var uses = p["uses"];
    var r2 = p["imageData"][0];
    var g2 = p["imageData"][1];
    var b2 = p["imageData"][2];
    var d = colorDistance(pixel[1], pixel[2], pixel[3], r2, g2, b2);
    if (d < distance[uses]) {
      best[uses] = p["index"];
      distance[uses] = d;
    }
  });

  bestPerson = -1;
  for (var i = 0; i <= maxUses; i++) {
    if (i == maxUses || distance[i] <= tolerance) {
      bestPerson = best[i];
      break;
    }
  }

  if (bestPerson >= 0) {
    personData[bestPerson]["uses"]++;
    if (personData[bestPerson]["uses"] > maxUses) {
      maxUses = personData[bestPerson]["uses"];
    }

    var i = pixel[0];
    ImageElement img = personData[bestPerson]["img"];
    int x = i % RES * SIZE;
    int y = (i / RES).floor() * SIZE;
    mainCtx.drawImage(img, x, y);
  }
}

/**
 * All done, re-enable UI-controls
 */
void finish() {
  dom["create"].attributes.remove("disabled");
  dom["result"].style.display = "block";
  dom["controls"].style.display = "block";
  dom["disconnect"].style.display = "inline-block";
  updateState("");
}


/**
 * Call the OAuth2 endpoint to disconnect the app for the user
 * and reset the UI to the non-logged-in state
 */
void disconnect() {
  if (auth.token != null) {
    // JSONP workaround because the accounts.google.com endpoint doesn't allow CORS
    js.context["myJsonpCallback"] = ([jsonData]) {
      print("revoke response: $jsonData");

      // disable authenticated requests in the client library
      client.makeAuthRequests = false;
      auth.logout();

      dom["login"].style.display = "inline-block";
      dom["disconnect"].style.display = "none";
      dom["app"].style.display = "none";
      dom["result"].style.display = "none";
      dom["controls"].style.display = "none";
      dom["progress"].innerHtml = "";
    };

    ScriptElement script = new Element.tag("script");
    script.src = "https://accounts.google.com/o/oauth2/revoke?token=${auth.token.data}&callback=myJsonpCallback";
    document.body.children.add(script);
  }
}
